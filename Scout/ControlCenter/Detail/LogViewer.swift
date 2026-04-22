import SwiftUI

struct LogViewer: View {
    let logPath: URL
    @State private var lines: [String] = []
    @State private var search: String = ""

    var filtered: [String] {
        search.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Search in log…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .padding(.horizontal, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
        }
        .task(id: logPath) {
            await tail()
        }
    }

    private func tail() async {
        guard let handle = try? FileHandle(forReadingFrom: logPath) else { return }
        defer { try? handle.close() }

        // Initial load
        if let data = try? handle.readToEnd() {
            let s = String(data: data, encoding: .utf8) ?? ""
            lines = s.components(separatedBy: "\n")
        }

        // Tail with DispatchSource. Cancel immediately if the parent Task is
        // cancelled (e.g., user selects a different run) so we don't overlap
        // two sources writing to the same `lines` state.
        let fd = handle.fileDescriptor
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .extend, queue: .global()
        )
        src.setEventHandler {
            if let d = try? handle.readToEnd(),
               let s = String(data: d, encoding: .utf8) {
                let more = s.components(separatedBy: "\n")
                Task { @MainActor in self.lines.append(contentsOf: more) }
            }
        }
        src.resume()

        await withTaskCancellationHandler {
            // Park until cancellation. sleep(nanoseconds: .max) is fine — the
            // handler below cancels the source the instant the parent Task
            // is cancelled, so there's no latency on switch.
            try? await Task.sleep(nanoseconds: UInt64.max)
        } onCancel: {
            src.cancel()
        }
    }
}
