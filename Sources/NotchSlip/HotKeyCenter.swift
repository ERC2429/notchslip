import AppKit
import Carbon.HIToolbox

/// Global ⌥Space hotkey via Carbon. No Accessibility permission required.
final class HotKeyCenter {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F5445), id: 1) // 'NOTE'
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            print("[NotchSlip] global hotkey unavailable (status \(status))")
        }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.onTrigger?()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}