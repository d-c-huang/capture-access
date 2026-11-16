import AppKit
import Carbon

/// Run with `bash macos/Tests/run-settings-checks.sh`. This uses an isolated
/// preferences suite and releases all temporary hotkeys before returning.
@main
struct SettingsChecks {
    @MainActor static func main() throws {
        let suite = "CaptureAccess.SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        precondition(preferences.targetApplicationURL == nil)
        precondition(preferences.keepsHistory && !preferences.hasCompletedSetup)
        precondition(preferences.automaticallyChecksForUpdates && preferences.lastUpdateAttempt == nil)
        precondition(preferences.specialShortcut == .specialDefault)
        precondition(preferences.ordinaryShortcut == .ordinaryDefault)
        precondition(preferences.specialShortcut.keyEquivalent == "s")
        precondition(preferences.specialShortcut.eventModifiers == [.control, .option])
        precondition(!CaptureShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: 0).isValid)
        precondition(!CaptureShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey)).isValid)
        precondition(!CaptureShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | optionKey)).isValid)

        preferences.targetApplicationPath = "/Applications/Example.app"
        preferences.keepsHistory = false
        preferences.hasCompletedSetup = true
        preferences.automaticallyChecksForUpdates = false
        preferences.lastUpdateAttempt = Date(timeIntervalSince1970: 123456)
        preferences.specialShortcut = CaptureShortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey))
        preferences.ordinaryShortcut = CaptureShortcut(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(controlKey | shiftKey))
        let restored = AppPreferences(defaults: defaults)
        precondition(restored.targetApplicationURL?.path == "/Applications/Example.app")
        precondition(!restored.keepsHistory && restored.hasCompletedSetup)
        precondition(!restored.automaticallyChecksForUpdates)
        precondition(restored.lastUpdateAttempt == preferences.lastUpdateAttempt)
        precondition(restored.specialShortcut == preferences.specialShortcut)
        precondition(restored.ordinaryShortcut == preferences.ordinaryShortcut)

        defaults.set(Data("invalid".utf8), forKey: "specialShortcut")
        precondition(AppPreferences(defaults: defaults).specialShortcut == .specialDefault)
        defaults.set(try JSONEncoder().encode(CaptureShortcut.ordinaryDefault), forKey: "specialShortcut")
        defaults.set(try JSONEncoder().encode(CaptureShortcut.ordinaryDefault), forKey: "ordinaryShortcut")
        let repaired = AppPreferences(defaults: defaults)
        precondition(repaired.specialShortcut == .specialDefault && repaired.ordinaryShortcut == .ordinaryDefault)
        print("PASS: preferences persistence, modifier validation, local menu conflicts, corrupt and duplicate recovery")

        let first = GlobalCaptureShortcut(), second = GlobalCaptureShortcut(), probe = GlobalCaptureShortcut()
        defer { first.unregister(); second.unregister(); probe.unregister() }
        let candidates = CaptureShortcut.keys.map {
            CaptureShortcut(keyCode: $0.code, modifiers: UInt32(controlKey | optionKey | cmdKey))
        }
        guard let firstKey = candidates.first(where: { first.register($0, action: {}) }),
              let secondKey = candidates.first(where: { $0 != firstKey && second.register($0, action: {}) }) else {
            fatalError("Two available global key combinations are required for the registration check.")
        }
        precondition(!first.register(secondKey, action: {}))
        precondition(!probe.register(firstKey, action: {}), "Failed change must retain its old binding")
        first.unregister()
        precondition(probe.register(firstKey, action: {}), "Unregister must release the key")
        print("PASS: independent hotkeys, failed-change preservation, unregister")
    }
}
