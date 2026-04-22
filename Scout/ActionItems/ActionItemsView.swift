import Combine
import SwiftUI

struct ActionItemsView: View {
    @EnvironmentObject var docService: ActionItemsDocumentService
    @EnvironmentObject var writerBox: ActionItemsWriterBox
    @EnvironmentObject var envCheck: ActionItemsEnvironmentState
    let scoutDirectory: URL
    let actionItemsDirectory: URL

    @State private var displayedDate: Date = Self.todayET()
    @State private var filter = ActionItemsFilter(kinds: [], status: .all, searchText: "")
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !envCheck.result.ok {
                environmentBanner
            }
            FilterChipsView(filter: $filter)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(DS.Paper.base.opacity(0.94))
                .overlay(alignment: .bottom) { EditorialRule() }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Paper.base)
        .searchable(text: $filter.searchText, placement: .toolbar, prompt: "Search tasks, tickets, people…")
        .searchFocused($searchFocused)
        .background {
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                DatePickerToolbarItem(date: $displayedDate, todayET: Self.todayET())
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([docServiceExpectedURL()])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
            }
        }
        .overlay(alignment: .top) {
            if let t = toast {
                toastView(t)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { load() }
        .onChange(of: displayedDate) { _, _ in load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch docService.state {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                case .missing(_, let url):
                    missingState(url: url)
                case .failed(let err):
                    Text("Couldn't load file: \(err.localizedDescription)")
                        .foregroundStyle(DS.Status.err)
                        .padding()
                case .loaded(let doc):
                    loadedContent(doc)
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.top, 28)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.visible)
    }

    /// Editorial reading page: dateline → preamble → filtered sections.
    @ViewBuilder
    private func loadedContent(_ doc: ActionItemsDocument) -> some View {
        dateline
        if !doc.preamble.isEmpty {
            preamble(doc.preamble)
        }
        ForEach(filteredSections(doc)) { section in
            SectionView(
                section: filtered(section),
                displayedDate: displayedDate,
                scoutDirectory: scoutDirectory,
                onOp: handleOp
            )
        }
    }

    // MARK: - Dateline (big serif header + meta on the right)

    private var dateline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(longDate(displayedDate))
                .font(DS.serif(28, weight: .medium))
                .foregroundStyle(DS.Ink.p1)
            Text(weekLabel(displayedDate))
                .font(DS.sans(14))
                .foregroundStyle(DS.Ink.p3)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("repo ~/Scout")
                    .font(DS.mono(12))
                    .foregroundStyle(DS.Ink.p4)
                Text(displayedDate, style: .date)
                    .font(DS.mono(12))
                    .foregroundStyle(DS.Ink.p4)
            }
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { EditorialRule() }
        .padding(.bottom, 22)
    }

    /// Preamble paragraph — the briefing's opening voice. Serif, max 72ch,
    /// muted a half-step from headline ink.
    private func preamble(_ parts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                InlineMarkdownText(p)
                    .font(DS.serif(15.5))
                    .foregroundStyle(DS.Ink.p2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .padding(.bottom, 20)
    }

    private var environmentBanner: some View {
        let missing = envCheck.result.missingScripts.joined(separator: ", ")
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Action Items writes disabled — \(envCheck.result.python3Path == nil ? "python3 not found" : "missing: \(missing)")")
        }
        .font(DS.sans(11))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Status.err.opacity(0.85))
    }

    private func missingState(url: URL) -> some View {
        let isFuture = displayedDate > Self.todayET()
        return VStack(spacing: 14) {
            Image(systemName: isFuture ? "calendar" : "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(DS.Ink.p3)
            Text(isFuture
                 ? "No action items yet for \(shortDate(displayedDate)) — snoozed tasks will land here, and the morning briefing will fill it in on the day."
                 : "No action items for \(shortDate(displayedDate)) — morning briefing runs at 08:03.")
                .font(DS.serif(14))
                .foregroundStyle(DS.Ink.p2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                if let prev = Calendar(identifier: .iso8601).date(byAdding: .day, value: -1, to: displayedDate) {
                    Button("Previous day") { displayedDate = prev }
                }
                if !Calendar.current.isDate(displayedDate, inSameDayAs: Self.todayET()) {
                    Button("Today") { displayedDate = Self.todayET() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(DS.sans(12))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            .shadow(radius: 4)
    }

    // MARK: - Date formatting

    private func longDate(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        fmt.timeZone = TimeZone(identifier: "America/New_York")
        return fmt.string(from: d)
    }

    private func weekLabel(_ d: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        let week = cal.component(.weekOfYear, from: d)
        let month = cal.component(.month, from: d)
        let quarter = ((month - 1) / 3) + 1
        return "Week \(week) · Q\(quarter)"
    }

    private func shortDate(_ d: Date) -> String {
        let fmt = DateFormatter(); fmt.dateStyle = .medium
        fmt.timeZone = TimeZone(identifier: "America/New_York")
        return fmt.string(from: d)
    }

    // MARK: - Actions

    private func handleOp(_ op: WriteOp) async throws {
        do {
            _ = try await writerBox.writer.submit(op, displayedDate: displayedDate)
            await MainActor.run { docService.reparseCurrent() }
        } catch let err as ActionItemsWriterError {
            if case .cliNonZeroExit(_, _, let kind) = err, kind == .environment {
                await MainActor.run { setToast("Environment problem — check python3 install.") }
            }
            throw err
        }
    }

    private func setToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { if toast == text { toast = nil } }
        }
    }

    private func load() {
        Task { try? await docService.load(date: displayedDate) }
    }

    private func docServiceExpectedURL() -> URL {
        docService.url(for: displayedDate)
    }

    private func filteredSections(_ doc: ActionItemsDocument) -> [ActionSection] {
        doc.sections.filter { s in
            filter.kinds.isEmpty || filter.kinds.contains(s.kind)
        }
    }

    private func filtered(_ section: ActionSection) -> ActionSection {
        let needle = filter.searchText.lowercased()
        let tasks = section.tasks.filter { t in
            let statusOK: Bool = {
                switch filter.status {
                case .all:     return true
                case .open:    return !t.done && t.snoozedUntil == nil
                case .done:    return t.done && t.snoozedUntil == nil
                case .snoozed: return t.snoozedUntil != nil
                }
            }()
            guard statusOK else { return false }
            guard !needle.isEmpty else { return true }
            return t.plainSubject.lowercased().contains(needle)
                || t.body.lowercased().contains(needle)
                || t.comments.contains(where: { $0.text.lowercased().contains(needle) })
        }
        return ActionSection(
            id: section.id,
            emoji: section.emoji,
            title: section.title,
            kind: section.kind,
            tasks: tasks,
            bullets: section.bullets,
            tables: section.tables,
            subheads: section.subheads
        )
    }

    private static func todayET() -> Date {
        let cal = Calendar(identifier: .iso8601)
        var comps = cal.dateComponents(in: TimeZone(identifier: "America/New_York")!, from: Date())
        comps.hour = 0; comps.minute = 0; comps.second = 0; comps.nanosecond = 0
        return cal.date(from: comps) ?? Date()
    }
}

/// A boxed writer — actors can't be directly stored in ``@EnvironmentObject``,
/// but a class holding the actor can.
final class ActionItemsWriterBox: ObservableObject {
    let writer: ActionItemsWriter
    init(writer: ActionItemsWriter) { self.writer = writer }
}

/// Publishes the environment check result so the view's banner can react.
@MainActor
final class ActionItemsEnvironmentState: ObservableObject {
    @Published var result: ActionItemsEnvironmentResult = .init(ok: true, python3Path: nil, missingScripts: [])
}
