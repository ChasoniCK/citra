import ServiceManagement
import SwiftUI
import UserNotifications

/// The Settings window. Every control writes the `AppSettings` key the app reads; ring appearance and
/// shortcuts take effect from the next drag.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "command") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            ConversionSettings().tabItem { Label("Conversions", systemImage: "arrow.triangle.2.circlepath") }
            FileActionSettings().tabItem { Label("File Actions", systemImage: "folder") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppSettings.Key.enabled) private var enabled = true
    @AppStorage(AppSettings.Key.notifications) private var notifications = true
    @AppStorage(AppSettings.Key.outputLocation) private var location = OutputLocation.original
    @AppStorage(AppSettings.Key.outputFolder) private var folder = ""
    @State private var loginItem = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Citra", isOn: $enabled)
                Toggle("Launch at login", isOn: Binding(get: { loginItem == .enabled || loginItem == .requiresApproval },
                                                        set: setLaunchAtLogin))
                if loginItem == .requiresApproval {
                    HStack {
                        Text("Allow Citra in Login Items to finish.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
            Section("Results") {
                Picker("Save results", selection: $location) {
                    Text("Next to the original").tag(OutputLocation.original)
                    Text("In a folder").tag(OutputLocation.folder)
                }
                if location == .folder {
                    HStack {
                        Text(folder.isEmpty ? "No folder chosen — results go next to the original" : (folder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Notify when a task finishes", isOn: $notifications)
                if notifications, notificationsDenied {
                    HStack {
                        Text("Notifications for Citra are off in System Settings.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            Section("Permissions") {
                Text("Citra needs no special permissions. It watches mouse drags without Accessibility or Input Monitoring, and reads only the files you drop on the ring.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginItem = SMAppService.mainApp.status
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

private struct ShortcutSettings: View {
    @AppStorage(AppSettings.Key.modifier(.conversion)) private var conversion = ModifierKey.command
    @AppStorage(AppSettings.Key.modifier(.tools)) private var tools = ModifierKey.shift
    @AppStorage(AppSettings.Key.modifier(.fileActions)) private var fileActions = ModifierKey.control

    private var mapping: ModifierMapping { ModifierMapping(conversion: conversion, tools: tools, fileActions: fileActions) }

    private func binding(_ mode: MenuMode) -> Binding<ModifierKey> {
        Binding(get: { mapping[mode] }, set: { key in
            let next = mapping.assigning(key, to: mode) // a key used by another mode swaps, never duplicates
            conversion = next.conversion
            tools = next.tools
            fileActions = next.fileActions
        })
    }

    var body: some View {
        Form {
            Section {
                ForEach(MenuMode.allCases, id: \.self) { mode in
                    Picker(mode.title, selection: binding(mode)) {
                        ForEach(ModifierKey.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            } footer: {
                Text("Press the modifier after you start dragging. If several are held, ⌘ wins over ⇧, ⇧ over ⌃, ⌃ over ⌥. Choosing a key another mode uses swaps the two.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Defaults") {
                    conversion = .command
                    tools = .shift
                    fileActions = .control
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(AppSettings.Key.ringSize) private var size = RingSize.normal
    @AppStorage(AppSettings.Key.motion) private var motion = Motion.normal
    @AppStorage(AppSettings.Key.accent) private var accent = Accent.orange

    var body: some View {
        Form {
            Picker("Menu size", selection: $size) {
                Text("Small").tag(RingSize.small)
                Text("Normal").tag(RingSize.normal)
                Text("Large").tag(RingSize.large)
            }
            .pickerStyle(.segmented)
            Picker("Animations", selection: $motion) {
                Text("Off").tag(Motion.off)
                Text("Fast").tag(Motion.fast)
                Text("Normal").tag(Motion.normal)
            }
            .pickerStyle(.segmented)
            LabeledContent("Accent") {
                HStack(spacing: 10) {
                    ForEach(Accent.allCases, id: \.self) { choice in
                        Button { accent = choice } label: {
                            Circle()
                                .fill(LinearGradient(colors: [choice.gradient.top, choice.gradient.bottom], startPoint: .top, endPoint: .bottom))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.primary.opacity(choice == accent ? 0.9 : 0), lineWidth: 2).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .help(choice.rawValue.capitalized)
                    }
                }
            }
            Text("Changes apply from the next drag.").foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ConversionSettings: View {
    @AppStorage(AppSettings.Key.jpegQuality) private var jpeg = 0.9
    @AppStorage(AppSettings.Key.heicQuality) private var heic = 0.8
    @AppStorage(AppSettings.Key.videoQuality) private var video = VideoQuality.passthrough

    /// Registered actions grouped by what they work on, with availability on this Mac.
    private var groups: [(String, String, Bool)] {
        let all = Registry.all(for: .conversion) + Registry.all(for: .tools)
        return [("image.", "Images"), ("zip.", "ZIP archives"), ("video.", "Video")].map { prefix, name in
            let actions = all.filter { $0.id.hasPrefix(prefix) }
            return (name, actions.map(\.title).joined(separator: ", "), actions.allSatisfy(\.isAvailable))
        }
    }

    var body: some View {
        Form {
            Section("Images") {
                qualitySlider("JPEG quality", $jpeg)
                qualitySlider("HEIC quality", $heic)
            }
            Section("Video") {
                Picker("MOV conversion", selection: $video) {
                    Text("Copy streams when possible (fast, lossless)").tag(VideoQuality.passthrough)
                    Text("Always re-encode").tag(VideoQuality.reencode)
                }
            }
            Section("Available on this Mac") {
                ForEach(groups, id: \.0) { name, titles, available in
                    LabeledContent(name) {
                        Text(available ? titles : "\(titles) — some unavailable")
                            .foregroundStyle(available ? Color.secondary : Color.orange)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func qualitySlider(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: 0.5...1, step: 0.05)
                Text("\(Int((value.wrappedValue * 100).rounded())) %").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct FileActionSettings: View {
    @AppStorage(AppSettings.Key.terminal) private var terminal = TerminalChoice.terminal
    @AppStorage(AppSettings.Key.shelfEdge) private var edge = ShelfEdge.right

    var body: some View {
        Form {
            Picker("Open folders in", selection: $terminal) {
                Text("Terminal").tag(TerminalChoice.terminal)
                Text(OpenInTerminal.isITermInstalled ? "iTerm2" : "iTerm2 (not installed — Terminal is used)").tag(TerminalChoice.iterm)
            }
            Picker("Shelf appears at", selection: $edge) {
                Text("Left edge").tag(ShelfEdge.left)
                Text("Right edge").tag(ShelfEdge.right)
            }
            .pickerStyle(.segmented)
            Text("Drag the shelf near a side edge to pin it there. Files dragged out of the shelf are copied; removing one from the shelf never touches the file.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
