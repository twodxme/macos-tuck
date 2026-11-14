import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey: no
/// Accessibility or Input Monitoring permission needed, unlike event taps.
/// Each slot reports both press and release, so a shortcut can be tapped
/// or held (hold-to-peek).
@MainActor
final class HotKeys {
  enum Slot: UInt32 { case toggle = 1, quickOpen = 2 }

  struct Handlers {
    var pressed: () -> Void
    var released: () -> Void = {}
  }

  private var refs: [Slot: EventHotKeyRef] = [:]
  fileprivate static var handlers: [UInt32: Handlers] = [:]
  private static var handlerInstalled = false

  func register(_ slot: Slot, _ preset: HotKeyPreset, _ handlers: Handlers) {
    unregister(slot)
    guard let combo = preset.combo else { return }
    HotKeys.handlers[slot.rawValue] = handlers
    HotKeys.installHandlerOnce()
    let id = EventHotKeyID(signature: OSType(0x5455_434B), id: slot.rawValue) // 'TUCK'
    var ref: EventHotKeyRef?
    if RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
      refs[slot] = ref
    }
  }

  func unregister(_ slot: Slot) {
    if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
    HotKeys.handlers[slot.rawValue] = nil
  }

  private static func installHandlerOnce() {
    guard !handlerInstalled else { return }
    handlerInstalled = true
    var specs = [
      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      guard let event else { return noErr }
      var id = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
      let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
      let slot = id.id
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let h = HotKeys.handlers[slot] else { return }
          pressed ? h.pressed() : h.released()
        }
      }
      return noErr
    }, specs.count, &specs, nil, nil)
  }
}
