import Carbon.HIToolbox
import os

/// Registers a system-wide hotkey (Control-Option-Command-F) via Carbon.
/// Must stay alive for as long as the hotkey should work.
@MainActor
final class GlobalHotKey {
    private static let logger = Logger(
        subsystem: "com.github.sv-tmueller.cropcast", category: "hotkey")

    private let onPressed: @MainActor () -> Void
    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(onPressed: @escaping @MainActor () -> Void) {
        self.onPressed = onPressed
        register()
    }

    private func register() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.onPressed() }
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef)
        guard installStatus == noErr else {
            Self.logger.error("InstallEventHandler failed: \(installStatus)")
            return
        }

        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: 0x4352_4350, id: 1),
            GetApplicationEventTarget(), 0, &hotKeyRef)
        if registerStatus != noErr {
            Self.logger.error("RegisterEventHotKey failed: \(registerStatus)")
        }
    }
}
