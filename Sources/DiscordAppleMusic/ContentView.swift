import PresenceCore
import PresenceKit
import SwiftUI

struct ContentView: View {
    @Bindable var controller: AgentController

    static let donateURL = URL(string: "https://buymeacoffee.com/jualopezmo")!

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { controller.isOn }, set: { controller.setOn($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Discord").font(.headline)
                        Text("Runs in the background and starts at login.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                StatusRow(controller: controller)
            }

            Section("Customize") {
                Toggle("Cover art", isOn: $controller.settings.showCoverArt)
                Toggle("Clickable song, artist and album", isOn: $controller.settings.clickableLinks)
                Toggle("\u{201C}Listen on Apple Music\u{201D} button", isOn: $controller.settings.showButton)
                Picker("Member list shows", selection: $controller.settings.statusDisplay) {
                    Text("Song").tag(Settings.StatusDisplay.song)
                    Text("Artist").tag(Settings.StatusDisplay.artist)
                    Text("Apple Music").tag(Settings.StatusDisplay.appName)
                }
            }

            Section {
                TextField("Discord application ID", text: Binding(
                    get: { controller.settings.clientID ?? "" },
                    set: { controller.settings.clientID = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                ), prompt: Text("Default"))
            } header: {
                Text("Advanced")
            } footer: {
                Text("Use your own Discord application to change the name or icon shown in Discord.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Enjoying it?")
                    Spacer()
                    Link(destination: Self.donateURL) {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { controller.refresh() }
    }
}

private struct StatusRow: View {
    let controller: AgentController

    var body: some View {
        switch (controller.serviceStatus, controller.agentStatus?.state) {
        case (.requiresApproval, _):
            row("exclamationmark.triangle.fill", .orange, "Allow it in Login Items to start.") {
                Button("Open Settings") { controller.openLoginItemsSettings() }
            }
        case (.enabled, .playing?):
            row("music.note", .green, controller.agentStatus?.title ?? "", detail: controller.agentStatus?.artist)
        case (.enabled, .discordUnavailable?):
            row("bubble.left.and.exclamationmark.bubble.right", .orange, "Waiting for Discord to open.")
        case (.enabled, .musicAccessDenied?):
            row("lock.fill", .orange, "Allow access to Music.") {
                Button("Open Settings") { controller.openAutomationSettings() }
            }
        case (.enabled, _):
            row("pause.circle", .secondary, "Nothing playing in Music.")
        default:
            row("power", .secondary, "Off")
        }
        if let error = controller.lastError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func row(
        _ symbol: String, _ color: Color, _ title: String, detail: String? = nil,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            action()
        }
    }
}
