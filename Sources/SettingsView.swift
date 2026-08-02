import SwiftUI

/// The minimalist popover shown from the menu-bar icon.
struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LangSwitcher")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Double-shift cycles through:")
                    .font(.subheadline)
                Text("Each press moves to the next layout below (wraps around). Drag to reorder.")
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
                }
                .onMove { settings.move(from: $0, to: $1) }
            }
            .frame(height: 130)
            .listStyle(.bordered)

            HStack {
                Menu {
                    ForEach(settings.availableToAdd) { layout in
                        Button(layout.name) { settings.add(layout.id) }
                    }
                } label: {
                    Label("Add layout", systemImage: "plus")
                }
                .disabled(settings.availableToAdd.isEmpty)
                .frame(width: 160)
                Spacer()
            }

            Picker("Convert:", selection: $settings.scope) {
                Text("Last word").tag(Scope.word)
                Text("Whole text").tag(Scope.text)
            }
            .pickerStyle(.menu)

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
}
