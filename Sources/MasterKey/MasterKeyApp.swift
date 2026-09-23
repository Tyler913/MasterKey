import AppKit
import SwiftUI
import Combine
import BridgeCore
import Carbon

@main
enum MasterKeyMain {
    static func main() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            do { try PreviewRenderer.render(to: CommandLine.arguments[index + 1]) }
            catch { fputs("Preview failed: \(error)\n", stderr); exit(1) }
            return
        }
        #endif
        if CommandLine.arguments.contains("--probe-hidpp") {
            setbuf(stdout, nil)
            let monitor = HIDPPMonitor()
            monitor.onStatus = { print($0) }
            monitor.onButton = { binding, down in print(L10n.format(down ? .pressed : .released, binding.title)) }
            monitor.start()
            CFRunLoopRunInMode(.defaultMode, 15, false)
            monitor.stop()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: BridgeModel!
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var subscription: AnyCancellable?
    private var presentationSubscription: AnyCancellable?
    private var visibilityObservation: NSKeyValueObservation?
    private var terminationSignal: DispatchSourceSignal?
    private var appIcon: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        model = BridgeModel()
        appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
        if let appIcon { NSApp.applicationIconImage = appIcon }
        model.presentationProvider = { [weak self] in self?.presentationDescription ?? "" }
        signal(SIGTERM, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource.setEventHandler { NSApp.terminate(nil) }
        signalSource.resume()
        terminationSignal = signalSource
        updatePresentation()
        subscription = model.$configuration.combineLatest(model.$language).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        presentationSubscription = model.$showDockIcon.combineLatest(model.$showMenuBarIcon).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.updatePresentation() }
        }
        // A normal launch opens settings even when both icons are hidden. Login
        // launches stay in the background, including after an application update.
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
        if !loginLaunch { showSettings() }
    }

    private func updatePresentation() {
        guard model != nil else { return }
        let policy: NSApplication.ActivationPolicy = model.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        if model.showMenuBarIcon {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem = item
                item.autosaveName = "MasterKey.MenuBar"
                item.behavior = [.removalAllowed]
                if let icon = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MasterKey") {
                    icon.size = NSSize(width: 14, height: 18)
                    icon.isTemplate = true
                    item.button?.image = icon
                } else { item.button?.title = "MK" }
                item.button?.title = "MK"
                item.button?.imagePosition = .imageLeading
                item.button?.setAccessibilityLabel("MasterKey")
                // macOS persists status-item visibility, even when using an automatic
                // autosave name. Creating the item alone does not make it visible again.
                item.isVisible = true
                visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] item, change in
                    guard change.newValue == false else { return }
                    DispatchQueue.main.async {
                        guard let self, self.statusItem === item, !item.isVisible else { return }
                        self.model.showMenuBarIcon = false
                    }
                }
            }
            statusItem?.isVisible = true
        } else {
            visibilityObservation?.invalidate()
            visibilityObservation = nil
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
        }
        rebuildMenu()
        // The Dock can recreate its tile after a policy transition. Reapply the
        // bundled artwork once that transition has reached the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, let icon = self.appIcon else { return }
            NSApp.applicationIconImage = icon
            if self.model.showDockIcon {
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: NSApp.dockTile.size))
                imageView.image = icon
                imageView.imageScaling = .scaleProportionallyUpOrDown
                NSApp.dockTile.contentView = imageView
                NSApp.dockTile.display()
            }
        }
        model.presentationStatus = presentationDescription
    }

    private var presentationDescription: String {
        let barWindow = statusItem?.button?.window
        let frame = barWindow.map { NSStringFromRect($0.frame) } ?? "none"
        let screen = barWindow?.screen.map { NSStringFromRect($0.frame) } ?? "none"
        return "Dock: \(NSApp.activationPolicy() == .regular) · Menu item: \(statusItem?.isVisible == true)\nMenu window: \(barWindow?.isVisible == true) · Frame: \(frame) · Screen: \(screen)\nIcon loaded: \(appIcon != nil)"
    }

    private func rebuildMenu() {
        guard model != nil else { return }
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        applicationItem.submenu = makeActionsMenu()
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
        statusItem?.button?.toolTip = L10n.text(.menuHint)
        statusItem?.button?.appearsDisabled = !model.configuration.enabled
        statusItem?.menu = makeActionsMenu()
    }

    private func makeActionsMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: "MasterKey", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(withTitle: L10n.text(.settingsMenu), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L10n.text(model.configuration.enabled ? .pauseMenu : .enableMenu), action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.text(.releaseKeys), action: #selector(releaseKeys), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text(.quitMenu), action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    @objc func showSettings() {
        guard model != nil else { return }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MasterKey"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 540, height: 620)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    @objc private func toggle() { model.configuration.enabled.toggle() }
    @objc private func releaseKeys() { model.releaseAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}
