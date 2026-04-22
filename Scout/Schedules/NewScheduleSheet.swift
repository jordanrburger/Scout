import SwiftUI

struct NewScheduleSheet: View {
    @EnvironmentObject var service: ScheduleEditorService
    @Environment(\.dismiss) var dismiss

    @State private var idField: String = "com.scout."
    @State private var runner: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Scout/run-scout.sh")
    @State private var isInterval: Bool = false
    @State private var intervalSeconds: Int = 1800
    @State private var fires: [CalendarFire] = [
        CalendarFire(weekday: nil, hour: 9, minute: 0)
    ]
    @State private var error: String?
    @State private var isSaving = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Schedule").font(.title3)

            LabeledContent("Label") {
                TextField("com.scout.something", text: $idField)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Runner") {
                Picker("", selection: $runner) {
                    ForEach(knownRunners, id: \.self) { url in
                        Text(url.lastPathComponent).tag(url)
                    }
                }
                .labelsHidden()
            }

            Picker("Trigger", selection: $isInterval) {
                Text("Calendar fires").tag(false)
                Text("Interval").tag(true)
            }
            .pickerStyle(.segmented)

            if isInterval {
                Stepper(value: $intervalSeconds, in: 1...86_400, step: 60) {
                    Text("\(intervalSeconds) sec (\(intervalSeconds / 60) min)")
                }
            } else {
                ForEach(Array(fires.enumerated()), id: \.element.id) { idx, fire in
                    HStack {
                        Picker("Weekday", selection: Binding<Int>(
                            get: { fires[idx].weekday ?? 0 },
                            set: { newValue in
                                fires[idx].weekday = newValue == 0 ? nil : newValue
                            }
                        )) {
                            Text("Every day").tag(0)
                            ForEach(1...7, id: \.self) { w in
                                Text(weekdayName(w)).tag(w)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Stepper(value: Binding(
                            get: { fires[idx].hour },
                            set: { fires[idx].hour = $0 }
                        ), in: 0...23) {
                            Text("\(fires[idx].hour):\(String(format: "%02d", fires[idx].minute))")
                                .font(.body.monospaced())
                                .frame(width: 70, alignment: .leading)
                        }
                        Stepper(value: Binding(
                            get: { fires[idx].minute },
                            set: { fires[idx].minute = $0 }
                        ), in: 0...59) {
                            Text(":\(String(format: "%02d", fires[idx].minute))")
                                .font(.body.monospaced())
                                .frame(width: 40, alignment: .leading)
                        }
                        Button(role: .destructive) {
                            fires.remove(at: idx)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(fires.count <= 1)
                    }
                }
                Button("Add fire") {
                    fires.append(CalendarFire(weekday: nil, hour: 9, minute: 0))
                }
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        let s = Schedule(
            id: idField,
            label: idField,
            runnerScript: runner,
            trigger: isInterval
                ? .interval(seconds: intervalSeconds)
                : .calendar(fires)
        )
        do {
            try await service.create(s, commitMessageOverride: nil)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func weekdayName(_ calendarWeekday: Int) -> String {
        ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendarWeekday]
    }
}
