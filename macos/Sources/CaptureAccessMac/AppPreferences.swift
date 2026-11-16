import AppKit
import Carbon
import Combine

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let specialDefault = CaptureShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey))
    static let ordinaryDefault = CaptureShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey))

    struct Key: Identifiable {
        let code: UInt32
        let label: String
        var id: UInt32 { code }
    }

    static let keys: [Key] = [
        (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
        (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
        (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
        (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
        (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
        (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
        (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
        (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
        (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
        (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9")
    ].map { Key(code: UInt32($0.0), label: $0.1) }

    static let modifierChoices: [(value: UInt32, label: String)] = [
        (UInt32(controlKey | optionKey), "⌃ Control + ⌥ Option"),
        (UInt32(controlKey | shiftKey), "⌃ Control + ⇧ Shift"),
        (UInt32(cmdKey | optionKey), "⌘ Command + ⌥ Option"),
        (UInt32(cmdKey | shiftKey), "⌘ Command + ⇧ Shift"),
        (UInt32(controlKey | cmdKey), "⌃ Control + ⌘ Command"),
        (UInt32(optionKey | shiftKey), "⌥ Option + ⇧ Shift"),
        (UInt32(controlKey | optionKey | shiftKey), "⌃ Control + ⌥ Option + ⇧ Shift"),
        (UInt32(cmdKey | optionKey | shiftKey), "⌘ Command + ⌥ Option + ⇧ Shift"),
        (UInt32(controlKey | optionKey | cmdKey), "⌃ Control + ⌥ Option + ⌘ Command")
    ]

    var isValid: Bool {
        Self.keys.contains { $0.code == keyCode }
            && Self.modifierChoices.contains { $0.value == modifiers }
            && conflictingApplicationCommand == nil
    }

    var conflictingApplicationCommand: String? {
        if modifiers == UInt32(cmdKey | shiftKey) {
            switch Int(keyCode) {
            case kVK_ANSI_1: return "选择窗口并截图"
            case kVK_ANSI_2: return "再次截图"
            case kVK_ANSI_C: return "复制图片"
            case kVK_ANSI_Z: return "重做"
            default: break
            }
        }
        if modifiers == UInt32(cmdKey | optionKey), keyCode == UInt32(kVK_ANSI_H) {
            return "隐藏其他应用"
        }
        return nil
    }

    var displayName: String {
        let label = Self.keys.first { $0.code == keyCode }?.label ?? "?"
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined() + label
    }

    var keyEquivalent: String {
        Self.keys.first { $0.code == keyCode }?.label.lowercased() ?? ""
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var targetApplicationPath: String {
        didSet { defaults.set(targetApplicationPath, forKey: "targetApplicationPath") }
    }
    @Published var keepsHistory: Bool {
        didSet { defaults.set(keepsHistory, forKey: "keepsHistory") }
    }
    @Published var specialShortcut: CaptureShortcut {
        didSet { persist(specialShortcut, forKey: "specialShortcut") }
    }
    @Published var ordinaryShortcut: CaptureShortcut {
        didSet { persist(ordinaryShortcut, forKey: "ordinaryShortcut") }
    }
    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { defaults.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates") }
    }
    var lastUpdateAttempt: Date? {
        get { defaults.object(forKey: "lastUpdateAttempt") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateAttempt") }
    }
    @Published var shortcutRegistrationError: String?
    // The app delegate applies a complete pair synchronously so the settings
    // window can keep a failed change visible instead of closing before feedback.
    var applyShortcutChanges: (() -> Void)?

    var targetApplicationURL: URL? {
        targetApplicationPath.isEmpty ? nil : URL(fileURLWithPath: targetApplicationPath, isDirectory: true)
    }

    var targetApplicationName: String {
        guard let url = targetApplicationURL else { return "未选择应用" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        targetApplicationPath = defaults.string(forKey: "targetApplicationPath") ?? ""
        keepsHistory = defaults.object(forKey: "keepsHistory") as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        automaticallyChecksForUpdates = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
        let special = Self.loadShortcut("specialShortcut", from: defaults) ?? .specialDefault
        let ordinary = Self.loadShortcut("ordinaryShortcut", from: defaults) ?? .ordinaryDefault
        if special == ordinary {
            specialShortcut = .specialDefault
            ordinaryShortcut = .ordinaryDefault
        } else {
            specialShortcut = special
            ordinaryShortcut = ordinary
        }
    }

    private static func loadShortcut(_ key: String, from defaults: UserDefaults) -> CaptureShortcut? {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(CaptureShortcut.self, from: data), shortcut.isValid else { return nil }
        return shortcut
    }

    private func persist(_ shortcut: CaptureShortcut, forKey key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }
}
