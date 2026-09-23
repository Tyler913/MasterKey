#if DEBUG
import AppKit
import SwiftUI
import BridgeCore

/// Renders only our own views into bitmap files; no desktop capture or keyboard events.
enum PreviewRenderer {
    static func render(to path: String) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") { icon.setName("AppIcon") }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .simplifiedChinese, .traditionalChinese] {
            for scenario in ["fn", "combination", "relay", "permissions"] {
                var config = Configuration()
                config.hidBinding = HIDBinding(productID: 0xC548, locationID: 123, transport: "USB", product: "USB Receiver", usage: 0xC3, reportID: 0x11, deviceIndex: 3, controlID: 0xC3)
                if scenario == "combination" { config.outputMode = .shortcut }
                if scenario == "relay" { config.inputMode = .relay }
                let model = BridgeModel(previewLanguage: language, configuration: config, permissions: scenario != "permissions")
                let view = NSHostingView(rootView: SettingsView(model: model))
                let size = NSSize(width: 560, height: 690)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scenario == "fn" ? .aqua : .darkAqua)
                window.contentView = view
                view.frame = NSRect(origin: .zero, size: size)
                window.layoutIfNeeded()
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: directory.appendingPathComponent("\(language.rawValue)-\(scenario).png"))
                print("Rendered \(language.rawValue) \(scenario)")
            }
        }
    }
}
#endif
