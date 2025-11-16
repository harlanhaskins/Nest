import ArgumentParser
import Foundation
import Nest

@main
struct NestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nest",
        abstract: "Install and manage Swift package executables",
        subcommands: [Install.self, Uninstall.self, List.self, Search.self],
        defaultSubcommand: Install.self
    )
}

// MARK: - GitHub API Models

struct GitHubSearchResult: Codable {
    let items: [GitHubRepository]
}

struct GitHubRepository: Codable {
    let name: String
    let description: String?
    let cloneUrl: String
    let stargazersCount: Int
    let owner: GitHubOwner
}

struct GitHubOwner: Codable {
    let login: String
}

// MARK: - GitHub Search

/// Search GitHub for Swift packages
/// - Parameters:
///   - query: Search query
///   - limit: Maximum number of results to return
/// - Returns: Array of matching repositories
/// - Throws: ValidationError if the search fails
func searchGitHub(query: String, limit: Int = 4) async throws -> [GitHubRepository] {
    let searchQuery = "\(query)+language:swift"
    let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
    let searchURL = URL(string: "https://api.github.com/search/repositories?q=\(encodedQuery)&sort=stars&per_page=\(limit)")!

    var request = URLRequest(url: searchURL)
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
    request.setValue("nest", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw ValidationError("Invalid response from GitHub")
    }

    if httpResponse.statusCode != 200 {
        throw ValidationError("Failed to search GitHub (status: \(httpResponse.statusCode))")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let searchResult = try decoder.decode(GitHubSearchResult.self, from: data)

    return searchResult.items
}

// MARK: - Generic Interactive Selector

/// Presents an interactive selection menu to the user
/// - Parameters:
///   - items: Array of items to select from
///   - title: Title to display above the items
///   - format: Closure to format each item for display
/// - Returns: The selected item
/// - Throws: ValidationError if selection is cancelled or invalid
func selectInteractively<T>(
    from items: [T],
    title: String,
    format: (T) -> String
) throws -> T {
    guard !items.isEmpty else {
        throw ValidationError("No items to select from")
    }

    if items.count == 1 {
        return items[0]
    }

    print("\n\(title)\n")

    for (index, item) in items.enumerated() {
        print("  \(index + 1). \(format(item))")
    }

    print("\nSelect an option (1-\(items.count)) or press Enter to cancel: ", terminator: "")
    fflush(stdout)

    guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
        throw ValidationError("Selection cancelled")
    }

    guard let selection = Int(input), selection >= 1, selection <= items.count else {
        throw ValidationError("Invalid selection")
    }

    return items[selection - 1]
}
