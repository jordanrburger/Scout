import SwiftUI

/// Editorial sidebar: sand-colored group label, flat row, accent fill on the
/// selected item. Matches the handoff bundle's `.sb-item` language.
struct SidebarView: View {
    @Binding var selection: SidebarItem

    var body: some View {
        List(selection: $selection) {
            Section {
                sidebarRow(.controlCenter, label: "Control Center", system: "chart.bar.doc.horizontal")
                sidebarRow(.actionItems,   label: "Action Items",   system: "checklist")
                // Schedules tab hidden in Plan 5 — the launchd-plist editor model
                // it was built around no longer matches reality (only schedule-tick
                // and heartbeat plists exist; slots live in schedule.yaml). Plan 6
                // will rewrite this surface as a schedule.yaml editor. The .schedules
                // case stays in SidebarItem for state-restore compat; MainWindowView
                // routes it to a placeholder.
            } header: {
                Text("Scout")
                    .font(DS.sans(11, weight: .medium))
                    .foregroundStyle(DS.Ink.p4)
            }
            Section {
                sidebarRow(.settings, label: "Settings", system: "gearshape")
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func sidebarRow(_ item: SidebarItem, label: String, system: String) -> some View {
        Label {
            Text(label)
                .font(DS.sans(13))
        } icon: {
            Image(systemName: system)
                .font(.system(size: 13))
                .foregroundStyle(selection == item ? DS.Accent.ink : DS.Ink.p3)
        }
        .tag(item)
    }
}
