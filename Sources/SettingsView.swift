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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LangSwitcher")
                .font(.headline)

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

            Toggle("Remember layout per app", isOn: $settings.rememberLayoutPerApp)
                .toggleStyle(.checkbox)
                .help("Switch back to the layout you last used in each app")

            // Shown only when the hotkey isn't actually live. Checking the
            // grants alone would cry wolf: a listen-only tap generally runs on
            // Accessibility without Input Monitoring ever being granted.
            if !appState.isListening {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Hotkey inactive", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("Grant these, then it starts working automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !Permissions.isAccessibilityTrusted() {
                        permissionRow("Accessibility", action: Permissions.openAccessibilitySettings)
                    }
                    if !Permissions.isInputMonitoringGranted {
                        permissionRow("Input Monitoring", action: Permissions.openInputMonitoringSettings)
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func permissionRow(_ name: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
                .font(.callout)
            Spacer()
            Button("Open Settings", action: action)
                .controlSize(.small)
        }
    }
}
