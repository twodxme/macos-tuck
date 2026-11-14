import Carbon.HIToolbox

/// A system-wide shortcut through Carbon's RegisterEventHotKey: no
/// Accessibility or Input Monitoring permission needed, unlike event taps.
@MainActor
final class HotKey {
  private var ref: EventHotKeyRef?
  private static var handlerInstalled = false
  fileprivate static var action: (() -> Void)?

  func register(_ preset: HotKeyPreset, action: @escaping () -> Void) {
    unregister()
    guard let combo = preset.combo else { return }
    HotKey.action = action
    HotKey.installHandlerOnce()
    let id = EventHotKeyID(signature: OSType(0x5455_434B), id: 1) // 'TUCK'
    RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
  }

  func unregister() {
    if let ref { UnregisterEventHotKey(ref) }
    ref = nil
  }

  private static func installHandlerOnce() {
    guard !handlerInstalled else { return }
    handlerInstalled = true
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
      DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.action?() } }
      return noErr
    }, 1, &spec, nil, nil)
  }
}
