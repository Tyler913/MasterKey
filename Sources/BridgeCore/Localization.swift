import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return L10n.text(.followSystem)
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for language in preferred {
            let parts = language.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-")
            if parts.first == "en" { return .english }
            if parts.first == "zh" {
                if parts.contains("hans") { return .simplifiedChinese }
                if parts.contains("hant") || !Set(parts).isDisjoint(with: ["tw", "hk", "mo"]) { return .traditionalChinese }
                return .simplifiedChinese
            }
        }
        return .english
    }
}

public enum TextKey: CaseIterable {
    case followSystem, language, preferences, mouseButton, shortcut, permissions, accessibility, inputMonitoring
    case showDockIcon, showMenuBarIcon, backgroundHint, recordShortcut, recordShortcutHint, pressShortcut, useFnMode, unsupportedShortcutKey
    case allow, allowed, enabled, paused, ready, setupNeeded, pressButton, record, replace, cancel, noButton
    case source, inputHID, inputMouse, inputRelay, relayKey, recordRelay, directHint, mouseHint, relayHint
    case combination, key, behavior, click, hold, test, testHint, countdown, relayRecordHint, relayTapOnly
    case off, left, right, logitechButton, systemButton, launchAtLogin, openSettings, reconnect, releaseKeys
    case help, diagnostics, done, copy, copied, eventsSent, noEvents, logPrivacy, sourceLabel, outputLabel, devicesLabel, systemLabel, statusLabel
    case settingsMenu, pauseMenu, enableMenu, quitMenu, menuHint, permissionHint
    case helpTitle, helpStep1, helpStep2, helpStep3, troubleshooting, helpPermissions, helpFn, helpRelay, holdHint
    case checkingPermissions, needAccessibility, needInput, needEnabled, disconnected, listenerResumed
    case learningStarted, learningTimeout, testCountdown, relayCountdown, relaySent, loginFailed, recorded
    case pressed, released, relayReceived, relayConflict, physicalModifierHeld, sentDown, sentUp, safetyRelease
    case standardConnected, standardFailed, eventFailed, eventConnected, hidppFailed, hidppConnecting, hidppQueryFailed, hidppTimeout, hidppReady
}

/// Shared by SwiftUI, the menu bar and input diagnostics. No OS language settings are changed.
public enum L10n {
    public static var language: AppLanguage = .system
    private struct Translation {
        let en: String
        let hans: String
        let hant: String
        init(_ en: String, _ hans: String, _ hant: String) { self.en = en; self.hans = hans; self.hant = hant }
    }
    private static let strings: [TextKey: Translation] = [
        .followSystem: .init("System default", "跟随系统", "跟隨系統"),
        .language: .init("Language", "语言", "語言"),
        .preferences: .init("General", "通用", "一般"),
        .mouseButton: .init("Mouse button", "鼠标按键", "滑鼠按鍵"),
        .shortcut: .init("Shortcut", "快捷键", "快捷鍵"),
        .permissions: .init("Permissions", "权限", "權限"),
        .accessibility: .init("Accessibility", "辅助功能", "輔助使用"),
        .inputMonitoring: .init("Input Monitoring", "输入监控", "輸入監控"),
        .showMenuBarIcon: .init("Show menu bar icon", "显示菜单栏图标", "顯示選單列圖示"),
        .showDockIcon: .init("Show Dock icon", "显示 Dock 图标", "顯示 Dock 圖示"),
        .backgroundHint: .init("Reopen MasterKey to access settings.", "重新打开 MasterKey 即可进入设置。", "重新開啟 MasterKey 即可進入設定。"),
        .recordShortcut: .init("Record key combination", "录入组合键", "錄製組合鍵"),
        .recordShortcutHint: .init("Click, then press a shortcut. Escape cancels.", "点击后按组合键；Esc 取消。", "點擊後按組合鍵；Esc 取消。"),
        .pressShortcut: .init("Press a shortcut…", "请按组合键…", "請按組合鍵…"),
        .useFnMode: .init("Choose Fn / 🌐 above", "请在上方选择 Fn / 🌐", "請在上方選擇 Fn / 🌐"),
        .unsupportedShortcutKey: .init("This key is unavailable. Try another.", "此按键不可用，请换一个。", "此按鍵無法使用，請更換。"),
        .allow: .init("Allow…", "允许…", "允許…"),
        .allowed: .init("Allowed", "已允许", "已允許"),
        .enabled: .init("Enabled", "已启用", "已啟用"),
        .paused: .init("Paused", "已暂停", "已暫停"),
        .ready: .init("Listening", "监听中", "監聽中"),
        .setupNeeded: .init("Setup needed", "待设置", "待設定"),
        .pressButton: .init("Press your button…", "请按一下目标键…", "請按一下目標鍵…"),
        .record: .init("Record", "录入", "錄製"),
        .replace: .init("Change", "更换", "更換"),
        .cancel: .init("Cancel", "取消", "取消"),
        .noButton: .init("No button selected", "尚未选择按键", "尚未選擇按鍵"),
        .source: .init("Source", "接收方式", "接收方式"),
        .inputHID: .init("Logitech · Direct", "罗技 · 直接读取", "羅技 · 直接讀取"),
        .inputMouse: .init("System mouse button", "系统鼠标按键", "系統滑鼠按鍵"),
        .inputRelay: .init("Options+ · Relay", "Options+ · 中转", "Options+ · 轉接"),
        .relayKey: .init("Relay key", "中转键", "轉接鍵"),
        .recordRelay: .init("Record in Options+…", "录入到 Options+…", "錄製到 Options+…"),
        .directHint: .init("Options+ action: Do nothing", "Options+ 动作：Do nothing", "Options+ 動作：Do nothing"),
        .mouseHint: .init("Applies to the same button on all mice.", "对所有鼠标的相同按键生效。", "對所有滑鼠的相同按鍵生效。"),
        .relayHint: .init("Assign this key to your button in Options+.", "在 Options+ 中为目标按钮分配此键。", "在 Options+ 中為目標按鈕指定此鍵。"),
        .combination: .init("Key combination", "组合键", "組合鍵"),
        .key: .init("Key", "按键", "按鍵"),
        .behavior: .init("Behavior", "触发方式", "觸發方式"),
        .click: .init("Click", "点击", "點擊"),
        .hold: .init("Hold to talk", "按住说话", "按住說話"),
        .test: .init("Test", "测试", "測試"),
        .testHint: .init("Send once after a 3-second delay.", "3 秒后发送一次快捷键。", "3 秒後傳送一次快捷鍵。"),
        .countdown: .init("%d s · Cancel", "%d 秒 · 取消", "%d 秒 · 取消"),
        .relayRecordHint: .init("Click, then focus the shortcut field in Options+ within 3 seconds.", "点击后，3 秒内选中 Options+ 的快捷键录入框。", "點擊後，3 秒內選取 Options+ 的快捷鍵輸入框。"),
        .relayTapOnly: .init("Options+ relay uses clicks only.", "Options+ 中转仅支持点击。", "Options+ 轉接僅支援點擊。"),
        .off: .init("Off", "不用", "不用"),
        .left: .init("Left", "左", "左"),
        .right: .init("Right", "右", "右"),
        .logitechButton: .init("Logitech button %04X", "罗技按键 %04X", "羅技按鍵 %04X"),
        .systemButton: .init("Button %d", "按钮 %d", "按鈕 %d"),
        .launchAtLogin: .init("Launch at login", "登录时启动", "登入時啟動"),
        .openSettings: .init("Open System Settings…", "打开系统设置…", "開啟系統設定…"),
        .reconnect: .init("Reconnect", "重新连接", "重新連線"),
        .releaseKeys: .init("Release keys", "松开快捷键", "放開快捷鍵"),
        .help: .init("Help", "帮助", "說明"),
        .diagnostics: .init("Diagnostics", "诊断", "診斷"),
        .done: .init("Done", "完成", "完成"),
        .copy: .init("Copy log", "复制日志", "複製記錄"),
        .copied: .init("Copied", "已复制", "已複製"),
        .eventsSent: .init("%d shortcuts sent", "已发送 %d 次", "已傳送 %d 次"),
        .noEvents: .init("No events yet.", "暂无事件。", "尚無事件。"),
        .logPrivacy: .init("Button events only. Typed text is never recorded.", "仅记录按键状态，不记录输入文字。", "僅記錄按鍵狀態，不記錄輸入文字。"),
        .sourceLabel: .init("Source", "来源", "來源"),
        .outputLabel: .init("Output", "输出", "輸出"),
        .devicesLabel: .init("Devices", "设备", "裝置"),
        .systemLabel: .init("System", "系统", "系統"),
        .statusLabel: .init("Status", "状态", "狀態"),
        .settingsMenu: .init("Settings…", "设置…", "設定…"),
        .pauseMenu: .init("Pause", "暂停", "暫停"),
        .enableMenu: .init("Enable", "启用", "啟用"),
        .quitMenu: .init("Quit MasterKey", "退出 MasterKey", "結束 MasterKey"),
        .menuHint: .init("MasterKey · Mouse shortcuts", "MasterKey · 鼠标快捷键", "MasterKey · 滑鼠快捷鍵"),
        .permissionHint: .init("Allow MasterKey to read your button and send shortcuts.", "允许 MasterKey 读取按键并发送快捷键。", "允許 MasterKey 讀取按鍵並傳送快捷鍵。"),
        .helpTitle: .init("Connect your mouse to Typeless", "连接鼠标与 Typeless", "連接滑鼠與 Typeless"),
        .helpStep1: .init("In Options+, set the button to Other actions → Do nothing. An empty Keyboard shortcut is different.", "在 Options+ 中选择 Other actions → Do nothing；不是把 Keyboard shortcut 留空。", "在 Options+ 中選擇 Other actions → Do nothing；不是將 Keyboard shortcut 留空。"),
        .helpStep2: .init("Choose Logitech · Direct, then Record and press your button.", "选择「罗技 · 直接读取」，点「录入」后按一下目标键。", "選擇「羅技 · 直接讀取」，點「錄製」後按一下目標鍵。"),
        .helpStep3: .init("Match the shortcut in Typeless. Use Click to start/stop, or Hold to talk.", "快捷键与 Typeless 保持一致。选择点击开始／结束，或按住说话。", "快捷鍵須與 Typeless 一致。選擇點擊開始／結束，或按住說話。"),
        .troubleshooting: .init("Troubleshooting", "遇到问题", "遇到問題"),
        .helpPermissions: .init("After an update, macOS may require you to remove and re-add MasterKey in privacy permissions, then relaunch it.", "更新后若权限不生效，在系统隐私设置中移除并重新添加 MasterKey，再重开应用。", "更新後若權限未生效，在系統隱私設定中移除並重新加入 MasterKey，再重新開啟。"),
        .helpFn: .init("If Fn does not trigger Typeless, choose a sided key combination and add the same shortcut in Typeless.", "Fn 无反应时，改用左右组合键，并在 Typeless 中添加相同快捷键。", "Fn 無反應時，改用左右組合鍵，並在 Typeless 中加入相同快捷鍵。"),
        .helpRelay: .init("If a button cannot be recorded, use Options+ · Relay with F18. Relay mode uses clicks only.", "无法录入时，可用 Options+ · 中转，将按钮设为 F18；中转仅支持点击。", "無法錄製時，可用 Options+ · 轉接，將按鈕設為 F18；轉接僅支援點擊。"),
        .holdHint: .init("Held shortcuts are released after 120 seconds.", "按住的快捷键会在 120 秒后自动松开。", "按住的快捷鍵會在 120 秒後自動放開。"),
        .checkingPermissions: .init("Checking permissions…", "正在检查权限…", "正在檢查權限…"),
        .needAccessibility: .init("Accessibility permission required.", "需要辅助功能权限。", "需要輔助使用權限。"),
        .needInput: .init("Input Monitoring permission required.", "需要输入监控权限。", "需要輸入監控權限。"),
        .needEnabled: .init("Enable MasterKey and allow Accessibility first.", "请先启用 MasterKey 并允许辅助功能。", "請先啟用 MasterKey 並允許輔助使用。"),
        .disconnected: .init("Device disconnected; keys released.", "设备已断开，快捷键已松开。", "裝置已中斷連線，快捷鍵已放開。"),
        .listenerResumed: .init("Listener restored. Press your button again.", "监听已恢复，请重新按键。", "監聽已恢復，請重新按鍵。"),
        .learningStarted: .init("Press your button within 15 seconds. No shortcut will be sent.", "请在 15 秒内按键；录入时不会发送快捷键。", "請在 15 秒內按鍵；錄製時不會傳送快捷鍵。"),
        .learningTimeout: .init("No button received. Check Do nothing in Options+ and the HID++ connection.", "未收到按键，请检查 Options+ 的 Do nothing 和专用通道连接。", "未收到按鍵，請檢查 Options+ 的 Do nothing 與專用通道連線。"),
        .testCountdown: .init("Test in 3 seconds. Focus Typeless or a text field.", "3 秒后测试，请切到 Typeless 或文本框。", "3 秒後測試，請切換至 Typeless 或文字框。"),
        .relayCountdown: .init("Relay key in 3 seconds. Focus the Options+ shortcut field.", "3 秒后发送中转键，请选中 Options+ 录入框。", "3 秒後傳送轉接鍵，請選取 Options+ 輸入框。"),
        .relaySent: .init("Relay sent: %@", "已发送中转键：%@", "已傳送轉接鍵：%@"),
        .loginFailed: .init("Login item failed: %@", "登录启动设置失败：%@", "登入啟動設定失敗：%@"),
        .recorded: .init("Recorded: %@", "已录入：%@", "已錄製：%@"),
        .pressed: .init("%@ · Down", "%@ · 按下", "%@ · 按下"),
        .released: .init("%@ · Up", "%@ · 松开", "%@ · 放開"),
        .relayReceived: .init("Relay received: %@", "收到中转键：%@", "收到轉接鍵：%@"),
        .relayConflict: .init("Relay and output shortcuts must differ.", "中转键和输出键不能相同。", "轉接鍵和輸出鍵不能相同。"),
        .physicalModifierHeld: .init("Skipped: release keyboard modifiers first.", "已跳过，请先松开键盘修饰键。", "已略過，請先放開鍵盤修飾鍵。"),
        .sentDown: .init("Sent: %@ · Down", "已发送：%@ · 按下", "已傳送：%@ · 按下"),
        .sentUp: .init("Shortcut released.", "快捷键已松开。", "快捷鍵已放開。"),
        .safetyRelease: .init("Released after the 120-second hold limit.", "已达到 120 秒，自动松开。", "已達到 120 秒，自動放開。"),
        .standardConnected: .init("Standard mouse channel connected.", "标准鼠标通道已连接。", "標準滑鼠通道已連線。"),
        .standardFailed: .init("Mouse channel unavailable (0x%08X).", "鼠标通道不可用（0x%08X）。", "滑鼠通道無法使用（0x%08X）。"),
        .eventFailed: .init("Cannot listen. Check permissions, then reconnect.", "无法监听，请检查权限后重新连接。", "無法監聽，請檢查權限後重新連線。"),
        .eventConnected: .init("System listener connected: %@", "系统监听已连接：%@", "系統監聽已連線：%@"),
        .hidppFailed: .init("HID++ channel unavailable (0x%08X).", "罗技专用通道不可用（0x%08X）。", "羅技專用通道無法使用（0x%08X）。"),
        .hidppConnecting: .init("HID++ connected; discovering buttons…", "专用通道已连接，正在识别按键…", "專用通道已連線，正在辨識按鍵…"),
        .hidppQueryFailed: .init("HID++ query failed (0x%08X).", "按键查询失败（0x%08X）。", "按鍵查詢失敗（0x%08X）。"),
        .hidppTimeout: .init("HID++ query timed out. Reconnect to retry.", "按键查询超时，请重新连接。", "按鍵查詢逾時，請重新連線。"),
        .hidppReady: .init("HID++ ready · Device %d · %d buttons", "专用通道就绪 · 设备 %d · %d 个按键", "專用通道就緒 · 裝置 %d · %d 個按鍵")
    ]

    public static func text(_ key: TextKey, language selected: AppLanguage? = nil) -> String {
        guard let value = strings[key] else { preconditionFailure("Missing translation: \(key)") }
        switch (selected ?? language).resolved() {
        case .simplifiedChinese: return value.hans
        case .traditionalChinese: return value.hant
        default: return value.en
        }
    }
    public static func format(_ key: TextKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}
