import Foundation
@testable import Nest
import Testing

// MARK: - Test Fixture

struct PackageFetcherTestFixture {
    let fetcher: PackageFetcher
    let configuration: InstallConfiguration
    let tempDirectory: URL
    let fileManager: FileManager

    init() throws {
        fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PackageFetcherTests-\(UUID().uuidString)")

        let installDir = tempDirectory.appendingPathComponent("install")
        configuration = InstallConfiguration(installDirectory: installDir)
        fetcher = PackageFetcher(configuration: configuration, fileSystem: fileManager)

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: tempDirectory)
    }

    func createTestPackage(name: String, at location: URL? = nil) throws -> URL {
        let packageDir = location ?? tempDirectory.appendingPathComponent(name)
        try fileManager.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let packageSwift = packageDir.appendingPathComponent("Package.swift")
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "\(name)",
            products: [
                .executable(name: "\(name)", targets: ["\(name)"])
            ],
            targets: [
                .executableTarget(name: "\(name)")
            ]
        )
        """
        try content.write(to: packageSwift, atomically: true, encoding: .utf8)

        // Create a simple source file
        let sourcesDir = packageDir.appendingPathComponent("Sources/\(name)")
        try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let mainSwift = sourcesDir.appendingPathComponent("main.swift")
        try "print(\"Hello from \(name)\")".write(to: mainSwift, atomically: true, encoding: .utf8)

        return packageDir
    }
}

// MARK: - Local Package Fetching Tests

@Test("Fetch local package")
func fetchLocalPackage() async throws {
    let fixture = try PackageFetcherTestFixture()
    defer { fixture.cleanup() }

    // Create a test package
    let sourcePackage = try fixture.createTestPackage(name: "TestPackage")

    let identifier = PackageIdentifier(
        owner: "local",
        name: "TestPackage",
        url: sourcePackage,
        version: nil
    )

    let result = try await fixture.fetcher.fetch(
        identifier: identifier,
        source: .localPath(sourcePackage)
    )

    // Verify the package was copied
    #expect(fixture.fileManager.fileExists(atPath: result.packagePath.path))
    #expect(result.packagePath.lastPathComponent == "TestPackage")

    // Verify Package.swift exists
    let manifestPath = result.packagePath.appendingPathComponent("Package.swift")
    #expect(fixture.fileManager.fileExists(atPath: manifestPath.path))
}

@Test("Fetch local package with version ignored")
func fetchLocalPackageWithVersion() async throws {
    let fixture = try PackageFetcherTestFixture()
    defer { fixture.cleanup() }

    let sourcePackage = try fixture.createTestPackage(name: "VersionedPackage")

    let identifier = PackageIdentifier(
        owner: "local",
        name: "VersionedPackage",
        url: sourcePackage,
        version: "1.0.0" // Version is ignored for local packages
    )

    let result = try await fixture.fetcher.fetch(
        identifier: identifier,
        source: .localPath(sourcePackage)
    )

    #expect(fixture.fileManager.fileExists(atPath: result.packagePath.path))
    #expect(result.resolvedVersion == "1.0.0")
}

@Test("Fetch local package without Package.swift fails")
func fetchInvalidLocalPackage() async throws {
    let fixture = try PackageFetcherTestFixture()
    defer { fixture.cleanup() }

    let emptyDir = fixture.tempDirectory.appendingPathComponent("EmptyPackage")
    try fixture.fileManager.createDirectory(at: emptyDir, withIntermediateDirectories: true)

    let identifier = PackageIdentifier(
        owner: "local",
        name: "EmptyPackage",
        url: emptyDir,
        version: nil
    )

    await #expect(throws: PackageFetcherError.self) {
        _ = try await fixture.fetcher.fetch(
            identifier: identifier,
            source: .localPath(emptyDir)
        )
    }
}

@Test("Fetch already-fetched package returns existing")
func fetchAlreadyFetchedPackage() async throws {
    let fixture = try PackageFetcherTestFixture()
    defer { fixture.cleanup() }

    let sourcePackage = try fixture.createTestPackage(name: "CachedPackage")

    let identifier = PackageIdentifier(
        owner: "local",
        name: "CachedPackage",
        url: sourcePackage,
        version: nil
    )

    // Fetch once
    let result1 = try await fixture.fetcher.fetch(
        identifier: identifier,
        source: .localPath(sourcePackage)
    )

    // Fetch again - should return existing
    let result2 = try await fixture.fetcher.fetch(
        identifier: identifier,
        source: .localPath(sourcePackage)
    )

    // Compare path strings to handle URL differences
    #expect(result1.packagePath.path == result2.packagePath.path)
    #expect(fixture.fileManager.fileExists(atPath: result2.packagePath.path))
}

// MARK: - Directory Structure Tests

@Test("Packages are stored in correct directory structure")
func packagesDirectoryStructure() async throws {
    let fixture = try PackageFetcherTestFixture()
    defer { fixture.cleanup() }

    let sourcePackage = try fixture.createTestPackage(name: "StructureTest")

    let identifier = PackageIdentifier(
        owner: "local",
        name: "StructureTest",
        url: sourcePackage,
        version: "1.0.0"
    )

    let result = try await fixture.fetcher.fetch(
        identifier: identifier,
        source: .localPath(sourcePackage)
    )

    // Verify path structure: ~/.nest/packages/local/StructureTest-1.0.0/
    let expectedPath = fixture.configuration.packagesDirectory
        .appendingPathComponent("local")
        .appendingPathComponent("StructureTest-1.0.0")

    #expect(result.packagePath.path == expectedPath.path)
    #expect(fixture.fileManager.fileExists(atPath: expectedPath.path))
}

@Test("Multiple packages can coexist")
func multiplePackagesCoexist() async throws {
    let fixture = try PackageFetcherTestFixture()
    defer { fixture.cleanup() }

    // Fetch first package
    let package1 = try fixture.createTestPackage(name: "Package1")
    let id1 = PackageIdentifier(owner: "local", name: "Package1", url: package1, version: nil)
    let result1 = try await fixture.fetcher.fetch(
        identifier: id1,
        source: .localPath(package1)
    )

    // Fetch second package
    let package2 = try fixture.createTestPackage(name: "Package2")
    let id2 = PackageIdentifier(owner: "local", name: "Package2", url: package2, version: nil)
    let result2 = try await fixture.fetcher.fetch(
        identifier: id2,
        source: .localPath(package2)
    )

    // Both should exist
    #expect(fixture.fileManager.fileExists(atPath: result1.packagePath.path))
    #expect(fixture.fileManager.fileExists(atPath: result2.packagePath.path))
    #expect(result1.packagePath != result2.packagePath)
}
