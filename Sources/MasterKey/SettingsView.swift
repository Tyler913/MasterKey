import SwiftUI
import BridgeCore

// Name the property-wrapper type explicitly; recent SDKs also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var model: BridgeModel
    @ViewState private var sheet: Panel? = nil
    private enum Panel: String, Identifiable { case help, diagnostics; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    if !model.accessibility || !model.inputMonitoring { permissions }
                    source
                    output
                    general
                }.padding(.horizontal, 22).padding(.bottom, 20).padding(.top, 4)
            }
            footer
        }
        // Rebuild native picker labels too; AppKit can cache unchanged selection titles.
        .id(model.language)
        .frame(minWidth: 540, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $sheet) { panel in
            if panel == .help { HelpView(model: model) }
            else { DiagnosticsView(model: model) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)!)
                .resizable().interpolation(.high).scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("MasterKey").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(L10n.text(.enabled), isOn: $model.configuration.enabled)
                .toggleStyle(.switch).labelsHidden().accessibilityIdentifier("enabled")
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }

    private var permissions: some View {
        card(.permissions, symbol: "lock.shield") {
            permissionRow(.accessibility, granted: model.accessibility, action: model.requestAccessibility)
            Divider()
            permissionRow(.inputMonitoring, granted: model.inputMonitoring, action: model.requestInputMonitoring)
        }
    }
    private func permissionRow(_ key: TextKey, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(L10n.text(key)); Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(L10n.text(.allowed))
            } else { Button(L10n.text(.allow), action: action) }
        }.frame(minHeight: 24)
    }

    private var source: some View {
        card(.mouseButton, symbol: "computermouse") {
            Picker(L10n.text(.source), selection: $model.configuration.inputMode) {
                ForEach(InputMode.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("inputMode")
            Divider()
            if model.configuration.inputMode == .relay {
                HStack(spacing: 12) {
                    Picker(L10n.text(.relayKey), selection: $model.configuration.relayKey) {
                        ForEach(RelayKey.allCases) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 200)
                    Spacer(minLength: 0)
                    Button(L10n.text(.recordRelay)) { model.delayedTest(relay: true) }
                        .help(L10n.text(.relayRecordHint)).disabled(!model.accessibility || model.countdown > 0)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: model.learning ? "dot.radiowaves.left.and.right" : "cursorarrow.click")
                        .foregroundStyle(model.learning ? Color.accentColor : .secondary)
                    Text(bindingTitle).fontWeight(.medium).lineLimit(2)
                    Spacer(minLength: 4)
                    Button(recordTitle) {
                        if model.learning { model.cancelLearning() } else { model.learn() }
                    }.disabled(!model.accessibility || !model.configuration.enabled || (model.configuration.inputMode == .hid && !model.inputMonitoring))
                        .accessibilityIdentifier("recordButton")
                }.frame(minHeight: 26)
            }
            Text(L10n.text(sourceHint)).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var bindingTitle: String {
        if model.learning { return L10n.text(.pressButton) }
        if model.configuration.inputMode == .mouse { return L10n.format(.systemButton, Int(model.configuration.mouseButton + 1)) }
        guard let binding = model.configuration.hidBinding else { return L10n.text(.noButton) }
        if let control = binding.controlID { return L10n.format(.logitechButton, Int(control)) }
        return L10n.format(.systemButton, Int(binding.usage))
    }
    private var recordTitle: String {
        if model.learning { return L10n.text(.cancel) }
        return L10n.text(model.configuration.hidBinding == nil && model.configuration.inputMode == .hid ? .record : .replace)
    }
    private var sourceHint: TextKey {
        switch model.configuration.inputMode { case .hid: return .directHint; case .mouse: return .mouseHint; case .relay: return .relayHint }
    }

    private var output: some View {
        card(.shortcut, symbol: "waveform") {
            Picker(L10n.text(.shortcut), selection: $model.configuration.outputMode) {
                Text("Fn / 🌐").tag(OutputMode.fn)
                Text(L10n.text(.combination)).tag(OutputMode.shortcut)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("outputMode")
            if model.configuration.outputMode == .shortcut {
                ShortcutRecorder(configuration: $model.configuration)
                    .frame(height: 30)
                    .help(L10n.text(.recordShortcutHint))
            }
            HStack(spacing: 16) {
                if model.configuration.inputMode == .relay {
                    Text(L10n.text(.click)).foregroundStyle(.secondary).help(L10n.text(.relayTapOnly))
                } else {
                    Picker(L10n.text(.behavior), selection: $model.configuration.pressMode) {
                        Text(L10n.text(.click)).tag(PressMode.tap)
                        Text(L10n.text(.hold)).tag(PressMode.hold)
                    }.frame(maxWidth: 300).help(L10n.text(.holdHint))
                }
                Spacer(minLength: 0)
                if model.countdown > 0 {
                    Button(L10n.format(.countdown, model.countdown), action: model.cancelCountdown)
                } else {
                    Button(L10n.text(.test)) { model.delayedTest(relay: false) }
                        .help(L10n.text(.testHint)).accessibilityIdentifier("testOutput")
                        .disabled(!model.accessibility || model.configuration.conflictsWithRelay)
                }
            }.padding(.top, 3)
            if model.configuration.conflictsWithRelay {
                Text(L10n.text(.relayConflict)).font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private var general: some View {
        card(.preferences, symbol: "slider.horizontal.3") {
            Picker(L10n.text(.language), selection: $model.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("language")
            Divider()
            Toggle(L10n.text(.launchAtLogin), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                .toggleStyle(.switch).controlSize(.small)
            Divider()
            Toggle(L10n.text(.showDockIcon), isOn: $model.showDockIcon)
                .toggleStyle(.switch).controlSize(.small).accessibilityIdentifier("showDockIcon")
            Toggle(L10n.text(.showMenuBarIcon), isOn: $model.showMenuBarIcon)
                .toggleStyle(.switch).controlSize(.small).accessibilityIdentifier("showMenuBarIcon")
            if !model.showDockIcon && !model.showMenuBarIcon {
                Text(L10n.text(.backgroundHint)).font(.caption).foregroundStyle(.secondary)
            }
            if model.loginNeedsApproval { Button(L10n.text(.openSettings), action: model.openLoginItems).font(.caption) }
        }
    }
    private func card<Content: View>(_ title: TextKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.text(title), systemImage: symbol).font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 11, content: content).padding(14).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.055), lineWidth: 1))
        }
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Circle().fill(model.ready ? Color.green : Color.secondary.opacity(0.6)).frame(width: 6, height: 6)
                Text(L10n.text(!model.configuration.enabled ? .paused : (model.ready ? .ready : .setupNeeded)))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.reconnect() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L10n.text(.reconnect)).accessibilityLabel(L10n.text(.reconnect))
                Button(L10n.text(.diagnostics)) { sheet = .diagnostics }
                Button { sheet = .help } label: { Image(systemName: "questionmark.circle") }
                    .help(L10n.text(.help)).accessibilityLabel(L10n.text(.help))
                Button(L10n.text(.quitMenu)) { NSApp.terminate(nil) }
            }.buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 13)
        }
    }
}

private struct HelpView: View {
    @ObservedObject var model: BridgeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text(.helpTitle)).font(.title3).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 16) { step("1", .helpStep1); step("2", .helpStep2); step("3", .helpStep3) }
            DisclosureGroup(L10n.text(.troubleshooting)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach([TextKey.helpPermissions, .helpFn, .helpRelay], id: \.self) { key in
                        Text(L10n.text(key)).fixedSize(horizontal: false, vertical: true)
                    }
                }.font(.callout).foregroundStyle(.secondary).padding(.top, 10)
            }
            HStack { Spacer(); Button(L10n.text(.done)) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 480)
    }
    private func step(_ number: String, _ key: TextKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22).background(Color.accentColor.opacity(0.1), in: Circle())
            Text(L10n.text(key)).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var model: BridgeModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text(.diagnostics)).font(.title3).fontWeight(.semibold); Spacer()
                Text(L10n.format(.eventsSent, model.sentCount)).font(.caption).foregroundStyle(.secondary)
            }
            Text(model.status).font(.callout).textSelection(.enabled)
            Text(model.presentationStatus).font(.caption).foregroundStyle(.secondary)
            if !model.devices.isEmpty { Text(model.devices.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                Text(model.log.isEmpty ? L10n.text(.noEvents) : model.log.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 220).padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            Text(L10n.text(.logPrivacy)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text(copied ? .copied : .copy)) { model.copyDiagnostics(); copied = true }
                Button(L10n.text(.releaseKeys), action: model.releaseAll)
                Spacer()
                Button(L10n.text(.done)) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580)
    }
}
