import Foundation

// MARK: - Package Manifest Models

/// Represents the structure of `swift package dump-package` JSON output
struct PackageManifest: Decodable {
    let name: String
    let products: [Product]

    struct Product: Decodable {
        let name: String
        let type: ProductType
        let targets: [String]

        enum ProductType: Decodable {
            // We only care about checking if these keys exist
            private enum CodingKeys: String, CodingKey {
                case executable
                case library
            }

            case executable
            case library

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if container.contains(.executable) {
                    self = .executable
                } else {
                    self = .library
                }
            }
        }
    }
}
