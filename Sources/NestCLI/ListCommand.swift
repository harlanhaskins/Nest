import ArgumentParser
import Foundation
import Nest

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List installed packages",
        discussion: """
        List all installed Swift packages.

        Examples:
          nest list
        """
    )

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
            print("No packages installed.")
            return
        }

        // Get all owner directories
        let ownerDirs = try fileManager.contentsOfDirectory(
            at: packagesDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        if ownerDirs.isEmpty {
            print("No packages installed.")
            return
        }

        var totalPackages = 0
        print("Installed packages:\n")

        for ownerDir in ownerDirs {
            let owner = ownerDir.lastPathComponent
            let packages = try fileManager.contentsOfDirectory(
                at: ownerDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            if !packages.isEmpty {
                print("  \(owner)/")
                for package in packages {
                    print("    • \(package.lastPathComponent)")
                    totalPackages += 1
                }
                print("")
            }
        }

        print("Total: \(totalPackages) package(s)")
    }
}
