# Agent Guidelines for Nest

## Architecture Principles

### Always Use Codable for JSON Parsing

**✅ Correct:**
```swift
struct PackageManifest: Codable {
    let products: [Product]
}
let manifest = try JSONDecoder().decode(PackageManifest.self, from: data)
```

**❌ Incorrect:**
```swift
let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
let products = json?["products"] as? [[String: Any]]
```

### Code Organization

- **Models:** `Sources/Nest/` - Core data structures
- **CLI:** `Sources/NestCLI/` - Command-line interface using ArgumentParser
- **Building:** `Sources/Nest/PackageBuilder/` - Package building and executable discovery
- **Fetching:** `Sources/Nest/PackageFetcher/` - Git cloning and local copying
- **Tests:** `Tests/NestTests/` - Use Swift Testing framework

### Error Handling

Use typed errors with `LocalizedError` conformance:
```swift
public enum PackageBuilderError: Error, LocalizedError {
    case buildFailed(String, output: String)
    case noExecutablesFound(URL)

    public var errorDescription: String? {
        // Provide user-friendly messages
    }
}
```

### Concurrency

- Use Swift 6.0+ with strict concurrency checking
- Prefer `async/await` over completion handlers
- Mark types as `Sendable` where appropriate

### Testing

- Use Swift Testing framework (`@Test`, `#expect`)
- Test core functionality without CLI dependencies
- Use fixtures for file system operations

## Current Technical Decisions

- **Swift Version:** 6.0+, Swift 6.2.1 toolchain
- **Platform:** macOS 13.0+
- **Dependencies:**
  - ArgumentParser 1.6.0 (for CLI)
- **Installation Directory:** `~/.swift-nest/`
  - `packages/` - Downloaded/cloned packages
  - `bin/` - Symlinks to built executables
