import SwiftUI

/// The minimalist popover shown from the menu-bar icon.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var appState = AppState.shared

    /// Rows are pinned to this height so the list can be sized exactly, with no
    /// leftover strip under the last one.
    private let rowHeight: CGFloat = 26

    /// One row per layout, so the list grows and shrinks with the cycle rather
    /// than leaving empty space or scrolling. Capped so a long list can't push
    /// the panel off screen.
    private var listHeight: CGFloat {
        let rows = max(settings.layoutIDs.count, 1)
        return min(CGFloat(rows) * rowHeight, 300)
    }

    /// Says what the button will do, or why it can't.
    private var updateButtonTitle: String {
        if let version = appState.availableUpdate { return "Update to \(version)" }
        return settings.checkForUpdates ? "Up to date" : "Update"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("LangSwitcher")
                    .font(.headline)
                Text(UpdateChecker.currentVersion)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Chosen layouts")
                    .font(.subheadline)
                Text("Double-tap \(settings.hotkey.symbol) to cycle through these in order. Drag to reorder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            List {
                ForEach(settings.layoutIDs, id: \.self) { id in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(KeyboardLayouts.layout(id: id)?.name ?? id)
                        Spacer()
                        Button {
                            settings.remove(id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.canRemove)
                        .opacity(settings.canRemove ? 1 : 0.3)
                        .help(settings.canRemove
                              ? "Remove from the cycle"
                              : "Keep at least \(Settings.minimumLayouts) layouts")
                    }
                    .frame(height: rowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                }
                .onMove { settings.move(from: $0, to: $1) }
            }
            // The bordered style draws square corners, so use a plain list and
            // supply our own rounded border to match the panel.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, rowHeight)
            .frame(height: listHeight)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )

            HStack {
                Menu {
                    ForEach(settings.availableToAdd) { layout in
                        Button(layout.name) { settings.add(layout.id) }
                    }
                } label: {
                    Text("Add layout")
                }
                // Sized to its content: a fixed width left the bezel wider than
                // the label and pushed it out of line with everything else.
                .fixedSize()
                .disabled(settings.availableToAdd.isEmpty)
                Spacer()
            }

            Picker("Hotkey:", selection: $settings.hotkey) {
                ForEach(HotkeyModifier.allCases) { modifier in
                    Text("Double-tap \(modifier.symbol) \(modifier.name)").tag(modifier)
                }
            }
            .pickerStyle(.menu)

            Picker("Convert:", selection: $settings.scope) {
                Text("Last word").tag(Scope.word)
                Text("Whole text").tag(Scope.text)
            }
            .pickerStyle(.menu)

            // The three toggles read as one group rather than being split
            // across the panel.
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                Toggle("Remember layout per app", isOn: $settings.rememberLayoutPerApp)
                    .help("Switch back to the layout you last used in each app")
                Toggle("Update automatically", isOn: $settings.checkForUpdates)
                    .help("Checks GitHub once a day and installs a newer version")
            }
            .toggleStyle(.checkbox)

            // Running from anywhere but /Applications is how duplicate copies
            // start competing for the same permission.
            if !Instance.isInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Running from \(Instance.location)", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("Move LangSwitcher to Applications and open it from there, "
                         + "or macOS keeps asking for permission.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Shown only when the hotkey isn't actually live.
            if !appState.isListening {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Hotkey inactive", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("Allow LangSwitcher under Accessibility and it starts working.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Spacer()
                        Button("Open Settings", action: Permissions.openAccessibilitySettings)
                            .controlSize(.small)
                    }
                }
            }

            if let status = appState.updateStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                // Stays disabled until a newer release has actually been seen.
                Button(updateButtonTitle) {
                    guard let version = appState.availableUpdate else { return }
                    appState.updateStatus = "Installing \(version)…"
                    Updater.install(version: version) { result in
                        if case .failure(let error) = result {
                            appState.updateStatus = error.localizedDescription
                        }
                    }
                }
                .disabled(appState.availableUpdate == nil)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
