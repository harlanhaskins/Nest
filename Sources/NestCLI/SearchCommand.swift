import ArgumentParser
import Foundation

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search for Swift packages on GitHub",
        discussion: """
        Search GitHub for Swift packages by name or description.

        This command displays all search results with detailed information
        to help you find the right package before installing.

        Examples:
          nest search argument-parser
          nest search networking
        """
    )

    @Argument(help: "Search query (package name, keyword, etc.)")
    var query: String

    @Option(help: "Maximum number of results to show (default: 4)")
    var limit: Int = 4

    mutating func run() async throws {
        print("Searching GitHub for Swift packages matching '\(query)'...\n")

        let results = try await searchGitHub(query: query, limit: limit)

        guard !results.isEmpty else {
            print("No Swift packages found matching '\(query)'")
            print("\nTry:")
            print("  • Using different keywords")
            print("  • Searching with owner/repo format: nest install owner/repo")
            print("  • Using a Git URL: nest install --url https://github.com/owner/repo")
            return
        }

        print("Found \(results.count) package(s):\n")

        for (index, repo) in results.enumerated() {
            print("[\(index + 1)] \(repo.owner.login)/\(repo.name) (⭑ \(repo.stargazersCount))")
            if let description = repo.description, !description.isEmpty {
                print("    \(description)")
            }
            print("")
        }

        print("To install a package, use:")
        print("  nest install owner/repo")
    }
}
