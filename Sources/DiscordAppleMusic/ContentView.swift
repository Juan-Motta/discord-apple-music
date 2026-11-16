import PresenceCore
import PresenceKit
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case presence, about
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .presence: "Presence"
        case .about: "About"
        }
    }
}

/// The selected tab. Kept in an observable model (not @State, whose macro needs Xcode) so that
/// changing it inside `withAnimation` animates the indicator and the content.
@MainActor
@Observable
final class TabSelection {
    private static let key = "selectedTab"

    private(set) var tab = Tab(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .presence

    func select(_ next: Tab) {
        guard next != tab else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { tab = next }
        UserDefaults.standard.set(next.rawValue, forKey: Self.key)
    }
}

struct ContentView: View {
    @Bindable var controller: AgentController
    let updater: UpdateController
    let tabs: TabSelection

    static let donateURL = URL(string: "https://buymeacoffee.com/jualopezmo")!
    static let projectURL = URL(string: "https://github.com/Juan-Motta/discord-apple-music")!

    /// A new GitHub issue with the app and macOS versions filled in.
    static func bugReportURL(version: String) -> URL {
        let body = """
            **What happened?**


            **What did you expect?**


            ---
            App \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            """
        var components = URLComponents(string: "https://github.com/Juan-Motta/discord-apple-music/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    var body: some View {
        VStack(spacing: 16) {
            TabBar(tabs: tabs)
            // Both pages stay laid out, so the window always has the taller one's height and
            // never resizes; switching only slides them sideways.
            ZStack(alignment: .top) {
                PresenceTab(controller: controller).page(.presence, selected: tabs.tab)
                AboutTab(updater: updater).page(.about, selected: tabs.tab)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { controller.refresh() }
        .task { await updater.check() }
    }
}

// MARK: - Tab bar

private struct TabBar: View {
    let tabs: TabSelection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let selected = tabs.tab == tab
                Button { tabs.select(tab) } label: {
                    Text(tab.title)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .background(alignment: .leading) {
            // One pill that only slides sideways, so layout changes elsewhere can't nudge it.
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(Tab.allCases.count)
                let index = CGFloat(Tab.allCases.firstIndex(of: tabs.tab) ?? 0)
                SelectionCapsule()
                    .frame(width: width, height: proxy.size.height)
                    .offset(x: width * index)
            }
        }
        .padding(4)
        .glassCapsule()
    }
}

private struct SelectionCapsule: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26, *) {
            // A light tint, like macOS's own segmented control, so the pill stands out from the bar.
            let tint = Color.white.opacity(colorScheme == .dark ? 0.18 : 0.75)
            Capsule().fill(.clear)
                .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 3, y: 1)
        } else {
            Capsule().fill(.background).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
    }
}

// MARK: - Presence

private struct PresenceTab: View {
    @Bindable var controller: AgentController

    var body: some View {
        VStack(spacing: 12) {
            DiscordCard(status: controller.isOn ? controller.agentStatus : nil, settings: controller.settings)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Discord").font(.headline)
                        Text("Runs in the background, even with this window closed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Show in Discord", isOn: Binding(get: { controller.isOn }, set: { controller.setOn($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(14)

                Divider().padding(.horizontal, 14)
                OptionRow("Start at login", isOn: $controller.settings.startAtLogin)

                StatusAction(controller: controller)
            }
            .glassPanel()

            CustomizeSection(controller: controller)
            Link(destination: ContentView.donateURL) {
                Label("Make a donation", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .glassButton()
        }
    }
}

/// Only shown when the user has to do something.
private struct StatusAction: View {
    let controller: AgentController

    var body: some View {
        Group {
            if controller.serviceStatus == .requiresApproval {
                row("Allow it in Login Items to start.") { controller.openLoginItemsSettings() }
            } else if controller.isOn, controller.agentStatus?.state == .musicAccessDenied {
                row("Allow access to Music.") { controller.openAutomationSettings() }
            }
            if let error = controller.lastError {
                Text(error).font(.caption).foregroundStyle(.red).padding([.horizontal, .bottom], 14)
            }
        }
    }

    private func row(_ text: LocalizedStringKey, open: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 14)
            HStack {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Button("Open Settings", action: open)
            }
            .padding(14)
        }
    }
}

/// A look-alike of Discord's "Listening to" card and member-list line. The song comes from what
/// the agent publishes; the settings are applied right away so changes show while you toggle them.
private struct DiscordCard: View {
    let status: AgentStatus?
    let settings: PresenceCore.Settings

    private var playing: AgentStatus? { status?.state == .playing ? status : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(playing != nil ? "Listening to Apple Music" : "Discord preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Discord.secondaryText)

            HStack(spacing: 12) {
                if settings.showCoverArt {
                    Artwork(url: playing?.artworkURL)
                        .opensLink(settings.clickableLinks ? playing?.albumURL : nil)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let playing {
                        link(playing.title ?? "", playing.trackURL, font: .headline, color: Discord.text)
                        link(playing.artist ?? "", playing.artistURL, font: .subheadline, color: Discord.secondaryText)
                        if let album = playing.album {
                            link(album, playing.albumURL, font: .subheadline, color: Discord.secondaryText)
                        }
                        if let start = playing.startedAt, let end = playing.endsAt {
                            ProgressLine(start: start, end: end).padding(.top, 6)
                        }
                    } else {
                        Text(placeholder).font(.headline).foregroundStyle(Discord.text.opacity(0.6))
                        Text("Nothing is shown on your profile.")
                            .font(.subheadline)
                            .foregroundStyle(Discord.secondaryText)
                    }
                }
                .lineLimit(1)
                .contentTransition(.opacity)
            }
            .frame(minHeight: 72)

            if settings.showButton, playing != nil {
                // Verbatim: this is the label Discord shows to others, which is not translated.
                Text(verbatim: "Listen on Apple Music")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Discord.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Discord.track, in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
                    .opensLink(playing?.buttonURL)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Discord.background, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .animation(.smooth(duration: 0.3), value: status)
        .animation(.smooth(duration: 0.3), value: settings)
        .environment(\.colorScheme, .dark)
    }

    /// Song, artist and album are links in Discord when "Clickable" is on.
    /// Song, artist and album open Apple Music, like in Discord, when "Clickable" is on.
    private func link(_ text: String, _ url: String?, font: Font, color: Color) -> some View {
        HoverLink(text: text, url: settings.clickableLinks ? url : nil, font: font, color: color)
    }

    private var placeholder: LocalizedStringKey {
        switch status?.state {
        case nil: "Off"
        case .discordUnavailable?: "Waiting for Discord"
        case .musicAccessDenied?: "No access to Music"
        default: "Nothing playing"
        }
    }
}

/// Text that underlines on hover and opens its link on click, like Discord's activity links.
private struct HoverLink: View {
    let text: String
    let url: String?
    let font: Font
    let color: Color
    // ObservableObject + @StateObject instead of @State: SwiftUI's macro plugin ships only with Xcode.
    @StateObject private var hover = HoverState()

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .underline(hover.isHovering && url != nil, color: color)
            .onHover { hover.isHovering = $0 }
            .opensLink(url)
    }
}

private final class HoverState: ObservableObject {
    @Published var isHovering = false
}

private extension View {
    /// Opens `url` on click with a pointing-hand cursor; does nothing when `url` is nil.
    @ViewBuilder
    func opensLink(_ url: String?) -> some View {
        if let url, let destination = URL(string: url) {
            let clickable = onTapGesture { NSWorkspace.shared.open(destination) }
                .help(destination.absoluteString)
            if #available(macOS 15, *) {
                clickable.pointerStyle(.link)
            } else {
                clickable
            }
        } else {
            self
        }
    }
}

private enum Discord {
    static let background = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let text = Color.white
    static let secondaryText = Color(red: 0.71, green: 0.73, blue: 0.76)
    static let track = Color(red: 0.31, green: 0.31, blue: 0.34)
}

private struct Artwork: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Discord.track
                Image(systemName: "music.note").font(.title2).foregroundStyle(Discord.secondaryText)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(.rect(cornerRadius: 8))
        .id(url)
        .transition(.opacity)
    }
}

private struct ProgressLine: View {
    let start: Date
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(end.timeIntervalSince(start), 1)
            let elapsed = min(max(context.date.timeIntervalSince(start), 0), total)
            HStack(spacing: 8) {
                Text(format(elapsed))
                GeometryReader { proxy in
                    Capsule().fill(Discord.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Discord.text).frame(width: proxy.size.width * elapsed / total)
                        }
                }
                .frame(height: 4)
                Text(format(total))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Discord.secondaryText)
            .contentTransition(.numericText())
            .animation(.linear(duration: 1), value: elapsed)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Customize

private struct CustomizeSection: View {
    @Bindable var controller: AgentController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                OptionRow("Cover art", isOn: $controller.settings.showCoverArt)
                Divider().padding(.horizontal, 14)
                OptionRow("Clickable song, artist and album", isOn: $controller.settings.clickableLinks)
                Divider().padding(.horizontal, 14)
                OptionRow("\u{201C}Listen on Apple Music\u{201D} button", isOn: $controller.settings.showButton)
                Divider().padding(.horizontal, 14)
                HStack {
                    Text("Member list shows")
                    Spacer()
                    Picker("", selection: $controller.settings.statusDisplay) {
                        Text("Song").tag(Settings.StatusDisplay.song)
                        Text("Artist").tag(Settings.StatusDisplay.artist)
                        Text("Apple Music").tag(Settings.StatusDisplay.appName)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .glassPanel()

        }
    }
}

private struct OptionRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - About

private struct AboutTab: View {
    let updater: UpdateController

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Discord Apple Music").font(.title3.weight(.semibold))
                Text("Your Apple Music, on your Discord profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                UpdateRow(updater: updater).padding(14)
                Divider().padding(.horizontal, 14)
                HStack {
                    Text("Source code")
                    Spacer()
                    Link("GitHub", destination: ContentView.projectURL)
                }
                .padding(14)
                Divider().padding(.horizontal, 14)
                HStack {
                    Text("Language")
                    Spacer()
                    Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.apply($0) })) {
                        ForEach(AppLanguage.allCases) { $0.label.tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider().padding(.horizontal, 14)
                HStack {
                    Text("Found a problem?")
                    Spacer()
                    Link("Report a bug", destination: ContentView.bugReportURL(version: updater.versionText))
                }
                .padding(14)
            }
            .glassPanel()

        }
    }
}

private struct UpdateRow: View {
    let updater: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Version \(updater.versionText)")
                Spacer()
                switch updater.state {
                case .idle:
                    Button("Check for Updates") { Task { await updater.check() } }
                case .checking:
                    ProgressView().controlSize(.small)
                case .upToDate:
                    Label("Up to date", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                case .available(let update):
                    Button("Update to \(update.version.description)") { Task { await updater.install(update) } }
                        .buttonStyle(.borderedProminent)
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("Updating…").foregroundStyle(.secondary)
                case .failed(_, let update?):
                    Button("Download") { updater.openReleasePage(update) }
                case .failed:
                    Button("Try Again") { Task { await updater.check() } }
                }
            }
            if case .failed(let message, _) = updater.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .animation(.smooth, value: updater.state)
    }
}

// MARK: - Glass

private extension View {
    /// Shows this page when it is the selected tab, and slides it off to its side otherwise.
    func page(_ tab: Tab, selected: Tab) -> some View {
        let order = Tab.allCases
        let distance = CGFloat(order.firstIndex(of: tab)! - order.firstIndex(of: selected)!)
        return offset(x: distance * 420)
            .opacity(distance == 0 ? 1 : 0)
            .allowsHitTesting(distance == 0)
            .accessibilityHidden(distance != 0)
    }

    /// A rounded Liquid Glass panel, or a material panel before macOS 26.
    @ViewBuilder
    func glassPanel() -> some View {
        let panel = frame(maxWidth: .infinity, alignment: .leading)
        if #available(macOS 26, *) {
            panel.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            panel.background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).controlSize(.large)
        } else {
            buttonStyle(.bordered).controlSize(.large)
        }
    }
}
