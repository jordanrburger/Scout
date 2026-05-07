import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject var service: ScheduleEditService
    @EnvironmentObject var appState: AppState

    @State private var expandedSlotKey: String?
    @State private var newDraftSlot: Slot?
    @State private var staleBannerVisible = false
    @State private var stalenessDetail: String?
    @State private var errorMessage: String?
    @State private var isInitialLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if staleBannerVisible {
                staleBanner
            }
            if let err = errorMessage {
                errorBanner(err)
            }
            content
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addDraftSlot()
                } label: {
                    Label("Add slot", systemImage: "plus")
                }
            }
        }
        .task { await reload() }
    }

    // MARK: - Content branches

    @ViewBuilder
    private var content: some View {
        if isInitialLoading {
            ProgressView().padding()
        } else if service.slots.isEmpty && newDraftSlot == nil {
            emptyState
        } else {
            slotList
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No scheduled slots", systemImage: "calendar.badge.plus")
        } description: {
            Text("Add a slot to start scheduling Scout runs. Or run `scoutctl schedule init` from the terminal to seed the plugin defaults (10 standard slots).")
        } actions: {
            Button("+ Add slot") { addDraftSlot() }
        }
    }

    @ViewBuilder
    private var slotList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let new = newDraftSlot {
                    SlotRow(
                        slot: new,
                        isExpanded: true,
                        isNewDraft: true,
                        hasDirtyDraft: true,
                        onToggleExpand: { },  // new-draft can't collapse
                        onSave: { saved in await saveNewDraft(saved) },
                        onDelete: { },         // new-draft can't delete; Revert removes it
                        onFireNow: { _ in },
                        onRevertNewDraft: { newDraftSlot = nil }
                    )
                }
                ForEach(service.slots) { slot in
                    SlotRow(
                        slot: slot,
                        isExpanded: expandedSlotKey == slot.key,
                        isNewDraft: false,
                        hasDirtyDraft: false,
                        onToggleExpand: { toggleExpand(slot.key) },
                        onSave: { saved in await saveExistingSlot(saved, original: slot) },
                        onDelete: { await deleteSlot(slot) },
                        onFireNow: { key in await appState.fireNow(slotKey: key, bypassBudget: false) },
                        onRevertNewDraft: nil
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var staleBanner: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("schedule.yaml was modified externally").font(.callout.bold())
                if let detail = stalenessDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Reload now") {
                Task { await reload(); staleBannerVisible = false }
            }
            Button("Dismiss") { staleBannerVisible = false }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15))
    }

    @ViewBuilder
    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            Text(text).font(.callout)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
        }
        .padding(8)
        .background(Color.red.opacity(0.12))
    }

    // MARK: - Helpers (testable)

    static func nextNewSlotKey(existing: [String]) -> String {
        var n = 1
        while existing.contains("new-slot-\(n)") { n += 1 }
        return "new-slot-\(n)"
    }

    static func makeNewDraftSlot(key: String) -> Slot {
        Slot(
            key: key,
            type: .briefing,
            runner: "run-scout.sh",
            firesAtLocal: "09:00",
            weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri"],
            missedWindowHours: 4,
            onMiss: .fire,
            cooldownMinutes: 60,
            budgetUsd: nil,
            tz: nil,
            runtime: .local
        )
    }

    // MARK: - Actions

    private func addDraftSlot() {
        guard newDraftSlot == nil else { return }
        let existing = service.slots.map(\.key)
        let key = Self.nextNewSlotKey(existing: existing)
        newDraftSlot = Self.makeNewDraftSlot(key: key)
        expandedSlotKey = nil
    }

    private func toggleExpand(_ key: String) {
        if expandedSlotKey == key {
            expandedSlotKey = nil
        } else {
            expandedSlotKey = key
        }
    }

    private func reload() async {
        do {
            try await service.loadAll()
            isInitialLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isInitialLoading = false
        }
    }

    private func saveNewDraft(_ slot: Slot) async {
        var combined = service.slots
        combined.append(slot)
        do {
            try await service.save(allSlots: combined)
            newDraftSlot = nil
            expandedSlotKey = slot.key
        } catch let stale as StaleScheduleError {
            staleBannerVisible = true
            stalenessDetail = stale.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveExistingSlot(_ saved: Slot, original: Slot) async {
        var updated = service.slots
        if let idx = updated.firstIndex(where: { $0.key == original.key }) {
            updated[idx] = saved
        }
        do {
            try await service.save(allSlots: updated)
        } catch let stale as StaleScheduleError {
            staleBannerVisible = true
            stalenessDetail = stale.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSlot(_ slot: Slot) async {
        do {
            try await service.delete(slotKey: slot.key)
            if expandedSlotKey == slot.key { expandedSlotKey = nil }
        } catch let stale as StaleScheduleError {
            staleBannerVisible = true
            stalenessDetail = stale.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
