import Carbon.HIToolbox
import Foundation

/// A permission-free escape hatch that restores the native cursor even when
/// another application's UI is not reachable.
final class EmergencyHotKey {
    struct RegistrationError: LocalizedError {
        enum Operation: String {
            case installEventHandler = "install the event handler"
            case registerHotKey = "register the hotkey"
        }

        let operation: Operation
        let status: OSStatus

        var errorDescription: String? {
            "Could not \(operation.rawValue) (OSStatus \(status))."
        }
    }

    private static let signature: OSType = 0x4E_58_43_52 // "NXCR"
    private static let identifier: UInt32 = 1

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) throws {
        self.action = action
        try register()
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }

    private func register() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == EmergencyHotKey.signature,
                  hotKeyID.id == EmergencyHotKey.identifier else {
                return OSStatus(eventNotHandledErr)
            }

            let instance = Unmanaged<EmergencyHotKey>
                .fromOpaque(userData)
                .takeUnretainedValue()
            instance.action()
            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            throw RegistrationError(
                operation: .installEventHandler,
                status: handlerStatus
            )
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard hotKeyStatus == noErr else {
            if let hotKeyReference {
                UnregisterEventHotKey(hotKeyReference)
                self.hotKeyReference = nil
            }
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            throw RegistrationError(
                operation: .registerHotKey,
                status: hotKeyStatus
            )
        }
    }
}
