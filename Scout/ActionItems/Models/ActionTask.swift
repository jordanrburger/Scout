import Foundation

struct ActionTask: Identifiable, Equatable, Hashable, Sendable {
    /// Ephemeral; regenerated on each parse. Do not persist.
    let id: UUID
    /// 1-based line number in the source file (for diagnostics).
    let lineNumber: Int
    let done: Bool
    /// Raw markdown subject (with `**bold**`, `[[wikilinks]]`, etc.).
    let subject: String
    /// Markdown-stripped subject. MUST match the Python CLIs'
    /// ``_strip_markdown_tokens`` output byte-for-byte.
    let plainSubject: String
    /// Post-dash/colon remainder. May be empty.
    let body: String
    let comments: [TaskComment]
    let deepLinks: [TaskDeepLink]
    /// Parsed from a `— 🛌 Snoozed until YYYY-MM-DD` body suffix. ``nil`` otherwise.
    let snoozedUntil: Date?
    /// Parsed from a `_(carried in from YYYY-MM-DD)_` body marker. ``nil`` otherwise.
    let carriedInFrom: Date?
}
