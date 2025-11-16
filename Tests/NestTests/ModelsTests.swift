import Foundation
@testable import Nest
import Testing

// MARK: - PackageSource Tests

@Test("PackageSource equality - name")
func packageSourceEquality() {
    let source1 = PackageSource.name("owner/repo")
    let source2 = PackageSource.name("owner/repo")
    let source3 = PackageSource.name("other/repo")

    #expect(source1 == source2)
    #expect(source1 != source3)
}

@Test("PackageSource equality - git")
func packageSourceGitEquality() {
    let url = URL(string: "https://github.com/owner/repo")!
    let source1 = PackageSource.git(url, version: "1.0.0")
    let source2 = PackageSource.git(url, version: "1.0.0")
    let source3 = PackageSource.git(url, version: "2.0.0")
    let source4 = PackageSource.git(url, version: nil)

    #expect(source1 == source2)
    #expect(source1 != source3)
    #expect(source1 != source4)
}

@Test("PackageSource equality - local path")
func packageSourceLocalPathEquality() {
    let url1 = URL(fileURLWithPath: "/path/to/package")
    let url2 = URL(fileURLWithPath: "/path/to/package")
    let url3 = URL(fileURLWithPath: "/different/path")

    let source1 = PackageSource.localPath(url1)
    let source2 = PackageSource.localPath(url2)
    let source3 = PackageSource.localPath(url3)

    #expect(source1 == source2)
    #expect(source1 != source3)
}

// MARK: - PackageIdentifier Tests

@Test("PackageIdentifier equality")
func packageIdentifierEquality() {
    let url = URL(string: "https://github.com/owner/repo")!
    let id1 = PackageIdentifier(owner: "owner", name: "MyPackage", url: url, version: "1.0.0")
    let id2 = PackageIdentifier(owner: "owner", name: "MyPackage", url: url, version: "1.0.0")
    let id3 = PackageIdentifier(owner: "owner", name: "OtherPackage", url: url, version: "1.0.0")

    #expect(id1 == id2)
    #expect(id1 != id3)
}

@Test("PackageIdentifier is hashable")
func packageIdentifierHashable() {
    let url = URL(string: "https://github.com/owner/repo")!
    let id1 = PackageIdentifier(owner: "owner", name: "MyPackage", url: url, version: "1.0.0")
    let id2 = PackageIdentifier(owner: "owner", name: "MyPackage", url: url, version: "1.0.0")

    var set = Set<PackageIdentifier>()
    set.insert(id1)
    set.insert(id2)

    // Should only contain one element since they're equal
    #expect(set.count == 1)
}

@Test("PackageIdentifier directory name without version")
func packageIdentifierDirectoryNameWithoutVersion() {
    let url = URL(string: "https://github.com/owner/repo")!
    let identifier = PackageIdentifier(owner: "owner", name: "MyPackage", url: url, version: nil)

    #expect(identifier.directoryName == "owner/MyPackage")
}

@Test("PackageIdentifier directory name with version")
func packageIdentifierDirectoryNameWithVersion() {
    let url = URL(string: "https://github.com/owner/repo")!
    let identifier = PackageIdentifier(owner: "owner", name: "MyPackage", url: url, version: "1.2.3")

    #expect(identifier.directoryName == "owner/MyPackage-1.2.3")
}

@Test("PackageIdentifier directory name sanitizes slashes")
func packageIdentifierDirectoryNameSanitizesSlashes() {
    let url = URL(string: "https://github.com/owner/repo")!
    let identifier = PackageIdentifier(owner: "owner", name: "repo-with/slash", url: url, version: nil)

    // Slashes in names should be replaced with hyphens
    #expect(identifier.directoryName == "owner/repo-with-slash")
}

@Test("PackageIdentifier directory name with slashes and version")
func packageIdentifierDirectoryNameWithSlashesAndVersion() {
    let url = URL(string: "https://github.com/owner/repo")!
    let identifier = PackageIdentifier(owner: "owner", name: "repo-with/slash", url: url, version: "2.0.0")

    #expect(identifier.directoryName == "owner/repo-with-slash-2.0.0")
}

// MARK: - InstallConfiguration Tests

@Test("InstallConfiguration paths")
func installConfigurationPaths() {
    let installDir = URL(fileURLWithPath: "/custom/install/path")
    let config = InstallConfiguration(installDirectory: installDir)

    #expect(config.installDirectory.path == "/custom/install/path")
    #expect(config.binDirectory.path == "/custom/install/path/bin")
    #expect(config.packagesDirectory.path == "/custom/install/path/packages")
}

@Test("Default install configuration")
func defaultInstallConfiguration() {
    let config = InstallConfiguration.default
    let homeDir = FileManager.default.homeDirectoryForCurrentUser

    #expect(
        config.installDirectory.path ==
            homeDir.appendingPathComponent(".nest").path
    )
    #expect(
        config.binDirectory.path ==
            homeDir.appendingPathComponent(".nest/bin").path
    )
    #expect(
        config.packagesDirectory.path ==
            homeDir.appendingPathComponent(".nest/packages").path
    )
}

@Test("InstallConfiguration with trailing slash")
func installConfigurationWithTrailingSlash() {
    let installDir = URL(fileURLWithPath: "/custom/path/")
    let config = InstallConfiguration(installDirectory: installDir)

    // URL should handle trailing slashes correctly
    #expect(config.binDirectory.path.contains("/bin"))
    #expect(config.packagesDirectory.path.contains("/packages"))
}

// MARK: - Integration Tests

@Test("PackageIdentifier with real GitHub URL")
func packageIdentifierWithRealGitHubURL() {
    let url = URL(string: "https://github.com/apple/swift-argument-parser")!
    let identifier = PackageIdentifier(
        owner: "apple",
        name: "swift-argument-parser",
        url: url,
        version: "1.2.3"
    )

    #expect(identifier.owner == "apple")
    #expect(identifier.name == "swift-argument-parser")
    #expect(identifier.url == url)
    #expect(identifier.version == "1.2.3")
    #expect(identifier.directoryName == "apple/swift-argument-parser-1.2.3")
}

@Test("PackageIdentifier with local URL")
func packageIdentifierWithLocalURL() {
    let url = URL(fileURLWithPath: "/Users/test/MyPackage")
    let identifier = PackageIdentifier(
        owner: "local",
        name: "MyPackage",
        url: url,
        version: nil
    )

    #expect(identifier.owner == "local")
    #expect(identifier.name == "MyPackage")
    #expect(identifier.url == url)
    #expect(identifier.version == nil)
    #expect(identifier.directoryName == "local/MyPackage")
}
