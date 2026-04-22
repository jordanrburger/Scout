import SwiftUI

struct ScheduleDetailView: View {
    let schedule: Schedule
    @EnvironmentObject var service: ScheduleEditorService

    @State private var draft: Schedule
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isConfirmingDelete = false
    @State private var commitMessageOverride: String = ""
    @State private var commitMessageDisclosureExpanded = false

    private let knownRunners: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Scout")
        return [
            home.appendingPathComponent("run-scout.sh"),
            home.appendingPathComponent("run-dreaming.sh"),
            home.appendingPathComponent("run-research.sh"),
            home.appendingPathComponent("scripts/heartbeat.sh"),
        ]
    }()
    private let customRunnerSentinel = URL(fileURLWithPath: "/__custom__")

    init(schedule: Schedule) {
        self.schedule = schedule
        _draft = State(initialValue: schedule)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                labelField
                runnerField
                triggerEditor
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 12) {
                        workingDirectoryField
                        environmentEditor
                        logPathFields
                    }
                    .padding(.top, 8)
                }
                DisclosureGroup(
                    "Commit message",
                    isExpanded: $commitMessageDisclosureExpanded
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(defaultCommitMessage)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        TextField("Override", text: $commitMessageOverride)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 8)
                }
                actionButtons
            }
            .padding()
        }
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            ),
            actions: { Button("OK") { saveError = nil } },
            message: { Text(saveError ?? "") }
        )
        .confirmationDialog(
            "Delete \(schedule.id)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes both the live plist and the repo copy, and commits the deletion.")
        }
    }

    // MARK: - Sections

    private var labelField: some View {
        LabeledContent("Label") {
            Text(schedule.id).font(.body.monospaced())
        }
    }

    private var runnerField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Runner").font(.headline)
            let isKnown = knownRunners.contains(draft.runnerScript)
            Picker("", selection: Binding<URL>(
                get: { isKnown ? draft.runnerScript : customRunnerSentinel },
                set: { newValue in
                    if newValue == customRunnerSentinel { return }
                    draft.runnerScript = newValue
                }
            )) {
                ForEach(knownRunners, id: \.self) { url in
                    Text(url.lastPathComponent).tag(url)
                }
                Text("Custom…").tag(customRunnerSentinel)
            }
            .labelsHidden()
            TextField("Path", text: Binding(
                get: { draft.runnerScript.path },
                set: { draft.runnerScript = URL(fileURLWithPath: $0) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var triggerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger").font(.headline)
            Picker("", selection: Binding<String>(
                get: { draft.trigger.isCalendar ? "cal" : "int" },
                set: { newValue in
                    if newValue == "cal", !draft.trigger.isCalendar {
                        draft.trigger = .calendar([CalendarFire(weekday: nil, hour: 9, minute: 0)])
                    } else if newValue == "int", draft.trigger.isCalendar {
                        draft.trigger = .interval(seconds: 1800)
                    }
                }
            )) {
                Text("Calendar fires").tag("cal")
                Text("Interval").tag("int")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch draft.trigger {
            case .calendar(let fires):
                calendarEditor(fires: fires)
            case .interval(let seconds):
                intervalEditor(seconds: seconds)
            }
        }
    }

    @ViewBuilder
    private func calendarEditor(fires: [CalendarFire]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(fires) { fire in
                HStack {
                    Picker("Weekday", selection: Binding<Int>(
                        get: { fire.weekday ?? 0 },
                        set: { newValue in
                            updateFire(id: fire.id) { f in
                                f.weekday = (newValue == 0) ? nil : newValue
                            }
                        }
                    )) {
                        Text("Every day").tag(0)
                        ForEach(1...7, id: \.self) { w in
                            Text(weekdayName(w)).tag(w)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Stepper(
                        value: Binding(
                            get: { fire.hour },
                            set: { newValue in
                                updateFire(id: fire.id) { $0.hour = newValue }
                            }
                        ),
                        in: 0...23
                    ) {
                        Text("\(fire.hour):\(String(format: "%02d", fire.minute))")
                            .font(.body.monospaced())
                            .frame(width: 70, alignment: .leading)
                    }
                    Stepper(
                        value: Binding(
                            get: { fire.minute },
                            set: { newValue in
                                updateFire(id: fire.id) { $0.minute = newValue }
                            }
                        ),
                        in: 0...59
                    ) {
                        Text(":\(String(format: "%02d", fire.minute))")
                            .font(.body.monospaced())
                            .frame(width: 40, alignment: .leading)
                    }
                    Button(role: .destructive) {
                        removeFire(id: fire.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add fire") { appendFire() }
        }
    }

    private func intervalEditor(seconds: Int) -> some View {
        HStack {
            Stepper(value: Binding(
                get: { seconds },
                set: { draft.trigger = .interval(seconds: max(1, $0)) }
            ), in: 1...86_400, step: 60) {
                Text("\(seconds) sec (\(seconds / 60) min)")
            }
        }
    }

    private var workingDirectoryField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Working directory").font(.subheadline)
            TextField("Optional", text: Binding(
                get: { draft.workingDirectory?.path ?? "" },
                set: { newValue in
                    draft.workingDirectory = newValue.isEmpty
                        ? nil : URL(fileURLWithPath: newValue)
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var environmentEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Environment variables").font(.subheadline)
            let keys = draft.environment.keys.sorted()
            ForEach(keys, id: \.self) { k in
                HStack {
                    TextField("KEY", text: Binding(
                        get: { k },
                        set: { newKey in
                            let v = draft.environment[k] ?? ""
                            draft.environment.removeValue(forKey: k)
                            draft.environment[newKey] = v
                        }
                    ))
                    .frame(width: 160)
                    TextField("value", text: Binding(
                        get: { draft.environment[k] ?? "" },
                        set: { draft.environment[k] = $0 }
                    ))
                    Button(role: .destructive) {
                        draft.environment.removeValue(forKey: k)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add variable") {
                var candidate = "KEY"
                var n = 1
                while draft.environment[candidate] != nil {
                    n += 1
                    candidate = "KEY\(n)"
                }
                draft.environment[candidate] = ""
            }
        }
    }

    private var logPathFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log paths").font(.subheadline)
            TextField("StandardOutPath", text: Binding(
                get: { draft.logStdOut?.path ?? "" },
                set: { draft.logStdOut = $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            TextField("StandardErrorPath", text: Binding(
                get: { draft.logStdErr?.path ?? "" },
                set: { draft.logStdErr = $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Revert") { draft = schedule }
                .disabled(draft == schedule || isSaving)
            Spacer()
            Button("Delete", role: .destructive) {
                isConfirmingDelete = true
            }
            .disabled(isSaving)
            Button("Save") {
                Task { await performSave() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(draft == schedule || isSaving)
        }
    }

    // MARK: - Actions

    private var defaultCommitMessage: String {
        let suffix = ScheduleDiff.summarize(original: schedule, edited: draft)
        return suffix.isEmpty
            ? "schedules: update \(schedule.id)"
            : "schedules: update \(schedule.id) (\(suffix))"
    }

    private func performSave() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.save(
                draft,
                commitMessageOverride: commitMessageOverride.isEmpty ? nil : commitMessageOverride
            )
        } catch {
            saveError = String(describing: error)
        }
    }

    private func performDelete() async {
        do {
            try await service.delete(schedule, commitMessageOverride: nil)
        } catch {
            saveError = String(describing: error)
        }
    }

    // MARK: - Fire-list mutations

    private func updateFire(id: UUID, _ mutate: (inout CalendarFire) -> Void) {
        guard case .calendar(var fires) = draft.trigger,
              let idx = fires.firstIndex(where: { $0.id == id }) else { return }
        mutate(&fires[idx])
        draft.trigger = .calendar(fires)
    }

    private func removeFire(id: UUID) {
        guard case .calendar(var fires) = draft.trigger else { return }
        fires.removeAll { $0.id == id }
        draft.trigger = .calendar(fires)
    }

    private func appendFire() {
        guard case .calendar(var fires) = draft.trigger else { return }
        fires.append(CalendarFire(weekday: nil, hour: 9, minute: 0))
        draft.trigger = .calendar(fires)
    }

    private func weekdayName(_ calendarWeekday: Int) -> String {
        ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendarWeekday]
    }
}

private extension ScheduleTrigger {
    var isCalendar: Bool { if case .calendar = self { return true }; return false }
}
