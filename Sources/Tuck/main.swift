import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var status: StatusController!
  private var settingsWindow: SettingsWindow!
  private let hotKey = HotKey()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = TuckSettings.load(from: .standard)
    status = StatusController(settings: settings)

    let model = SettingsModel(settings: settings)
    model.onChange = { [weak self] new in
      guard let self else { return }
      let hotKeyChanged = new.hotKey != self.status.settings.hotKey
      self.status.settings = new
      if hotKeyChanged { self.registerHotKey(new.hotKey) }
    }
    settingsWindow = SettingsWindow(model: model)
    status.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
    registerHotKey(settings.hotKey)

    // Scriptable like the Omarchy version: `open "tuck://toggle"` and friends.
    NSAppleEventManager.shared().setEventHandler(
      self, andSelector: #selector(handleURL(_:withReply:)),
      forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }

  private func registerHotKey(_ preset: HotKeyPreset) {
    hotKey.register(preset) { [weak self] in self?.status.toggle() }
  }

  /// tuck://toggle, tuck://expand, tuck://collapse, tuck://settings
  @objc private func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
    guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
          let host = URL(string: s)?.host else { return }
    switch host {
    case "toggle": status.toggle()
    case "expand": status.expand()
    case "collapse": status.collapse()
    case "settings": settingsWindow.show()
    default: break
    }
  }

  // Quitting with icons pushed off screen would leave them hidden until the
  // divider is gone; it goes with the app, but expand first to be tidy.
  func applicationWillTerminate(_ notification: Notification) { status.expand() }
}

// Top-level code runs on the main thread; say so to the compiler.
MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
}
