import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var status: StatusController!
  private var settingsWindow: SettingsWindow!
  private var model: SettingsModel!
  private var panel: MenuPanel!
  private let panelModel = PanelModel()
  private let hotKeys = HotKeys()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // One Tuck at a time: a second copy (say, a build folder next to the one
    // in /Applications) would add a second arrow and divider and fight it.
    let me = NSRunningApplication.current
    if let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != me }) {
      NSApp.terminate(nil)
      return
    }
    let settings = TuckSettings.load(from: .standard)
    status = StatusController(settings: settings)

    model = SettingsModel(settings: settings)
    model.onChange = { [weak self] new in
      guard let self else { return }
      let old = self.status.settings
      self.status.settings = new
      if new.hotKey != old.hotKey || new.quickOpenHotKey != old.quickOpenHotKey { self.registerHotKeys(new) }
    }
    model.untuck = { [weak self] item in self?.status.untuck(item) }
    model.refreshTucked = { [weak self] in self?.status.withFreshScan { _ in } }
    status.onTuckedChange = { [weak self] items in self?.model.tucked = items }
    settingsWindow = SettingsWindow(model: model)
    status.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

    panel = MenuPanel(model: panelModel, settings: model)
    panelModel.toggle = { [weak self] in self?.status.toggle() }
    panelModel.toggleAll = { [weak self] in self?.status.toggleAll() }
    panelModel.openTucked = { [weak self] item in self?.status.openTucked(item) }
    panelModel.openSettings = { [weak self] in self?.settingsWindow.show() }
    panelModel.showHelp = { [weak self] in self?.settingsWindow.show(pane: .hiding) }
    status.onToggleMenu = { [weak self] button in
      guard let self else { return }
      self.syncPanel()
      self.panel.toggle(under: button)
    }
    status.isMenuShown = { [weak self] in self?.panel.isShown ?? false }
    status.onStateChange = { [weak self] in self?.syncPanel() }
    syncPanel()
    registerHotKeys(settings)

    // Scriptable like the Omarchy version: `open "tuck://toggle"` and friends.
    NSAppleEventManager.shared().setEventHandler(
      self, andSelector: #selector(handleURL(_:withReply:)),
      forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }

  private func syncPanel() {
    panelModel.expanded = status.expanded
    panelModel.showingAll = status.mode == .all
    panelModel.hasHiddenSection = status.hasHiddenSection
    panelModel.tucked = status.tucked.map(\.item)
    panel?.refresh()
  }

  private func registerHotKeys(_ s: TuckSettings) {
    hotKeys.register(.toggle, s.hotKey, .init(
      pressed: { [weak self] in self?.status.hotKeyPressed() },
      released: { [weak self] in self?.status.hotKeyReleased() }))
    hotKeys.register(.quickOpen, s.effectiveQuickOpenHotKey, .init(
      pressed: { [weak self] in self?.status.quickOpen() }))
  }

  /// tuck://toggle, expand, collapse, all, quickopen, settings, menu
  @objc private func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
    guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
          let host = URL(string: s)?.host else { return }
    switch host {
    case "toggle": status.toggle()
    case "expand": status.expand()
    case "collapse": status.collapse()
    case "all": status.toggleAll()
    case "quickopen": status.quickOpen()
    case "settings": settingsWindow.show()
    case "menu": status.showMenuFromURL()
    default: break
    }
  }

  // Quitting with icons pushed off screen would leave them hidden until the
  // divider is gone; it goes with the app, but expand first to be tidy.
  func applicationWillTerminate(_ notification: Notification) { status?.expand() }
}

// Top-level code runs on the main thread; say so to the compiler.
MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
}
