import AppKit
import BridgeCore
import Combine
import ServiceManagement

final class BridgeModel: ObservableObject {
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: "visibility.dock") }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "visibility.menuBar") }
    }
    @Published var language: AppLanguage {
        didSet {
            L10n.language = language
            defaults.set(language.rawValue, forKey: "language")
        }
    }
    @Published var configuration: Configuration {
        didSet {
            guard configuration != oldValue else { return }
            save()
            releaseAll()
            events.configuration = configuration
            if configuration.inputMode != oldValue.inputMode || configuration.enabled != oldValue.enabled { reconnect() }
        }
    }
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    @Published private(set) var status = L10n.text(.checkingPermissions)
    @Published var presentationStatus = ""
    var presentationProvider: (() -> String)?
    @Published private(set) var devices: [String] = []
    @Published private(set) var log: [String] = []
    @Published private(set) var learning = false
    @Published private(set) var countdown = 0
    @Published private(set) var sentCount = 0
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false

    private let hid = HIDMonitor()
    private let hidpp = HIDPPMonitor()
    private let events = EventMonitor()
    private let emitter = KeyboardEmitter()
    private var latch = TriggerLatch()
    private var permissionTimer: Timer?
    private var learningTimer: Timer?
    private var countdownTimer: Timer?
    private var pendingRelay: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var learnedHIDAwaitingRelease: HIDBinding?
    private var learnedMouseAwaitingRelease: Int64?
    private var testing = false
    private var suspended = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Independent preferences replace 1.3's mutually exclusive mode; both default off.
        showDockIcon = defaults.bool(forKey: "visibility.dock")
        showMenuBarIcon = defaults.bool(forKey: "visibility.menuBar")
        let selectedLanguage = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "system") ?? .system
        language = selectedLanguage
        L10n.language = selectedLanguage
        status = L10n.text(.checkingPermissions)
        if let data = defaults.data(forKey: "configuration.v1"), let config = try? JSONDecoder().decode(Configuration.self, from: data) {
            configuration = config
        } else { configuration = Configuration() }
        emitter.onMessage = { [weak self] in self?.append($0) }
        hid.onStatus = { [weak self] in self?.status = $0; self?.append($0) }
        hid.onDevices = { [weak self] in self?.devices = $0 }
        hid.onDisconnect = { [weak self] in self?.releaseAll(); self?.append(L10n.text(.disconnected)) }
        hid.onButton = { [weak self] binding, down in self?.handleHID(binding, down: down) }
        hidpp.onButton = { [weak self] binding, down in self?.handleHID(binding, down: down) }
        hidpp.onStatus = { [weak self] in self?.status = $0; self?.append($0) }
        hidpp.onDisconnect = { [weak self] in self?.releaseAll(); self?.append(L10n.text(.disconnected)) }
        events.onMouse = { [weak self] button, down in self?.handleMouse(button, down: down) }
        events.onRelay = { [weak self] in self?.scheduleRelay() }
        events.onStatus = { [weak self] in self?.status = $0; self?.append($0) }
        events.onInterrupted = { [weak self] in self?.releaseAll(); self?.append(L10n.text(.listenerResumed)) }
        refreshPermissions()
        reconnect()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissions() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspended = true
                self?.releaseAll()
                self?.cancelLearning()
                self?.cancelCountdown()
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspended = false
                self?.reconnect()
            })
        }
    }

    #if DEBUG
    private var previewOnly = false
    /// Offscreen layout fixtures never open input monitors or write the user's preferences.
    init(previewLanguage: AppLanguage, configuration: Configuration, permissions: Bool) {
        defaults = UserDefaults(suiteName: "MasterKey.layout-preview")!
        showDockIcon = false
        showMenuBarIcon = false
        language = previewLanguage
        L10n.language = previewLanguage
        self.configuration = configuration
        previewOnly = true
        accessibility = permissions
        inputMonitoring = permissions
        status = L10n.text(permissions ? .ready : .needAccessibility)
        devices = ["USB Receiver · USB"]
    }
    #endif

    var ready: Bool {
        guard accessibility, configuration.enabled, !configuration.conflictsWithRelay else { return false }
        #if DEBUG
        if previewOnly { return true }
        #endif
        if configuration.inputMode != .hid { return events.isRunning }
        guard inputMonitoring, let binding = configuration.hidBinding else { return false }
        return binding.controlID == nil ? hid.isOpen && !devices.isEmpty : hidpp.isOpen
    }

    func reconnect() {
        releaseAll()
        cancelLearning()
        hid.stop()
        hidpp.stop()
        events.stop()
        learnedHIDAwaitingRelease = nil
        learnedMouseAwaitingRelease = nil
        devices = []
        events.configuration = configuration
        guard configuration.enabled else { status = L10n.text(.paused); return }
        guard accessibility else { status = L10n.text(.needAccessibility); return }
        if configuration.inputMode == .hid {
            guard inputMonitoring else { status = L10n.text(.needInput); return }
            hid.start()
            hidpp.start()
        } else { events.start() }
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openPrivacy("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openPrivacy("Privacy_ListenEvent")
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    func learn() {
        guard accessibility, configuration.enabled else { append(L10n.text(.needEnabled)); return }
        guard configuration.inputMode != .hid || inputMonitoring else { append(L10n.text(.needInput)); return }
        releaseAll()
        if configuration.inputMode == .hid { hidpp.rediscover() }
        learning = true
        events.learning = true
        append(L10n.text(.learningStarted))
        learningTimer?.invalidate()
        learningTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.cancelLearning()
            self?.append(L10n.text(.learningTimeout))
        }
    }

    func cancelLearning() {
        learning = false
        events.learning = false
        learningTimer?.invalidate()
        learningTimer = nil
    }

    func delayedTest(relay: Bool) {
        cancelCountdown()
        releaseAll()
        cancelLearning()
        testing = true
        countdown = 3
        append(L10n.text(relay ? .relayCountdown : .testCountdown))
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.countdown -= 1
            if self.countdown == 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.testing = false
                if relay { self.emitter.emitRelay(self.configuration.relayKey); self.append(L10n.format(.relaySent, self.configuration.relayKey.title)) }
                else { self.send(tap: true) }
            }
        }
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 0
        testing = false
    }

    func releaseAll() {
        cancelCountdown()
        pendingRelay?.cancel()
        pendingRelay = nil
        emitter.release()
        latch.reset()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { append(L10n.format(.loginFailed, error.localizedDescription)) }
        updateLoginStatus()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    func copyDiagnostics() {
        let details = ["MasterKey \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4")",
            "\(L10n.text(.systemLabel)): \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "\(L10n.text(.accessibility)): \(accessibility), \(L10n.text(.inputMonitoring)): \(inputMonitoring)",
            "\(L10n.text(.sourceLabel)): \(configuration.inputMode.title), \(L10n.text(.outputLabel)): \(configuration.outputTitle)",
            "\(L10n.text(.devicesLabel)): \(devices.joined(separator: ", "))", "\(L10n.text(.statusLabel)): \(status)", presentationStatus] + log.reversed()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details.joined(separator: "\n"), forType: .string)
    }

    func shutdown() {
        releaseAll()
        cancelCountdown()
        cancelLearning()
        permissionTimer?.invalidate()
        hid.stop()
        hidpp.stop()
        events.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func handleHID(_ binding: HIDBinding, down: Bool) {
        guard configuration.inputMode == .hid, configuration.enabled, !suspended, !testing else { return }
        if learnedHIDAwaitingRelease?.matches(binding) == true {
            if !down { learnedHIDAwaitingRelease = nil }
            return
        }
        if learning && down {
            learnedHIDAwaitingRelease = binding
            configuration.hidBinding = binding
            cancelLearning()
            append(L10n.format(.recorded, binding.title))
            return
        }
        guard !learning, configuration.hidBinding?.matches(binding) == true else { return }
        handleEdge(down, label: binding.controlID.map { L10n.format(.logitechButton, Int($0)) } ?? L10n.format(.systemButton, Int(binding.usage)))
    }

    private func handleMouse(_ button: Int64, down: Bool) {
        guard configuration.inputMode == .mouse, configuration.enabled, !suspended, !testing else { return }
        if learnedMouseAwaitingRelease == button {
            if !down { learnedMouseAwaitingRelease = nil }
            return
        }
        if learning && down {
            learnedMouseAwaitingRelease = button
            configuration.mouseButton = button
            cancelLearning()
            append(L10n.format(.recorded, L10n.format(.systemButton, Int(button + 1))))
            return
        }
        guard !learning, configuration.mouseButton == button else { return }
        handleEdge(down, label: L10n.format(.systemButton, Int(button + 1)))
    }

    private func handleEdge(_ down: Bool, label: String) {
        switch latch.receive(down: down) {
        case .began:
            append(L10n.format(.pressed, label))
            send(tap: configuration.pressMode == .tap)
        case .ended:
            append(L10n.format(.released, label))
            if configuration.pressMode == .hold { emitter.release() }
        case .none: break
        }
    }

    private func scheduleRelay() {
        guard !suspended, !testing else { return }
        append(L10n.format(.relayReceived, configuration.relayKey.title))
        pendingRelay?.cancel()
        // Options+ may send modifier releases after the main key-up. Wait for those releases.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.configuration.enabled, self.configuration.inputMode == .relay else { return }
            self.send(tap: true)
        }
        pendingRelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func send(tap: Bool) {
        guard !configuration.conflictsWithRelay else { append(L10n.text(.relayConflict)); return }
        if emitter.begin(configuration, tap: tap) { sentCount += 1 }
    }

    private func refreshPermissions() {
        if let presentation = presentationProvider?(), presentation != presentationStatus { presentationStatus = presentation }
        let ax = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let changed = ax != accessibility || input != inputMonitoring
        if accessibility != ax { accessibility = ax }
        if inputMonitoring != input { inputMonitoring = input }
        updateLoginStatus()
        if changed { reconnect() }
    }

    private func updateLoginStatus() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled || status == .requiresApproval
        let needsApproval = status == .requiresApproval
        if launchAtLogin != enabled { launchAtLogin = enabled }
        if loginNeedsApproval != needsApproval { loginNeedsApproval = needsApproval }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: "configuration.v1") }
    }

    private func append(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.insert("\(time)  \(message)", at: 0)
        if log.count > 80 { log.removeLast(log.count - 80) }
    }
}
