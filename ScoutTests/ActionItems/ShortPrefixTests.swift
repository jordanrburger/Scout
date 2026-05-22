import Testing
import Foundation
@testable import Scout

@Suite("ActionItemsParser.extractShortPrefix — `[#XXXX]` marker")
struct ExtractShortPrefixTests {
    @Test func extractsValidCrockfordPrefix() {
        let (prefix, rest) = ActionItemsParser.extractShortPrefix("[#A3F7] **subject** body")
        #expect(prefix == "A3F7")
        #expect(rest == "**subject** body")
    }

    @Test func returnsNilWhenNoPrefix() {
        let (prefix, rest) = ActionItemsParser.extractShortPrefix("**subject** body")
        #expect(prefix == nil)
        #expect(rest == "**subject** body")
    }

    @Test func rejectsForbiddenCrockfordChars() {
        // Crockford excludes I, L, O, U to avoid visual ambiguity.
        for bad in ["[#ILOU] subj", "[#ABCI] subj", "[#abcd] subj", "[#A3F] subj", "[#A3F77] subj"] {
            let (prefix, _) = ActionItemsParser.extractShortPrefix(bad)
            #expect(prefix == nil, "expected nil for \(bad); got \(prefix ?? "nil")")
        }
    }

    @Test func tolerantOfNoSpaceAfterBracket() {
        // `[#ABCD]**bold**` (no separating space) should still parse.
        let (prefix, rest) = ActionItemsParser.extractShortPrefix("[#ABCD]**bold**")
        #expect(prefix == "ABCD")
        #expect(rest == "**bold**")
    }

    @Test func consumesExtraWhitespaceAfterBracket() {
        let (prefix, rest) = ActionItemsParser.extractShortPrefix("[#ABCD]   **bold**")
        #expect(prefix == "ABCD")
        #expect(rest == "**bold**")
    }

    @Test func ignoresPrefixNotAtStart() {
        // The marker only counts at the very start of the body.
        let (prefix, rest) = ActionItemsParser.extractShortPrefix("**Reference [#ABCD]** body")
        #expect(prefix == nil)
        #expect(rest == "**Reference [#ABCD]** body")
    }
}

@Suite("ActionItems end-to-end parse with [#XXXX] prefix")
struct ActionItemsParseWithPrefixTests {
    @Test func parsesPrefixIntoTaskField() throws {
        let md = """
        # Action Items — 2026-05-22

        ## 🔴 Urgent

        - [ ] [#A3F7] **Reply to Procházka thread** _(carries from 5/19)_
        - [ ] **Legacy task without prefix** — should still parse with shortPrefix=nil
        """
        let doc = try ActionItemsParser.parse(
            text: md,
            sourceURL: URL(fileURLWithPath: "/tmp/action-items-2026-05-22.md"),
            sourceBytes: md.utf8.count
        )
        let urgent = try #require(doc.sections.first { $0.kind == .urgent })
        try #require(urgent.tasks.count == 2)

        let prefixed = urgent.tasks[0]
        #expect(prefixed.shortPrefix == "A3F7")
        // Subject reflects the post-prefix body (no `[#A3F7]` pollution).
        #expect(prefixed.subject.contains("Reply to Procházka thread"))
        #expect(!prefixed.subject.contains("[#A3F7]"))

        let legacy = urgent.tasks[1]
        #expect(legacy.shortPrefix == nil)
        #expect(legacy.subject.contains("Legacy task without prefix"))
    }
}
