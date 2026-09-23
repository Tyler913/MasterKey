import AppKit
import BridgeCore

final class EventMonitor {
    var configuration = Configuration()
    var learning = false
    var onMouse: ((Int64, Bool) -> Void)?
    var onRelay: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var relayDown: UInt16?
    private var swallowedButtons = Set<Int64>()
    var isRunning: Bool { tap != nil }

    func start() {
        stop()
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<EventMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            onStatus?(L10n.text(.eventFailed))
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onStatus?(L10n.format(.eventConnected, configuration.inputMode.title))
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        relayDown = nil
        swallowedButtons.removeAll()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            relayDown = nil
            swallowedButtons.removeAll()
            onInterrupted?()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != KeyboardEmitter.marker else { return Unmanaged.passUnretained(event) }
        if type == .keyUp, relayDown == UInt16(event.getIntegerValueField(.keyboardEventKeycode)) {
            relayDown = nil
            if configuration.enabled && configuration.inputMode == .relay { onRelay?() }
            return nil
        }
        if type == .otherMouseUp {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if swallowedButtons.remove(button) != nil {
                onMouse?(button, false)
                return nil
            }
        }
        guard configuration.enabled else { return Unmanaged.passUnretained(event) }
        if configuration.inputMode == .relay, type == .keyDown {
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if relayDown == code { return nil }
            if configuration.relayKey.matches(keyCode: code, flags: event.flags.rawValue) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { relayDown = code }
                return nil
            }
        }
        if configuration.inputMode == .mouse && (type == .otherMouseDown || type == .otherMouseUp) {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            // Never intercept primary or secondary clicks.
            guard button >= 2 else { return Unmanaged.passUnretained(event) }
            let selected = learning || button == configuration.mouseButton
            if selected {
                if type == .otherMouseDown { swallowedButtons.insert(button) }
                onMouse?(button, type == .otherMouseDown)
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
