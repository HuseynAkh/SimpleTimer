import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: TimerStore
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @Environment(\.colorScheme) private var scheme
    @State private var adding = false
    @State private var restore = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { value in Text(value.rawValue.capitalized).tag(value) }
                    }.pickerStyle(.segmented)
                }
                Section("Sessions") {
                    ForEach(store.state.presets, id: \.kind) { preset in
                        NavigationLink { SessionEditor(preset: preset) } label: {
                            HStack {
                                Text(preset.name).fontWeight(.medium)
                                Spacer()
                                Text(durationLabel(preset.minutes)).foregroundStyle(.secondary)
                            }.padding(.vertical, 10).padding(.horizontal, 12)
                                .background(Palette.color(preset.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        }.listRowSeparator(.hidden)
                    }
                    Button { adding = true } label: { Label("New session", systemImage: "plus") }
                }
                Section("Feedback") {
                    Toggle("Completion sound", isOn: Binding(get: { store.state.sound }, set: { store.state.sound = $0; store.save(); Task { await store.sync() } }))
                    Toggle("Haptics", isOn: Binding(get: { store.state.haptics }, set: { store.state.haptics = $0; store.save() }))
                }
                Section {
                    NavigationLink { ExportScreen() } label: { Label("Export & backup", systemImage: "square.and.arrow.up") }
                } footer: { Text("Your history stays on this iPhone unless you choose to share it.") }
                Section {
                    Button("Restore default sessions") { restore = true }
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(scheme, for: .navigationBar)
            .sheet(isPresented: $adding) { NavigationStack { SessionEditor(preset: nil) } }
            .confirmationDialog("Restore the four default sessions? Your history and custom sessions stay.", isPresented: $restore, titleVisibility: .visible) {
                Button("Restore defaults") { store.restore() }
            }
        }
    }
}

struct SessionEditor: View {
    @EnvironmentObject private var store: TimerStore
    @Environment(\.dismiss) private var dismiss
    let preset: Preset?
    @State private var name: String
    @State private var minutes: Int
    @State private var color: String
    @State private var deleting = false
    init(preset: Preset?) {
        self.preset = preset
        _name = State(initialValue: preset?.name ?? "")
        _minutes = State(initialValue: preset?.minutes ?? 25)
        _color = State(initialValue: preset?.color ?? "blue")
    }
    var body: some View {
        Form {
            Section { TextField("Session name", text: $name).onChange(of: name) { _, value in name = String(value.prefix(40)) } }
            Section {
                LabeledContent("Minutes") {
                    TextField("Minutes", value: $minutes, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minWidth: 70)
                        .accessibilityLabel("Duration in minutes")
                }
                Stepper("\(durationLabel(minutes))", value: $minutes, in: 1...240, step: 5)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach([15, 25, 45, 60, 90], id: \.self) { value in
                            Button("\(value)m") { minutes = value }.buttonStyle(.bordered)
                                .tint(minutes == value ? .accentColor : .secondary)
                                .accessibilityLabel("\(value) minutes")
                        }
                    }
                }
            } header: { Text("Duration") } footer: { Text("1–240 minutes. Type a value or use a quick choice.") }
            Section("Colour") { ColorSwatches(selection: $color, label: name.isEmpty ? "Session" : name) }
            if preset?.kind.isCustom == true {
                Section { Button("Delete session", role: .destructive) { deleting = true }
                        .disabled(preset?.kind == store.state.selected && store.state.session.isActive) }
            }
        }
        .navigationTitle(preset == nil ? "New session" : "Edit session").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if preset == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if var edited = preset { edited.customName = name.trimmingCharacters(in: .whitespacesAndNewlines); edited.minutes = minutes; edited.color = color; store.edit(edited) }
                    else { _ = store.state.addPreset(name: name, minutes: minutes, color: color); store.save() }
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(1...240).contains(minutes))
            }
        }
        .confirmationDialog("Delete this session type? Its history stays.", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) { if let preset { _ = store.state.removePreset(preset.kind); store.save() }; dismiss() }
        }
    }
}
struct ColorSwatches: View {
    @Binding var selection: String
    var label: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(Palette.names, id: \.self) { name in
                Button { selection = name } label: {
                    HStack {
                        Text(name.capitalized).font(.body.weight(.medium))
                        Spacer(minLength: 2)
                        Image(systemName: selection == name ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                    }.foregroundStyle(.primary).padding(14).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.color(name).opacity(selection == name ? 0.3 : 0.16), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selection == name ? Palette.chartColor(name) : .clear, lineWidth: 2))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel("\(label), \(name)")
                    .accessibilityAddTraits(selection == name ? .isSelected : [])
            }
        }.padding(.vertical, 8)
    }
}
