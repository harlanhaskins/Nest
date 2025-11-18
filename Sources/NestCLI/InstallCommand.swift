import ArgumentParser
import Foundation
import Nest

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install a Swift package",
        discussion: """
        Install Swift packages by name, URL, or local path.

        Examples:
          nest                                      # Install from current directory
          nest install apple/swift-argument-parser
          nest apple/swift-argument-parser          # install is default
          nest install --url https://github.com/apple/swift-argument-parser
          nest install --path ~/Projects/MyPackage
        """
    )

    @Argument(help: "Package name (format: owner/repo)")
    var packageName: String?

    @Option(help: "Git URL to clone from")
    var url: String?

    @Option(help: "Local path to install from")
    var path: String?

    @Option(help: "Installation directory (default: ~/.nest)")
    var installDir: String?

    mutating func validate() throws {
        let providedOptions = [packageName != nil, url != nil, path != nil].filter { $0 }.count

        guard providedOptions <= 1 else {
            throw ValidationError("Provide at most one of: package name, --url, or --path")
        }
    }

    mutating func run() async throws {
        let config = if let installDir = installDir {
            InstallConfiguration(installDirectory: URL(fileURLWithPath: installDir))
        } else {
            InstallConfiguration.default
        }

        // Determine the source
        let source: PackageSource
        let identifier: PackageIdentifier

        if let name = packageName {
            // Search for the package by name
            (source, identifier) = try await resolveByName(name)
        } else if let urlString = url {
            // Use URL directly without validation
            guard let gitURL = URL(string: urlString) else {
                throw ValidationError("Invalid URL: \(urlString)")
            }

            let (owner, name) = extractOwnerAndName(from: gitURL)
            identifier = PackageIdentifier(owner: owner, name: name, url: gitURL, version: nil)
            source = .git(gitURL, version: nil)
        } else if let path {
            // Use local path directly
            let localURL = URL(filePath: path)
            let name = localURL.lastPathComponent
            identifier = PackageIdentifier(owner: "local", name: name, url: localURL, version: nil)
            source = .localPath(localURL)
        } else {
            // No arguments provided - use current working directory
            let currentDir = FileManager.default.currentDirectoryPath
            let localURL = URL(filePath: currentDir)
            let name = localURL.lastPathComponent
            print("Installing from current directory: \(currentDir)")
            identifier = PackageIdentifier(owner: "local", name: name, url: localURL, version: nil)
            source = .localPath(localURL)
        }

        // Fetch the package
        print("Fetching package...")
        let fetcher = PackageFetcher(configuration: config)
        let fetchResult = try await fetcher.fetch(identifier: identifier, source: source)

        print("✓ Package fetched: \(fetchResult.identifier.name)")
        if let version = fetchResult.resolvedVersion {
            print("  Version: \(version)")
        }

        // Build the package
        print("\nBuilding package...")
        let builder = PackageBuilder(configuration: config)
        let buildResult = try await builder.build(at: fetchResult.packagePath)

        print("✓ Build complete")

        // Create symlinks
        print("\nInstalling executables...")
        let installed = try builder.createSymlinks(for: buildResult)

        print("✓ Installation complete!")
        for name in installed {
            print("  • \(name)")
        }
    }

    // MARK: - Helper Methods

    private func resolveByName(_ name: String) async throws -> (PackageSource, PackageIdentifier) {
        // Check if it's owner/repo format
        if name.contains("/") {
            let components = name.split(separator: "/")
            guard components.count == 2 else {
                throw ValidationError("Invalid package name '\(name)'. Expected format: owner/repo")
            }

            let owner = String(components[0])
            let repoName = String(components[1])
            let gitURL = URL(string: "https://github.com/\(name)")!
            let identifier = PackageIdentifier(owner: owner, name: repoName, url: gitURL, version: nil)

            return (.git(gitURL, version: nil), identifier)
        }

        // Search GitHub for single name
        return try await searchAndSelectPackage(query: name)
    }

    private func searchAndSelectPackage(query: String) async throws -> (PackageSource, PackageIdentifier) {
        print("Searching GitHub for Swift packages matching '\(query)'...")

        let results = try await searchGitHub(query: query, limit: 4)

        guard !results.isEmpty else {
            throw ValidationError("No Swift packages found matching '\(query)'")
        }

        // If only one result, use it directly
        if results.count == 1 {
            let repo = results[0]
            print("Found: \(repo.owner.login)/\(repo.name)")
            return try createIdentifier(from: repo)
        }

        // Multiple results - show interactive selector
        let selectedRepo = try selectInteractively(
            from: results,
            title: "Found \(results.count) Swift packages:"
        ) { repo in
            let description = repo.description ?? "No description"
            let stars = repo.stargazersCount
            return "\(repo.owner.login)/\(repo.name) \(stars)\n     \(description)"
        }

        print("\nSelected: \(selectedRepo.owner.login)/\(selectedRepo.name)\n")

        return try createIdentifier(from: selectedRepo)
    }

    private func createIdentifier(from repo: GitHubRepository) throws -> (PackageSource, PackageIdentifier) {
        guard let gitURL = URL(string: repo.cloneUrl) else {
            throw ValidationError("Invalid repository URL: \(repo.cloneUrl)")
        }

        let identifier = PackageIdentifier(
            owner: repo.owner.login,
            name: repo.name,
            url: gitURL,
            version: nil
        )

        return (.git(gitURL, version: nil), identifier)
    }

    private func extractOwnerAndName(from url: URL) -> (owner: String, name: String) {
        // Extract owner and repo from URL path components
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if pathComponents.count >= 2 {
            let owner = pathComponents[pathComponents.count - 2]
            var name = pathComponents[pathComponents.count - 1]

            // Remove .git suffix if present
            if name.hasSuffix(".git") {
                name = String(name.dropLast(4))
            }

            return (owner: owner, name: name)
        }

        // Fallback: use last path component as both owner and name
        var name = url.lastPathComponent
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }

        return (owner: name.isEmpty ? "local" : name, name: name.isEmpty ? "package" : name)
    }
}
