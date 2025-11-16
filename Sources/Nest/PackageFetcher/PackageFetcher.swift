import Foundation
import Subprocess
import System

// MARK: - Fetcher Errors

struct GitError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

public enum PackageFetcherError: Error, LocalizedError {
    case cloneFailed(String, underlying: Error?)
    case checkoutFailed(String, version: String)
    case copyFailed(URL, underlying: Error?)
    case invalidPackageStructure(URL)
    case versionNotFound(String)
    case gitOperationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .cloneFailed(url, error):
            if let error = error {
                return "Failed to clone repository '\(url)': \(error.localizedDescription)"
            }
            return "Failed to clone repository '\(url)'"
        case let .checkoutFailed(url, version):
            return "Failed to checkout version '\(version)' for repository '\(url)'"
        case let .copyFailed(source, error):
            if let error = error {
                return "Failed to copy package from '\(source.path)': \(error.localizedDescription)"
            }
            return "Failed to copy package from '\(source.path)'"
        case let .invalidPackageStructure(url):
            return "Invalid package structure at '\(url.path)' - missing Package.swift"
        case let .versionNotFound(version):
            return "Version '\(version)' not found in repository"
        case let .gitOperationFailed(message):
            return "Git operation failed: \(message)"
        }
    }
}

// MARK: - Fetch Result

public struct FetchResult {
    /// The location where the package was fetched to
    public let packagePath: URL
    /// The resolved version (if applicable)
    public let resolvedVersion: String?
    /// The package identifier
    public let identifier: PackageIdentifier

    public init(packagePath: URL, resolvedVersion: String?, identifier: PackageIdentifier) {
        self.packagePath = packagePath
        self.resolvedVersion = resolvedVersion
        self.identifier = identifier
    }
}

// MARK: - Package Fetcher

/// Handles fetching packages from various sources
public struct PackageFetcher {
    private let configuration: InstallConfiguration
    private let fileSystem: FileManager

    public init(
        configuration: InstallConfiguration = .default,
        fileSystem: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileSystem = fileSystem
    }

    /// Fetches a package to the local packages directory
    /// - Parameters:
    ///   - identifier: The package identifier
    ///   - source: The package source
    /// - Returns: Information about the fetched package
    /// - Throws: PackageFetcherError if fetching fails
    public func fetch(
        identifier: PackageIdentifier,
        source: PackageSource
    ) async throws -> FetchResult {
        // Ensure packages directory exists
        try ensureDirectoryExists(configuration.packagesDirectory)

        // Determine destination
        let destination = configuration.packagesDirectory
            .appendingPathComponent(identifier.directoryName)

        // Check if already exists
        if fileSystem.fileExists(atPath: destination.path) {
            // For local packages, rsync to update incrementally (preserves timestamps)
            // For Git packages, fetch latest and checkout to update branches/tags
            switch source {
            case let .localPath(path):
                print("Syncing package to update with latest changes...")
                try await syncLocal(source: path, destination: destination)
                return try finalizeFetch(
                    destination: destination,
                    identifier: identifier,
                    resolvedVersion: identifier.version,
                    cleanupOnError: false // Don't cleanup existing packages on validation failure
                )
            case let .git(_, version):
                // Update existing Git repository to latest version
                print("Updating existing Git repository...")
                try await updateGitRepository(at: destination, version: version)

                // Get resolved version after update
                let resolvedVersion = try await getCurrentGitRef(at: destination)
                return try finalizeFetch(
                    destination: destination,
                    identifier: identifier,
                    resolvedVersion: resolvedVersion,
                    cleanupOnError: false // Don't cleanup existing packages on validation failure
                )
            case .name:
                // GitHub search should have been resolved to a Git URL
                return try finalizeFetch(
                    destination: destination,
                    identifier: identifier,
                    resolvedVersion: identifier.version,
                    cleanupOnError: false
                )
            }
        }

        // Fetch based on source type
        switch source {
        case let .git(url, version):
            return try await fetchGit(
                url: url,
                version: version,
                destination: destination,
                identifier: identifier
            )
        case let .localPath(path):
            return try fetchLocal(
                source: path,
                destination: destination,
                identifier: identifier
            )
        case .name:
            // GitHub search should have been resolved to a Git URL by this point
            throw PackageFetcherError.gitOperationFailed(
                "GitHub search should be resolved to Git URL before fetching"
            )
        }
    }

    // MARK: - Git Fetching

    private func fetchGit(
        url: URL,
        version: String?,
        destination: URL,
        identifier: PackageIdentifier
    ) async throws -> FetchResult {
        // Use git command directly for now
        // We'll integrate SwiftPM's RepositoryManager in a follow-up

        // Ensure parent directory exists (e.g., packages/owner/)
        try ensureDirectoryExists(destination.deletingLastPathComponent())

        // Clone the repository
        let cloneResult = try await executeGit(
            arguments: ["clone", url.absoluteString, destination.path],
            workingDirectory: configuration.packagesDirectory,
            errorMessage: "Failed to clone \(url.absoluteString)"
        )

        guard cloneResult.success else {
            throw PackageFetcherError.cloneFailed(
                url.absoluteString,
                underlying: GitError(message: cloneResult.error)
            )
        }

        // Checkout specific version if provided
        var resolvedVersion = version
        if let version = version {
            let checkoutResult = try await executeGit(
                arguments: ["checkout", version],
                workingDirectory: destination,
                errorMessage: "Failed to checkout version \(version)"
            )

            guard checkoutResult.success else {
                // Clean up failed clone
                try? fileSystem.removeItem(at: destination)
                throw PackageFetcherError.checkoutFailed(url.absoluteString, version: version)
            }
        } else {
            // Get current HEAD ref as resolved version
            resolvedVersion = try await getCurrentGitRef(at: destination)
        }

        // Validate and create result (cleanup on failure since this is a new clone)
        return try finalizeFetch(
            destination: destination,
            identifier: identifier,
            resolvedVersion: resolvedVersion,
            cleanupOnError: true // Clean up failed clones
        )
    }

    private func updateGitRepository(at repository: URL, version: String?) async throws {
        // Fetch latest changes from origin
        let fetchResult = try await executeGit(
            arguments: ["fetch", "origin"],
            workingDirectory: repository,
            errorMessage: "Failed to fetch updates"
        )

        guard fetchResult.success else {
            throw PackageFetcherError.gitOperationFailed("Failed to fetch latest changes: \(fetchResult.error)")
        }

        // Checkout the specified version (or latest if no version specified)
        if let version = version {
            let checkoutResult = try await executeGit(
                arguments: ["checkout", version],
                workingDirectory: repository,
                errorMessage: "Failed to checkout version \(version)"
            )

            guard checkoutResult.success else {
                throw PackageFetcherError.checkoutFailed(repository.path, version: version)
            }

            // If it's a branch, pull the latest changes
            let isBranchResult = try await executeGit(
                arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
                workingDirectory: repository,
                errorMessage: "Failed to check if version is a branch"
            )

            if isBranchResult.success, !isBranchResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // It's a branch, pull latest
                _ = try await executeGit(
                    arguments: ["pull", "origin", version],
                    workingDirectory: repository,
                    errorMessage: "Failed to pull latest changes"
                )
            }
        } else {
            // No version specified - pull latest from current branch
            let pullResult = try await executeGit(
                arguments: ["pull"],
                workingDirectory: repository,
                errorMessage: "Failed to pull latest changes"
            )

            guard pullResult.success else {
                throw PackageFetcherError.gitOperationFailed("Failed to pull latest changes: \(pullResult.error)")
            }
        }
    }

    private func syncLocal(source: URL, destination: URL) async throws {
        // Use rsync to sync files incrementally, preserving timestamps for incremental builds
        // This is more efficient than delete + copy when updating local packages
        let result = try await Subprocess.run(
            .path("/usr/bin/rsync"),
            arguments: [
                "-a", // Archive mode (preserve timestamps, permissions, etc.)
                "--delete", // Delete files in destination that don't exist in source
                "--exclude=.build", // Don't sync .build directory
                "--exclude=.git", // Don't sync .git directory
                source.path + "/", // Trailing slash means "contents of this directory"
                destination.path + "/",
            ],
            output: .string(limit: 16 * 1024, encoding: UTF8.self),
            error: .string(limit: 16 * 1024, encoding: UTF8.self)
        )

        guard result.terminationStatus.isSuccess else {
            throw PackageFetcherError.copyFailed(source, underlying: nil)
        }
    }

    // MARK: - Local Copying

    private func fetchLocal(
        source: URL,
        destination: URL,
        identifier: PackageIdentifier
    ) throws -> FetchResult {
        // Validate source exists and has Package.swift
        try validatePackageStructure(at: source)

        // Ensure parent directory exists (e.g., packages/owner/)
        try ensureDirectoryExists(destination.deletingLastPathComponent())

        // Create destination directory
        try fileSystem.createDirectory(at: destination, withIntermediateDirectories: false)

        // Copy contents excluding .build and .git directories
        do {
            let contents = try fileSystem.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil
            )

            for item in contents {
                let itemName = item.lastPathComponent

                // Skip .build and .git directories
                if itemName == ".build" || itemName == ".git" {
                    continue
                }

                let destinationItem = destination.appendingPathComponent(itemName)
                try fileSystem.copyItem(at: item, to: destinationItem)
            }
        } catch {
            // Clean up on failure
            try? fileSystem.removeItem(at: destination)
            throw PackageFetcherError.copyFailed(source, underlying: error)
        }

        // Validate and create result (cleanup on failure since this is a new copy)
        return try finalizeFetch(
            destination: destination,
            identifier: identifier,
            resolvedVersion: identifier.version,
            cleanupOnError: true // Clean up failed copies
        )
    }

    // MARK: - Utilities

    private func ensureDirectoryExists(_ directory: URL) throws {
        if !fileSystem.fileExists(atPath: directory.path) {
            try fileSystem.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    private func validatePackageStructure(at path: URL) throws {
        let manifestPath = path.appendingPathComponent("Package.swift")
        guard fileSystem.fileExists(atPath: manifestPath.path) else {
            throw PackageFetcherError.invalidPackageStructure(path)
        }
    }

    /// Validates package structure and creates a FetchResult
    /// - Parameters:
    ///   - destination: Package directory path
    ///   - identifier: Package identifier
    ///   - resolvedVersion: Resolved version string
    ///   - cleanupOnError: Whether to remove destination on validation failure
    /// - Returns: FetchResult if validation succeeds
    /// - Throws: PackageFetcherError if validation fails
    private func finalizeFetch(
        destination: URL,
        identifier: PackageIdentifier,
        resolvedVersion: String?,
        cleanupOnError: Bool = false
    ) throws -> FetchResult {
        do {
            try validatePackageStructure(at: destination)
        } catch {
            if cleanupOnError {
                try? fileSystem.removeItem(at: destination)
            }
            throw error
        }

        return FetchResult(
            packagePath: destination,
            resolvedVersion: resolvedVersion,
            identifier: identifier
        )
    }

    private func getCurrentGitRef(at repository: URL) async throws -> String {
        let result = try await executeGit(
            arguments: ["rev-parse", "--short", "HEAD"],
            workingDirectory: repository,
            errorMessage: "Failed to get current Git ref"
        )

        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Git Execution

    private struct GitResult {
        let success: Bool
        let output: String
        let error: String
    }

    private func executeGit(
        arguments: [String],
        workingDirectory: URL? = nil,
        errorMessage: String
    ) async throws -> GitResult {
        do {
            let result = try await Subprocess.run(
                .path("/usr/bin/git"),
                arguments: Arguments(arguments),
                workingDirectory: workingDirectory.map { FilePath($0.path()) },
                output: .string(limit: 16 * 1024, encoding: UTF8.self),
                error: .string(limit: 16 * 1024, encoding: UTF8.self)
            )

            return GitResult(
                success: result.terminationStatus.isSuccess,
                output: result.standardOutput ?? "",
                error: result.standardError ?? ""
            )
        } catch {
            throw PackageFetcherError.gitOperationFailed("\(errorMessage): \(error.localizedDescription)")
        }
    }
}
