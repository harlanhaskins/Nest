import Foundation

// MARK: - Package Source

/// Represents the different ways a package can be specified
public enum PackageSource: Equatable {
    /// Package name to search on GitHub (e.g., "abc/MyPackage")
    case name(String)
    /// Local file system path (including current directory)
    case localPath(URL)
    /// Git repository URL
    case git(URL, version: String?)
}

// MARK: - Package Identifier

/// Uniquely identifies a package for installation
public struct PackageIdentifier: Equatable, Hashable {
    /// The owner/organization name (e.g., "apple", "swiftlang")
    public let owner: String
    /// The name of the package (e.g., "MyPackage")
    public let name: String
    /// The source URL (Git URL or local path)
    public let url: URL
    /// Optional version specifier (tag, branch, or commit)
    public let version: String?

    public init(owner: String, name: String, url: URL, version: String? = nil) {
        self.owner = owner
        self.name = name
        self.url = url
        self.version = version
    }

    /// Creates a hierarchical directory path for this package (e.g., "apple/swift-argument-parser")
    public var directoryName: String {
        let sanitizedOwner = owner.replacingOccurrences(of: "/", with: "-")
        let sanitizedName = name.replacingOccurrences(of: "/", with: "-")
        let basePath = "\(sanitizedOwner)/\(sanitizedName)"

        if let version = version {
            return "\(basePath)-\(version)"
        }
        return basePath
    }
}

// MARK: - Installation Configuration

/// Configuration for package installation paths
public struct InstallConfiguration {
    /// The root directory where packages are installed
    public let installDirectory: URL

    /// Directory containing symlinks to installed binaries
    public var binDirectory: URL {
        installDirectory.appendingPathComponent("bin")
    }

    /// Directory containing package source checkouts
    public var packagesDirectory: URL {
        installDirectory.appendingPathComponent("packages")
    }

    public init(installDirectory: URL) {
        self.installDirectory = installDirectory
    }

    /// Default installation configuration in user's home directory
    public static var `default`: InstallConfiguration {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let installDir = homeDirectory.appendingPathComponent(".nest")
        return InstallConfiguration(installDirectory: installDir)
    }
}
