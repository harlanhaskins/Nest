import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

// MARK: - Builder Errors

public enum PackageBuilderError: Error, LocalizedError {
    case buildFailed(String, output: String)
    case noExecutablesFound(URL)
    case symlinkFailed(String, underlying: Error?)

    public var errorDescription: String? {
        switch self {
        case let .buildFailed(path, output):
            return "Failed to build package at '\(path)':\n\(output)"
        case let .noExecutablesFound(path):
            return "No executable products found in package at '\(path)'"
        case let .symlinkFailed(name, error):
            if let error = error {
                return "Failed to create symlink for '\(name)': \(error.localizedDescription)"
            }
            return "Failed to create symlink for '\(name)'"
        }
    }
}

// MARK: - Build Result

public struct BuildResult {
    /// The executables that were built
    public let executables: [Executable]
    /// The package path
    public let packagePath: URL

    public init(executables: [Executable], packagePath: URL) {
        self.executables = executables
        self.packagePath = packagePath
    }
}

public struct Executable {
    /// Name of the executable
    public let name: String
    /// Path to the executable binary
    public let path: URL

    public init(name: String, path: URL) {
        self.name = name
        self.path = path
    }
}

// MARK: - Package Builder

public struct PackageBuilder {
    private let configuration: InstallConfiguration
    private let fileSystem: FileManager

    public init(
        configuration: InstallConfiguration = .default,
        fileSystem: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileSystem = fileSystem
    }

    /// Builds a package in release configuration and discovers executables
    public func build(at packagePath: URL) async throws -> BuildResult {
        // First, discover executable products from the manifest
        let executableNames = try await loadExecutableProducts(at: packagePath)

        guard !executableNames.isEmpty else {
            throw PackageBuilderError.noExecutablesFound(packagePath)
        }

        // Build only the executable products (avoids building tests and libraries)
        try await buildExecutables(executableNames, at: packagePath)

        // Map executable names to their built binaries
        let executables = try discoverBuiltExecutables(executableNames, at: packagePath)

        return BuildResult(executables: executables, packagePath: packagePath)
    }

    /// Creates symlinks for executables in the bin directory
    public func createSymlinks(for buildResult: BuildResult) throws -> [String] {
        let binDirectory = configuration.binDirectory

        // Ensure bin directory exists
        if !fileSystem.fileExists(atPath: binDirectory.path) {
            try fileSystem.createDirectory(
                at: binDirectory,
                withIntermediateDirectories: true
            )
        }

        var installedExecutables: [String] = []

        for executable in buildResult.executables {
            let symlinkPath = binDirectory.appendingPathComponent(executable.name)

            // Remove existing symlink if present
            if fileSystem.fileExists(atPath: symlinkPath.path) {
                try? fileSystem.removeItem(at: symlinkPath)
            }

            // Create symlink
            do {
                try fileSystem.createSymbolicLink(
                    at: symlinkPath,
                    withDestinationURL: executable.path
                )
                installedExecutables.append(executable.name)
            } catch {
                throw PackageBuilderError.symlinkFailed(executable.name, underlying: error)
            }
        }

        return installedExecutables
    }

    /// Removes symlinks for a package's executables
    public func removeSymlinks(for packageName: String) throws -> [String] {
        let binDirectory = configuration.binDirectory

        guard fileSystem.fileExists(atPath: binDirectory.path) else {
            return []
        }

        let contents = try fileSystem.contentsOfDirectory(
            at: binDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        )

        var removedExecutables: [String] = []

        for item in contents {
            // Check if it's a symlink
            guard let resourceValues = try? item.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  resourceValues.isSymbolicLink == true
            else {
                continue
            }

            // Check if the symlink points to this package
            if let destination = try? fileSystem.destinationOfSymbolicLink(atPath: item.path),
               destination.contains("/\(packageName)/") || destination.contains("/\(packageName)-")
            {
                try fileSystem.removeItem(at: item)
                removedExecutables.append(item.lastPathComponent)
            }
        }

        return removedExecutables
    }

    // MARK: - Private Methods

    private func buildExecutables(_ productNames: [String], at packagePath: URL) async throws {
        // Build each executable product explicitly (avoids building tests and libraries)
        // Inherit stdout/stderr from parent process so user can see build progress
        for productName in productNames {
            do {
                let result = try await Subprocess.run(
                    .path("/usr/bin/swift"),
                    arguments: ["build", "-c", "release", "--product", productName],
                    workingDirectory: FilePath(packagePath.path()),
                    output: .standardOutput,
                    error: .standardError
                )

                guard result.terminationStatus.isSuccess else {
                    throw PackageBuilderError.buildFailed(
                        packagePath.path,
                        output: "Build failed for product '\(productName)' with exit code \(result.terminationStatus)"
                    )
                }
            } catch let error as PackageBuilderError {
                throw error
            } catch {
                throw PackageBuilderError.buildFailed(
                    packagePath.path,
                    output: "Process execution failed for product '\(productName)': \(error.localizedDescription)"
                )
            }
        }
    }

    private func discoverBuiltExecutables(_ executableNames: [String], at packagePath: URL) throws -> [Executable] {
        // Map executable names to their built binaries in .build/release
        let releasePath = packagePath.appendingPathComponent(".build/release")
        var executables: [Executable] = []

        for name in executableNames {
            let executablePath = releasePath.appendingPathComponent(name)
            if fileSystem.fileExists(atPath: executablePath.path) {
                executables.append(Executable(name: name, path: executablePath))
            }
        }

        return executables
    }

    private func loadExecutableProducts(at packagePath: URL) async throws -> [String] {
        // Use `swift package dump-package` to get package manifest as JSON
        // NOTE: When integrating into SwiftPM, this should use ManifestLoader directly
        let result = try await Subprocess.run(
            .path("/usr/bin/swift"),
            arguments: ["package", "dump-package"],
            workingDirectory: .init(packagePath.path()),
            output: .string(limit: 1024 * 1024, encoding: UTF8.self)
        )

        guard result.terminationStatus.isSuccess else {
            return []
        }

        let outputData = Data((result.standardOutput ?? "").utf8)

        // Parse JSON using Codable
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(PackageManifest.self, from: outputData)

        // Extract executable product names
        return manifest.products
            .filter { $0.type == .executable }
            .map { $0.name }
    }
}
