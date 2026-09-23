import Foundation
import CoreGraphics
import BridgeCore

// A standalone regression runner also works with Command Line Tools, without XCTest / full Xcode.
private func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(rhs), got \(lhs) at \(file):\(line)")
}
private func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(value, "Expected true at \(file):\(line)")
}
private func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(!value, "Expected false at \(file):\(line)")
}
private enum CheckError: Error { case unexpectedNil }
private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckError.unexpectedNil }
    return value
}

final class BridgeCoreTests {
    func testPhysicalShortcutCaptureAndCancelBeforeCommit() throws {
        var capture = ShortcutCapture()
        XCTAssertTrue(capture.modifierChanged(keyCode: 59)) // left Control
        XCTAssertTrue(capture.modifierChanged(keyCode: 54)) // right Command
        XCTAssertFalse(capture.modifierChanged(keyCode: 6))
        XCTAssertTrue(capture.modifierTitle.contains(L10n.text(.left)))
        XCTAssertTrue(capture.modifierTitle.contains(L10n.text(.right)))
        let recorded = try XCTUnwrap(capture.shortcut(for: 6))
        XCTAssertEqual(recorded.control, .left)
        XCTAssertEqual(recorded.command, .right)
        XCTAssertEqual(recorded.option, .off)
        XCTAssertEqual(recorded.key, .z)
        XCTAssertTrue(capture.shortcut(for: 56) == nil) // Modifier alone cannot finish a combination.
        XCTAssertTrue(capture.modifierChanged(keyCode: 54)) // release right Command
        XCTAssertEqual(try XCTUnwrap(capture.shortcut(for: 8)).command, .off)
        let flagged = try XCTUnwrap(ShortcutCapture().shortcut(for: 0, flags: 0x140009))
        XCTAssertEqual(flagged.control, .left)
        XCTAssertEqual(flagged.command, .left)
        let right = try XCTUnwrap(ShortcutCapture().shortcut(for: 0, flags: 0x142010))
        XCTAssertEqual(right.control, .right)
        XCTAssertEqual(right.command, .right)
    }

    func testShortcutRecorderSupportsCommonKeysAndOldSavedFormat() throws {
        for keyCode: UInt16 in [0, 6, 18, 36, 49, 51, 79, 80, 122, 123, 126] {
            XCTAssertTrue(ShortcutKey(rawValue: keyCode).isRecordable)
            XCTAssertFalse(ShortcutKey(rawValue: keyCode).title.isEmpty)
        }
        for modifierCode: UInt16 in [54, 55, 56, 58, 59, 60, 61, 62, 63] {
            XCTAssertFalse(ShortcutKey(rawValue: modifierCode).isRecordable)
        }
        let old = Data(#"{"enabled":true,"inputMode":"hid","outputMode":"shortcut","pressMode":"tap","control":"left","command":"left","option":"off","shift":"off","key":6,"relayKey":"f18","mouseButton":3}"#.utf8)
        let config = try JSONDecoder().decode(Configuration.self, from: old)
        XCTAssertEqual(config.key, .z)
        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["key"] as? Int, 6)
        let new = try XCTUnwrap(ShortcutCapture().shortcut(for: 0)).applying(to: config)
        XCTAssertEqual(new.key.title, "A")
        XCTAssertEqual(new.control, .off)
        XCTAssertEqual(new.command, .off)
    }

    func testSystemLanguageResolution() {
        let cases: [([String], AppLanguage)] = [
            (["zh-Hans-CN"], .simplifiedChinese), (["zh_Hans_TW"], .simplifiedChinese),
            (["zh-Hant"], .traditionalChinese), (["zh-TW"], .traditionalChinese),
            (["zh-HK"], .traditionalChinese), (["zh-MO"], .traditionalChinese),
            (["zh-CN"], .simplifiedChinese), (["en-CA", "zh-Hans"], .english),
            (["fr-CA", "zh-Hant"], .traditionalChinese), (["de"], .english), ([], .english)
        ]
        for (preferred, expected) in cases { XCTAssertEqual(AppLanguage.system.resolved(preferred: preferred), expected) }
        XCTAssertEqual(AppLanguage.english.resolved(preferred: ["zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.traditionalChinese.resolved(preferred: ["en"]), .traditionalChinese)
    }

    func testTranslationCoverageAndFormatArguments() throws {
        let placeholders = try NSRegularExpression(pattern: "%[0-9]*[@dX]")
        func signature(_ text: String) -> [String] {
            placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }
        }
        for key in TextKey.allCases {
            let reference = signature(L10n.text(key, language: .english))
            for language in [AppLanguage.english, .simplifiedChinese, .traditionalChinese] {
                let value = L10n.text(key, language: language)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(signature(value), reference)
            }
        }
    }

    func testLanguageDoesNotChangeSavedBindingsOrKeyboardEvents() throws {
        let previousLanguage = L10n.language
        defer { L10n.language = previousLanguage }
        var configuration = Configuration()
        configuration.outputMode = .shortcut
        configuration.control = .right
        configuration.hidBinding = HIDBinding(productID: 0xC548, locationID: 123, transport: "USB", product: "USB Receiver", usage: 0xC3, reportID: 0x11, deviceIndex: 3, controlID: 0xC3)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = try encoder.encode(configuration)
        let plan = KeyboardPlan(configuration: configuration)
        for language in [AppLanguage.english, .simplifiedChinese, .traditionalChinese] {
            L10n.language = language
            XCTAssertEqual(try encoder.encode(configuration), saved)
            XCTAssertEqual(KeyboardPlan(configuration: configuration).down, plan.down)
            XCTAssertEqual(KeyboardPlan(configuration: configuration).up, plan.up)
            XCTAssertTrue(L10n.format(.logitechButton, 0xC3).contains("00C3"))
            XCTAssertTrue(L10n.format(.eventsSent, 12).contains("12"))
        }
    }

    func testFnUsesModifierEventsAndReleases() {
        let plan = KeyboardPlan(configuration: Configuration())
        XCTAssertEqual(plan.down, [.init(keyCode: 63, kind: .flagsChanged, flags: CGEventFlags.maskSecondaryFn.rawValue)])
        XCTAssertEqual(plan.up, [.init(keyCode: 63, kind: .flagsChanged, flags: 0)])
    }

    func testLeftControlCommandZHasBothGenericAndSidedFlags() {
        var config = Configuration()
        config.outputMode = .shortcut
        let plan = KeyboardPlan(configuration: config)
        XCTAssertEqual(plan.down.map(\.keyCode), [59, 55, 6])
        XCTAssertEqual(plan.down.last?.flags, 0x140009)
        XCTAssertEqual(plan.up.map(\.keyCode), [6, 55, 59])
        XCTAssertEqual(plan.up.map(\.flags), [0x140009, 0x40001, 0])
    }

    func testRightControlCommandZIsDistinctFromLeft() {
        var config = Configuration()
        config.outputMode = .shortcut
        config.control = .right
        config.command = .right
        let plan = KeyboardPlan(configuration: config)
        XCTAssertEqual(plan.down.map(\.keyCode), [62, 54, 6])
        XCTAssertEqual(plan.down.last?.flags, 0x142010)
        XCTAssertEqual(plan.up.last?.flags, 0)
    }

    func testEveryModifierCombinationIsBalanced() {
        for control in KeySide.allCases {
            for command in KeySide.allCases {
                for option in KeySide.allCases {
                    for shift in KeySide.allCases {
                        var config = Configuration()
                        config.outputMode = .shortcut
                        config.control = control
                        config.command = command
                        config.option = option
                        config.shift = shift
                        let plan = KeyboardPlan(configuration: config)
                        XCTAssertEqual(plan.up.map(\.keyCode), Array(plan.down.map(\.keyCode).reversed()))
                        XCTAssertEqual(plan.up.last?.flags, 0)
                        XCTAssertEqual(plan.down.last?.kind, .down)
                        XCTAssertEqual(plan.up.first?.kind, .up)
                        XCTAssertEqual(plan.down.last?.flags, plan.up.first?.flags)
                    }
                }
            }
        }
    }

    func testQuartzPreservesSidedModifierFlags() throws {
        var config = Configuration()
        config.outputMode = .shortcut
        config.control = .right
        config.command = .left
        config.option = .right
        config.shift = .left
        let plan = KeyboardPlan(configuration: config)
        for step in plan.down + plan.up {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: step.keyCode, keyDown: step.kind != .up))
            if step.kind == .flagsChanged { event.type = .flagsChanged }
            event.flags = CGEventFlags(rawValue: step.flags)
            let data = try XCTUnwrap(event.data)
            let restored = try XCTUnwrap(CGEvent(withDataAllocator: nil, data: data))
            XCTAssertEqual(restored.getIntegerValueField(.keyboardEventKeycode), Int64(step.keyCode))
            XCTAssertEqual(restored.flags.rawValue, step.flags)
            XCTAssertEqual(restored.type, step.kind == .flagsChanged ? .flagsChanged : (step.kind == .down ? .keyDown : .keyUp))
        }
    }

    func testDuplicateInputReportsOnlyTriggerOnce() {
        var latch = TriggerLatch()
        XCTAssertEqual(latch.receive(down: false), .none)
        XCTAssertEqual(latch.receive(down: true), .began)
        for _ in 0..<100 { XCTAssertEqual(latch.receive(down: true), .none) }
        XCTAssertEqual(latch.receive(down: false), .ended)
        XCTAssertEqual(latch.receive(down: false), .none)
        XCTAssertEqual(latch.receive(down: true), .began)
    }

    func testDisconnectResetAllowsNextPress() {
        var latch = TriggerLatch()
        _ = latch.receive(down: true)
        latch.reset()
        XCTAssertFalse(latch.isDown)
        XCTAssertEqual(latch.receive(down: true), .began)
    }

    func testRelayAcceptsLogitechGenericFlagsAndPhysicalSidedFlags() {
        XCTAssertTrue(RelayKey.hyperF12.matches(keyCode: 111, flags: 0x1C0000))
        XCTAssertTrue(RelayKey.hyperF12.matches(keyCode: 111, flags: 0x1C0029))
        XCTAssertTrue(RelayKey.hyperF12.matches(keyCode: 111, flags: 0x1C2050 | 0x800000))
        XCTAssertFalse(RelayKey.hyperF12.matches(keyCode: 111, flags: 0x1E0000))
        XCTAssertFalse(RelayKey.hyperF12.matches(keyCode: 79, flags: 0x1C0000))
        XCTAssertTrue(RelayKey.f18.matches(keyCode: 79, flags: 0x810000))
        XCTAssertFalse(RelayKey.f18.matches(keyCode: 79, flags: 0x100000))
    }

    func testSameRelayAndOutputIsRejected() {
        var config = Configuration()
        config.inputMode = .relay
        config.outputMode = .shortcut
        config.control = .off
        config.command = .off
        config.key = .f18
        XCTAssertTrue(config.conflictsWithRelay)
        config.control = .left
        XCTAssertFalse(config.conflictsWithRelay)
        config.outputMode = .fn
        XCTAssertFalse(config.conflictsWithRelay)
    }

    func testBindingSeparatesButtonsReportsAndReceiverLocations() {
        let original = HIDBinding(productID: 0xC548, locationID: 123, transport: "USB", product: "USB Receiver", usage: 4, reportID: 2)
        var other = original
        XCTAssertTrue(original.matches(other))
        other.usage = 5
        XCTAssertFalse(original.matches(other))
        other = original
        other.locationID = 456
        XCTAssertFalse(original.matches(other))
        other = original
        other.reportID = 3
        XCTAssertFalse(original.matches(other))
    }

    func testSettingsRoundTripPreservesSideAndBinding() throws {
        var config = Configuration()
        config.outputMode = .shortcut
        config.control = .right
        config.command = .left
        config.hidBinding = HIDBinding(productID: 0xC548, locationID: 123, transport: "USB", product: "USB Receiver", usage: 4, reportID: 2)
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), config)
    }

    func testRealMaster4DivertedButtonPacket() throws {
        // Observed with Options+ running and the selected button set to Do nothing.
        let down: [UInt8] = [0x11, 3, 0x0D, 0, 0, 0xC3] + Array(repeating: 0, count: 14)
        let up: [UInt8] = [0x11, 3, 0x0D, 0] + Array(repeating: 0, count: 16)
        let packet = try XCTUnwrap(HIDPPPacket(down))
        XCTAssertEqual(packet.deviceIndex, 3)
        XCTAssertEqual(packet.pressedControls(feature: 0x0D, allowed: [0xC3]), [0xC3])
        XCTAssertEqual(try XCTUnwrap(HIDPPPacket(up)).pressedControls(feature: 0x0D, allowed: [0xC3]), [])
    }

    func testHIDPPRejectsRepliesMotionWrongFeaturesAndTruncation() throws {
        let prefix: [UInt8] = [0x11, 3, 0x0D, 0, 0, 0xC3]
        let report = prefix + Array(repeating: UInt8(0), count: 14)
        for header: UInt8 in [0x0E, 0x10, 0x1E, 0x20] {
            var changed = report
            changed[3] = header
            XCTAssertTrue(try XCTUnwrap(HIDPPPacket(changed)).pressedControls(feature: 0x0D, allowed: [0xC3]) == nil)
        }
        XCTAssertTrue(try XCTUnwrap(HIDPPPacket(report)).pressedControls(feature: 0x0C, allowed: [0xC3]) == nil)
        XCTAssertTrue(HIDPPPacket(Array(report.prefix(11))) == nil)
        XCTAssertTrue(HIDPPPacket([0x12] + Array(repeating: 0, count: 63)) == nil)
    }

    func testHIDPPOnlyAcceptsEnumeratedMouseControls() throws {
        let report: [UInt8] = [0x11, 3, 0x0D, 0, 0, 0x50, 0, 0x51, 0, 0xC3, 0, 0x99] + Array(repeating: 0, count: 8)
        let packet = try XCTUnwrap(HIDPPPacket(report))
        XCTAssertEqual(packet.pressedControls(feature: 0x0D, allowed: [0x50, 0x51, 0xC3]), [0xC3])
    }

    func testHIDPPStateTracksSimultaneousButtonsAndDuplicates() {
        var state = HIDPPButtonState()
        XCTAssertEqual(state.update([0xC3]), [.init(control: 0xC3, down: true)])
        XCTAssertEqual(state.update([0xC3]), [])
        XCTAssertEqual(state.update([0xC4, 0xC3]), [.init(control: 0xC4, down: true)])
        XCTAssertEqual(state.update([0xC4]), [.init(control: 0xC3, down: false)])
        XCTAssertEqual(state.update([]), [.init(control: 0xC4, down: false)])
        XCTAssertEqual(state.update([]), [])
    }

    func testOldSettingsDecodeAndVendorBindingsStayDistinct() throws {
        let old = Data(#"{"productID":50504,"locationID":123,"transport":"USB","product":"USB Receiver","usage":4,"reportID":2}"#.utf8)
        let oldBinding = try JSONDecoder().decode(HIDBinding.self, from: old)
        XCTAssertTrue(oldBinding.controlID == nil)
        let vendor = HIDBinding(productID: 50504, locationID: 123, transport: "USB", product: "USB Receiver", usage: 0xC3, reportID: 0x11, deviceIndex: 3, controlID: 0xC3)
        XCTAssertFalse(oldBinding.matches(vendor))
        var otherSlot = vendor
        otherSlot.deviceIndex = 2
        XCTAssertFalse(vendor.matches(otherSlot))
        XCTAssertEqual(try JSONDecoder().decode(HIDBinding.self, from: JSONEncoder().encode(vendor)), vendor)
        XCTAssertEqual(HIDPPPacket.featureQuery(slot: 3, softwareID: 0x0E), [0x10, 3, 0, 0x0E, 0x1B, 0x04, 0])
    }
}

@main
enum BridgeChecks {
    static func main() throws {
        let tests = BridgeCoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("Physical left/right shortcut capture", tests.testPhysicalShortcutCaptureAndCancelBeforeCommit),
            ("Common keys and 1.2 settings compatibility", tests.testShortcutRecorderSupportsCommonKeysAndOldSavedFormat),
            ("System language resolution", tests.testSystemLanguageResolution),
            ("Translation coverage and format arguments", tests.testTranslationCoverageAndFormatArguments),
            ("Language preserves bindings and keyboard output", tests.testLanguageDoesNotChangeSavedBindingsOrKeyboardEvents),
            ("Fn press/release", tests.testFnUsesModifierEventsAndReleases),
            ("Left Control + Command + Z", tests.testLeftControlCommandZHasBothGenericAndSidedFlags),
            ("Right modifier flags", tests.testRightControlCommandZIsDistinctFromLeft),
            ("All 81 modifier combinations", tests.testEveryModifierCombinationIsBalanced),
            ("Quartz event serialization", tests.testQuartzPreservesSidedModifierFlags),
            ("Duplicate HID reports", tests.testDuplicateInputReportsOnlyTriggerOnce),
            ("Disconnect reset", tests.testDisconnectResetAllowsNextPress),
            ("Options+ relay matching", tests.testRelayAcceptsLogitechGenericFlagsAndPhysicalSidedFlags),
            ("Relay loop prevention", tests.testSameRelayAndOutputIsRejected),
            ("HID binding identity", tests.testBindingSeparatesButtonsReportsAndReceiverLocations),
            ("Settings persistence", tests.testSettingsRoundTripPreservesSideAndBinding),
            ("Actual MX Master 4 HID++ report", tests.testRealMaster4DivertedButtonPacket),
            ("HID++ rejects replies, motion, and malformed input", tests.testHIDPPRejectsRepliesMotionWrongFeaturesAndTruncation),
            ("HID++ mouse control allowlist", tests.testHIDPPOnlyAcceptsEnumeratedMouseControls),
            ("HID++ simultaneous buttons and duplicates", tests.testHIDPPStateTracksSimultaneousButtonsAndDuplicates),
            ("Old settings and receiver slot isolation", tests.testOldSettingsDecodeAndVendorBindingsStayDistinct)
        ]
        for (name, test) in cases { try test(); print("PASS \(name)") }
        print("\(cases.count) checks passed. No keyboard events were posted.")
    }
}
