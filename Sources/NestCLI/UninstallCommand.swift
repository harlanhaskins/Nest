import ArgumentParser
import Foundation
import Nest

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uninstall a Swift package",
        discussion: """
        Uninstall a previously installed Swift package.

        You can specify the package by:
        - Full identifier (e.g., "apple/swift-argument-parser")
        - Package name (e.g., "swift-argument-parser")
        - Binary name (e.g., "swift-package")

        Examples:
          nest uninstall apple/swift-argument-parser
          nest uninstall swift-argument-parser
          nest uninstall swift-package
        """
    )

    @Argument(help: "Package identifier (owner/repo, repo name, or binary name)")
    var identifier: String

    @Option(help: "Installation directory (default: ~/.nest)")
    var installDir: String?

    mutating func run() async throws {
        let config = if let installDir = installDir {
            InstallConfiguration(installDirectory: URL(fileURLWithPath: installDir))
        } else {
            InstallConfiguration.default
        }

        let fileManager = FileManager.default
        let packagesDir = config.packagesDirectory

        guard fileManager.fileExists(atPath: packagesDir.path) else {
            throw UninstallError.noPackagesInstalled
        }

        // Find matching packages
        let matchingPaths = try findMatchingPackages(identifier: identifier, packagesDir: packagesDir, config: config)

        guard !matchingPaths.isEmpty else {
            throw UninstallError.packageNotFound(identifier)
        }

        // Remove symlinks first
        let builder = PackageBuilder(configuration: config)
        var allRemovedSymlinks: [String] = []

        for packagePath in matchingPaths {
            // Extract package name from path for symlink removal
            let packageName = packagePath.lastPathComponent.components(separatedBy: "-").first ?? packagePath.lastPathComponent
            let removed = try builder.removeSymlinks(for: packageName)
            allRemovedSymlinks.append(contentsOf: removed)
        }

        if !allRemovedSymlinks.isEmpty {
            print("Removing symlinks:")
            for name in allRemovedSymlinks.sorted() {
                print("  • \(name)")
            }
        }

        // Remove all matching directories
        print(allRemovedSymlinks.isEmpty ? "Removing package(s):" : "\nRemoving package(s):")
        for packagePath in matchingPaths {
            let relativePath = packagePath.path.replacingOccurrences(of: packagesDir.path + "/", with: "")
            print("  • \(relativePath)")
            try fileManager.removeItem(at: packagePath)
        }

        print("\n✓ Uninstalled: \(identifier)")
        if matchingPaths.count > 1 {
            print("  (\(matchingPaths.count) package(s) removed)")
        }
    }

    // MARK: - Helper Methods

    private func findMatchingPackages(identifier: String, packagesDir: URL, config: InstallConfiguration) throws -> [URL] {
        let fileManager = FileManager.default

        // Check if identifier contains "/" (owner/repo format)
        if identifier.contains("/") {
            let components = identifier.split(separator: "/")
            if components.count == 2 {
                let owner = String(components[0])
                let repo = String(components[1])

                // Direct lookup: packages/owner/repo
                let ownerDir = packagesDir.appendingPathComponent(owner)
                guard fileManager.fileExists(atPath: ownerDir.path) else {
                    return []
                }

                let repoPath = ownerDir.appendingPathComponent(repo)
                if fileManager.fileExists(atPath: repoPath.path) {
                    return [repoPath]
                }

                // Also check for versioned packages (packages/owner/repo-version)
                let contents = try fileManager.contentsOfDirectory(at: ownerDir, includingPropertiesForKeys: nil)
                return contents.filter { $0.lastPathComponent.hasPrefix("\(repo)-") }
            }
        }

        // Search by package name or binary name across all owners
        return try searchAllOwners(for: identifier, packagesDir: packagesDir, config: config)
    }

    private func searchAllOwners(for identifier: String, packagesDir: URL, config: InstallConfiguration) throws -> [URL] {
        let fileManager = FileManager.default

        // Get all owner directories
        let ownerDirs = try fileManager.contentsOfDirectory(
            at: packagesDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var matches: [URL] = []

        // Search each owner directory for matching packages
        for ownerDir in ownerDirs {
            let packages = try fileManager.contentsOfDirectory(at: ownerDir, includingPropertiesForKeys: nil)

            // Match by package name
            let nameMatches = packages.filter { url in
                let packageName = url.lastPathComponent
                return packageName == identifier || packageName.hasPrefix("\(identifier)-")
            }
            matches.append(contentsOf: nameMatches)
        }

        // If no matches found, try matching by binary name
        if matches.isEmpty {
            matches = try findPackageByBinaryName(identifier, ownerDirs: ownerDirs, config: config)
        }

        return matches
    }

    private func findPackageByBinaryName(_ binaryName: String, ownerDirs: [URL], config: InstallConfiguration) throws -> [URL] {
        let fileManager = FileManager.default
        let binDir = config.binDirectory

        guard fileManager.fileExists(atPath: binDir.path) else {
            return []
        }

        // Check if binary symlink exists
        let binaryPath = binDir.appendingPathComponent(binaryName)
        guard fileManager.fileExists(atPath: binaryPath.path) else {
            return []
        }

        // Resolve symlink to find the actual executable
        let resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: binaryPath.path)
        let resolvedURL = URL(fileURLWithPath: resolvedPath, relativeTo: binDir)

        // Find which package directory contains this executable
        var matches: [URL] = []
        for ownerDir in ownerDirs {
            let packages = try fileManager.contentsOfDirectory(at: ownerDir, includingPropertiesForKeys: nil)
            for packageDir in packages {
                if resolvedURL.path.contains(packageDir.path) {
                    matches.append(packageDir)
                }
            }
        }

        return matches
    }
}

// MARK: - Errors

enum UninstallError: Error, LocalizedError {
    case noPackagesInstalled
    case packageNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noPackagesInstalled:
            return "No packages are installed"
        case let .packageNotFound(name):
            return "Package '\(name)' is not installed"
        }
    }
}
