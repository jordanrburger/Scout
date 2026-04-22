import Foundation

struct DetectedError: Equatable, Hashable, Sendable {
    let line: Int
    let pattern: String
    let snippet: String
}
