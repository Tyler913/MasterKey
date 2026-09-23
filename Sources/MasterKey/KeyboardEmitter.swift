import AppKit
import BridgeCore

final class KeyboardEmitter {
    static let marker: Int64 = 0x4D41535445524B
    private let source = CGEventSource(stateID: .privateState)
    private var activePlan: KeyboardPlan?
    private var releaseWork: DispatchWorkItem?
    private var watchdog: DispatchWorkItem?
    var onMessage: ((String) -> Void)?
    var isHolding: Bool { activePlan != nil }

    @discardableResult
    func begin(_ configuration: Configuration, tap: Bool) -> Bool {
        guard activePlan == nil else { return false }
        guard AXIsProcessTrusted() else {
            onMessage?(L10n.text(.needAccessibility))
            return false
        }
        // Avoid mixing a generated chord with modifiers the user is physically holding.
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        guard flags & 0x9E0000 == 0 else {
            onMessage?(L10n.text(.physicalModifierHeld))
            return false
        }
        let plan = KeyboardPlan(configuration: configuration)
        activePlan = plan
        post(plan.down)
        onMessage?(L10n.format(.sentDown, configuration.outputTitle))
        if tap {
            let work = DispatchWorkItem { [weak self] in self?.release() }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
        }
        let safety = DispatchWorkItem { [weak self] in
            self?.release()
            self?.onMessage?(L10n.text(.safetyRelease))
        }
        watchdog = safety
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: safety)
        return true
    }

    func release() {
        releaseWork?.cancel()
        watchdog?.cancel()
        releaseWork = nil
        watchdog = nil
        guard let plan = activePlan else { return }
        activePlan = nil
        // Preserve physical modifier changes made while the generated key was held.
        let physical = CGEventSource.flagsState(.hidSystemState).rawValue
        post(plan.up, additionalFlags: physical)
        onMessage?(L10n.text(.sentUp))
    }

    func emitRelay(_ relay: RelayKey) {
        guard AXIsProcessTrusted() else { onMessage?(L10n.text(.needAccessibility)); return }
        post([.init(keyCode: relay.keyCode, kind: .down, flags: relay.flags)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            self?.post([.init(keyCode: relay.keyCode, kind: .up, flags: relay.flags)])
        }
    }

    private func post(_ steps: [KeyStep], additionalFlags: UInt64 = 0) {
        for step in steps {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: step.keyCode, keyDown: step.kind != .up) else { continue }
            if step.kind == .flagsChanged { event.type = .flagsChanged }
            event.flags = CGEventFlags(rawValue: step.flags | additionalFlags)
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.post(tap: .cghidEventTap)
        }
    }
}
