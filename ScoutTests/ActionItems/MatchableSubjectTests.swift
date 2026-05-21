import Testing
import Foundation
@testable import Scout

@Suite("ActionTask.matchableSubject — scoutctl --subject key derivation")
struct MatchableSubjectTests {
    @Test func extractsBoldPortionWhenPresent() {
        // The case from issue #10 / screenshot: bold subject followed by
        // italic parenthetical. Sending the full plainSubject runs into the
        // italic body and scoutctl fails to substring-match it. Bold-only
        // matches reliably.
        let task = make(
            subject: "**🔥 🆕 Update kai-pricing-calculator-app with per-client conversion levers + margin maximizer** _(net-new from Kai's pricing meeting 6-7 AM ET; Jordan already iterating during meeting)_",
            plainSubject: "🔥 🆕 Update kai-pricing-calculator-app with per-client conversion levers + margin maximizer _(net-new from Kai's pricing meeting 6-7 AM ET; Jordan already iterating during meeting)_"
        )
        #expect(task.matchableSubject == "🔥 🆕 Update kai-pricing-calculator-app with per-client conversion levers + margin maximizer")
    }

    @Test func preservesInnerMarkdownInBoldPortion() {
        // scoutctl matches against the *raw* source line — `[[MKT-301]]` is
        // present verbatim in the file, so the substring we send must keep
        // the brackets too. v0.5.4 fix: do NOT strip inner markdown.
        let task = make(
            subject: "**Reply to MJ on [[MKT-301]] with consolidated GA-scope answer** _(carries from 5/15…)_",
            plainSubject: "Reply to MJ on MKT-301 with consolidated GA-scope answer _(carries from 5/15…)_"
        )
        #expect(task.matchableSubject == "Reply to MJ on [[MKT-301]] with consolidated GA-scope answer")
    }

    @Test func preservesMarkdownLinkInBoldPortion() {
        // The screenshot case from issue #10 / v0.5.3 follow-up: bold subject
        // contains `[PR #N (text)](url)`. v0.5.3 stripped the link → sent
        // "Close PR #5526 (AI-3079 sandboxId metadata) with note" which
        // doesn't appear verbatim in the raw line (the raw line has the
        // brackets + URL). v0.5.4 keeps it raw so scoutctl can substring-
        // match it directly.
        let task = make(
            subject: "**🔥 🆕 Close [PR #5526 (AI-3079 sandboxId metadata)](https://github.com/keboola/ui/pull/5526) with re-implement-on-OTel note** _(promoted 7:04 AM ET 5/20…)_",
            plainSubject: "🔥 🆕 Close PR #5526 (AI-3079 sandboxId metadata) with re-implement-on-OTel note _(promoted 7:04 AM ET 5/20…)_"
        )
        #expect(task.matchableSubject == "🔥 🆕 Close [PR #5526 (AI-3079 sandboxId metadata)](https://github.com/keboola/ui/pull/5526) with re-implement-on-OTel note")
    }

    @Test func trimsAtItalicParenWhenNoBold() {
        // Older/unstyled tasks: no bold marker, but still have an italic
        // body. Trim at the body separator so the match key is just the head.
        let task = make(
            subject: "Send the BAA forms _(carries from 5/16)_",
            plainSubject: "Send the BAA forms _(carries from 5/16)_"
        )
        #expect(task.matchableSubject == "Send the BAA forms")
    }

    @Test func trimsAtEmDashWhenNoBold() {
        let task = make(
            subject: "Merge PR #74 — sl-builder v2",
            plainSubject: "Merge PR #74 — sl-builder v2"
        )
        #expect(task.matchableSubject == "Merge PR #74")
    }

    @Test func passesThroughWhenNoMarkupNoSeparator() {
        let task = make(
            subject: "Drink water",
            plainSubject: "Drink water"
        )
        #expect(task.matchableSubject == "Drink water")
    }

    @Test func boldPortionWinsOverBodySeparator() {
        // Both a bold marker AND an em-dash inside it: bold extraction
        // takes the whole bold portion (including the em-dash), then
        // body separator trimming doesn't apply because we returned early.
        let task = make(
            subject: "**Andrea — Soustruh koncert** _(today 7:30 PM)_",
            plainSubject: "Andrea — Soustruh koncert _(today 7:30 PM)_"
        )
        #expect(task.matchableSubject == "Andrea — Soustruh koncert")
    }

    // MARK: - Helper

    private func make(subject: String, plainSubject: String) -> ActionTask {
        ActionTask(
            id: UUID(),
            lineNumber: 1,
            done: false,
            subject: subject,
            plainSubject: plainSubject,
            body: "",
            comments: [],
            deepLinks: [],
            snoozedUntil: nil,
            carriedInFrom: nil
        )
    }
}
