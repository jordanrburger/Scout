import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("linearWorkspace") private var linearWorkspace: String = ""
    @AppStorage("authorName") private var authorName: String = "user"

    var body: some View {
        Form {
            Toggle("Launch Scout at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }
            LabeledContent(
                "Scout directory",
                value: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Scout").path
            )
            TextField("Linear workspace", text: $linearWorkspace,
                      prompt: Text("e.g. acme-co"))
                .help("Used to build Linear URLs when you click a [[PROJ-123]] wikilink or deep link in an action item. Leave blank to open linear.app without a workspace.")
            TextField("Your name (for comment authorship)", text: $authorName,
                      prompt: Text("user"))
                .help("Shown next to comments you add to action items. Default is \"user\".")
        }
        .padding()
        .frame(width: 520, height: 260)
    }
}
