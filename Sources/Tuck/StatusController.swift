import AppKit
import os

private let log = Logger(subsystem: "com.twodxme.tuck", category: "status")

/// Tuck's status items, right to left:
///
///   [ hidden icons ] [ hidden divider ⋮ ] [ tucked icons ] [ divider | ] [ arrow ‹ ] [ visible icons ]
///
/// macOS gives apps no way to hide another app's menu bar item, so Tuck
/// stretches a divider (about half the screen; see `collapsedDividerLength`)
/// and everything left of it is pushed off screen. ⌘-dragging an icon across
/// a divider moves it between sections. Same trick as Hidden Bar, Dozer, Ice.
///
/// The hidden divider exists only while the always-hidden section is on.
///
/// Resource rule: nothing polls while tucked away. Timers exist only while
/// open (auto-hide, hover watch); listeners are notification- or
/// event-driven and installed only in the state that needs them.
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
  enum Mode { case collapsed, open, all }

  private let arrow: NSStatusItem
  private let divider: NSStatusItem
  private var hiddenDivider: NSStatusItem?

  private var autoHideTimer: Timer?
  private var hoverOpenTimer: Timer?
  private var hoverWatch: Timer?
  private var scanTimer: Timer?
  private var trackingArea: NSTrackingArea?
  private var lastPointerInBar = Date()
  private var appSwitchObserver: NSObjectProtocol?
  private var dragMonitor: Any?
  private var peek: (wasCollapsed: Bool, at: Date)?

  private(set) var mode: Mode = .open
  var expanded: Bool { mode != .collapsed }

  /// Tucked icons from the last scan (only when `trackTucked` is on).
  private(set) var tucked: [TuckedScanner.Found] = []
  var onTuckedChange: ([BarItem]) -> Void = { _ in }

  var settings: TuckSettings { didSet { apply(old: oldValue) } }
  var onOpenSettings: () -> Void = {}

  private static let layoutOKKey = "layoutOK"

  init(settings: TuckSettings) {
    self.settings = settings
    // Created first, so it sits right of the divider. Autosave names keep
    // wherever the user ⌘-drags them across launches.
    arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    arrow.autosaveName = "TuckArrow"
    divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    divider.autosaveName = "TuckDivider"
    super.init()

    if let button = arrow.button {
      button.target = self
      button.action = #selector(arrowClicked(_:))
      // Toggle on press, like the system's own menu bar items. The menu
      // opens on release: opening it on press nested its tracking inside
      // the button's, which then waited forever for a mouse-up the menu had
      // already eaten, and Tuck stopped answering (tuck:// links included).
      button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
      button.imagePosition = .imageLeading
    }
    // Not disabled: macOS dims a disabled status button. With no action,
    // clicks on it simply do nothing.
    divider.button?.toolTip = "Tuck divider: ⌘-drag icons to its left to tuck them"
    divider.button?.setAccessibilityLabel("Tuck divider")

    syncHiddenDivider()
    NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
    apply(old: nil)
    startUp()
  }

  // MARK: - launch

  /// Collapse as soon as the items are laid out, so tucked icons don't
  /// flash at login. When the last session ended with a sound layout, the
  /// divider is stretched straight away and checked once laid out.
  private func startUp() {
    guard !settings.startOpen else { setMode(.open); return }
    if UserDefaults.standard.bool(forKey: Self.layoutOKKey) {
      setMode(.collapsed)
    }
    waitForLayout(tries: 50)
  }

  private func waitForLayout(tries: Int) {
    // Fresh items report x = 0 until the bar has placed them; wait for
    // real, distinct positions before judging the layout.
    let a = arrow.button?.window?.frame ?? .zero, d = divider.button?.window?.frame ?? .zero
    if mode == .collapsed {
      // Collapsed from the first frame (the last layout was sound). A
      // stretched divider reports no useful position; what matters is that
      // the arrow landed on screen rather than being pushed off by it.
      let onScreen = NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: a.midX, y: a.midY)) }
      if a.width > 0, a.minX > 0, onScreen { return }
      guard tries > 0 else {
        log.info("arrow never landed on screen: \(NSStringFromRect(a), privacy: .public)")
        UserDefaults.standard.set(false, forKey: Self.layoutOKKey)
        expand(misplaced: true)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.waitForLayout(tries: tries - 1) }
      return
    }
    if a.width > 0, d.width > 0, a.minX > 0, d.minX > 0, a.minX != d.minX {
      if layoutOK() {
        if mode != .collapsed { collapse() }
      } else {
        expand(misplaced: true)
      }
      return
    }
    guard tries > 0 else { expand(misplaced: true); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.waitForLayout(tries: tries - 1) }
  }

  private func layoutOK() -> Bool {
    let ok = canCollapse(dividerMinX: divider.button?.window?.frame.minX,
                         arrowMinX: arrow.button?.window?.frame.minX)
    UserDefaults.standard.set(ok, forKey: Self.layoutOKKey)
    if !ok {
      log.info("layout not ok: arrow=\(NSStringFromRect(self.arrow.button?.window?.frame ?? .zero), privacy: .public) divider=\(NSStringFromRect(self.divider.button?.window?.frame ?? .zero), privacy: .public)")
    }
    return ok
  }

  // MARK: - state

  func toggle() { expanded ? collapse() : expand() }

  /// ⌥-click: show the always-hidden icons too, or back to plain open.
  func toggleAll() {
    guard hiddenDivider != nil else { toggle(); return }
    mode == .all ? setMode(.open) : setMode(.all)
  }

  func expand() { expand(misplaced: false) }

  private func expand(misplaced: Bool) {
    setMode(mode == .all ? .all : .open, misplaced: misplaced)
  }

  func collapse() {
    guard layoutOK() else {
      // The divider is on the wrong side of the arrow: stretching it would
      // push the arrow off screen too. Stay open; the tooltip explains.
      expand(misplaced: true)
      log.info("collapse refused: divider not left of arrow")
      return
    }
    setMode(.collapsed)
  }

  private func setMode(_ new: Mode, misplaced: Bool = false) {
    let wasExpanded = expanded
    mode = new
    log.info("mode \(String(describing: new), privacy: .public)\(misplaced ? " (misplaced)" : "", privacy: .public)")
    // Content first, then lengths, so the bar lays out once.
    refresh(misplaced: misplaced)
    switch new {
    case .collapsed:
      if let h = hiddenDivider { h.length = NSStatusItem.variableLength }
      divider.length = stretchLength()
    case .open:
      divider.length = NSStatusItem.variableLength
      if let h = hiddenDivider {
        h.length = hiddenSectionOK() ? stretchLength() : NSStatusItem.variableLength
      }
    case .all:
      divider.length = NSStatusItem.variableLength
      hiddenDivider?.length = NSStatusItem.variableLength
    }

    if expanded {
      restartAutoHide()
      startHoverWatch()
      watchAppSwitches(true)
      watchDrags(false)
      if !wasExpanded || new == .all { scheduleScan() }
    } else {
      autoHideTimer?.invalidate(); autoHideTimer = nil
      scanTimer?.invalidate(); scanTimer = nil
      stopHoverWatch()
      watchAppSwitches(false)
      watchDrags(true)
    }
  }

  /// How far a divider stretches, for the screen the items are on.
  private func stretchLength() -> CGFloat {
    guard let screen = divider.button?.window?.screen ?? NSScreen.main else { return 900 }
    return collapsedDividerLength(screenWidth: screen.frame.width,
                                  rightOfNotch: screen.auxiliaryTopRightArea?.width,
                                  override: settings.collapsedLengthOverride)
  }

  /// A new display or resolution changes the width that works.
  @objc private func screensChanged() {
    if mode == .collapsed { divider.length = stretchLength() }
    if mode == .open, let h = hiddenDivider, hiddenSectionOK() { h.length = stretchLength() }
  }

  private func apply(old: TuckSettings?) {
    if old?.alwaysHidden != settings.alwaysHidden { syncHiddenDivider() }
    if old?.openOn != settings.openOn { installHoverTracking() }
    if old?.trackTucked != settings.trackTucked {
      if settings.trackTucked { TuckedScanner.requestTrust(); scheduleScan() } else { setTucked([]) }
    }
    if old != nil { setMode(mode) } // re-apply lengths, listeners and labels
  }

  // MARK: - always-hidden section

  private func syncHiddenDivider() {
    if settings.alwaysHidden, hiddenDivider == nil {
      // Created after the divider, so a fresh one lands just left of it.
      let h = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      h.autosaveName = "TuckHiddenDivider"
      h.button?.toolTip = "Tuck hidden divider: icons left of it stay hidden until you ⌥-click the arrow"
      h.button?.setAccessibilityLabel("Tuck always-hidden divider")
      hiddenDivider = h
    } else if !settings.alwaysHidden, let h = hiddenDivider {
      NSStatusBar.system.removeStatusItem(h)
      hiddenDivider = nil
      if mode == .all { mode = .open }
    }
  }

  /// Stretching the hidden divider only makes sense left of the divider.
  private func hiddenSectionOK() -> Bool {
    guard let h = hiddenDivider?.button?.window?.frame.minX else { return false }
    return canCollapse(dividerMinX: h, arrowMinX: divider.button?.window?.frame.minX)
  }

  // MARK: - drawing

  private func refresh(misplaced: Bool = false) {
    if let button = arrow.button {
      button.image = arrowImage(open: expanded)
      button.toolTip = misplaced
        ? "Drag Tuck's divider to the left of its arrow (hold ⌘ and drag) so it can tuck icons away."
        : (settings.showTooltip ? settings.tooltip(open: expanded) : nil)
      button.setAccessibilityLabel(expanded ? "Tuck icons away" : "Show tucked icons")
      let count = tucked.count
      if !expanded, settings.trackTucked, settings.showCount, count > 0 {
        button.attributedTitle = NSAttributedString(string: "\(count)", attributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
          .baselineOffset: 1,
        ])
        button.setAccessibilityValue("\(count) tucked")
      } else {
        button.title = ""
        button.setAccessibilityValue(nil)
      }
    }
    if let button = divider.button {
      // Collapsed it's ~950 points of nothing: a hidden button keeps the
      // width but skips drawing it.
      button.isHidden = !expanded
      button.image = expanded && settings.showDivider ? Self.dividerImage : nil
      button.title = expanded && !settings.showDivider ? " " : ""
    }
    if let button = hiddenDivider?.button {
      // Visible only in .all, where it marks the hidden section's edge.
      button.isHidden = mode != .all
      button.image = mode == .all ? Self.hiddenDividerImage : nil
    }
  }

  /// Symbol images, built once per style and state rather than every toggle.
  private var imageCache: [String: NSImage] = [:]
  private func arrowImage(open: Bool) -> NSImage? {
    let name = settings.iconStyle.symbol(open: open)
    if let cached = imageCache[name] { return cached }
    let image = NSImage(systemSymbolName: name, accessibilityDescription: open ? "Tuck icons away" : "Show tucked icons")
    image?.isTemplate = true
    imageCache[name] = image
    return image
  }

  /// A 2-point bar, 16 tall, drawn as a template so it follows the menu
  /// bar's light/dark appearance at full strength.
  static let dividerImage: NSImage = barImage(dashed: false, description: "Tuck divider")
  /// The same bar, dashed, for the always-hidden edge.
  static let hiddenDividerImage: NSImage = barImage(dashed: true, description: "Tuck always-hidden divider")

  private static func barImage(dashed: Bool, description: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
      NSColor.black.setFill()
      let x = (rect.width - 2) / 2
      if dashed {
        for y in stride(from: 0.0, to: rect.height, by: 4) {
          NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 2, height: 2.5), xRadius: 1, yRadius: 1).fill()
        }
      } else {
        NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: 2, height: rect.height), xRadius: 1, yRadius: 1).fill()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = description
    return image
  }

  // MARK: - timers

  /// A main-run-loop timer. The tolerance lets macOS fold Tuck's wakeups
  /// into ones it is doing anyway.
  private func timer(_ interval: TimeInterval, tolerance: TimeInterval, repeats: Bool = false,
                     _ body: @escaping @MainActor (StatusController) -> Void) -> Timer {
    let t = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
      MainActor.assumeIsolated { if let self { body(self) } }
    }
    t.tolerance = tolerance
    RunLoop.main.add(t, forMode: .common)
    return t
  }

  // MARK: - auto-hide

  private func restartAutoHide() {
    autoHideTimer?.invalidate(); autoHideTimer = nil
    guard expanded, settings.openOn == .click, settings.autoHide else { return }
    autoHideTimer = timer(TimeInterval(settings.autoHideSeconds), tolerance: 0.5) { $0.autoHideFired() }
  }

  private func autoHideFired() {
    // Never collapse under the pointer or out from under an open menu
    // (say, the dropdown of an icon that was just revealed).
    if pointerInMenuBar() || menuOpen() {
      autoHideTimer = timer(1, tolerance: 0.3) { $0.autoHideFired() }
      return
    }
    collapse()
  }

  /// Checked only when a timer fires or an app switches, never polled.
  private func menuOpen() -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let screen = NSScreen.screens.first else { return false }
    let windows = list.compactMap { w -> WindowSnapshot? in
      guard let layer = w[kCGWindowLayer as String] as? Int,
            let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
      return WindowSnapshot(layer: layer, bounds: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0))
    }
    let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
    return dropdownOpen(windows, barHeight: barHeight, screenWidth: screen.frame.width)
  }

  // MARK: - collapse on app switch

  private func watchAppSwitches(_ on: Bool) {
    if on, settings.collapseOnAppSwitch, appSwitchObserver == nil {
      appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] note in
        // Tuck itself coming forward (Settings, quick open) isn't a switch.
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        MainActor.assumeIsolated { self?.appSwitched() }
      }
    } else if !on || !settings.collapseOnAppSwitch, let o = appSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(o)
      appSwitchObserver = nil
    }
  }

  private func appSwitched() {
    // A click on a revealed icon can bring its app forward; that's not
    // "moving on", so leave it open while the pointer or a menu says so.
    // Checked a beat later so a menu that opens with the switch is seen.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, self.expanded, self.settings.openOn == .click,
            !self.pointerInMenuBar(), !self.menuOpen() else { return }
      self.collapse()
    }
  }

  // MARK: - ⌘-drag to open

  /// While collapsed, a ⌘-press in the menu bar (the start of rearranging
  /// icons) opens Tuck so icons can be dropped into the tucked area. A
  /// global mouse-down monitor needs no permission; it exists only while
  /// collapsed and only if the setting is on.
  private func watchDrags(_ on: Bool) {
    if on, settings.openWhileDragging, dragMonitor == nil {
      dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
        guard event.modifierFlags.contains(.command) else { return }
        MainActor.assumeIsolated {
          guard let self, !self.expanded, self.pointerInMenuBar() else { return }
          self.expand()
        }
      }
    } else if !on || !settings.openWhileDragging, let m = dragMonitor {
      NSEvent.removeMonitor(m)
      dragMonitor = nil
    }
  }

  // MARK: - shortcut: tap to toggle, hold to peek

  func hotKeyPressed() {
    peek = (wasCollapsed: !expanded, at: Date())
    toggle()
  }

  func hotKeyReleased() {
    // Held past a tap: it was a peek, so put things back.
    if let p = peek, p.wasCollapsed, Date().timeIntervalSince(p.at) > 0.35 { collapse() }
    peek = nil
  }

  // MARK: - hover mode

  private func installHoverTracking() {
    stopHoverWatch()
    if let area = trackingArea { arrow.button?.removeTrackingArea(area) }
    trackingArea = nil
    guard settings.openOn == .hover, let button = arrow.button else { return }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
    button.addTrackingArea(area)
    trackingArea = area
    if expanded { startHoverWatch() }
  }

  /// Hover mode closes once the pointer has been off the menu bar for a
  /// moment. The watch runs only while open.
  private func startHoverWatch() {
    guard settings.openOn == .hover, hoverWatch == nil else { return }
    lastPointerInBar = Date()
    hoverWatch = timer(0.15, tolerance: 0.05, repeats: true) { $0.hoverTick() }
  }

  private func stopHoverWatch() {
    hoverWatch?.invalidate()
    hoverWatch = nil
  }

  @objc func mouseEntered(with event: NSEvent) {
    guard settings.openOn == .hover, !expanded else { return }
    hoverOpenTimer?.invalidate()
    hoverOpenTimer = timer(0.15, tolerance: 0.03) { $0.expand() }
  }

  @objc func mouseExited(with event: NSEvent) {
    hoverOpenTimer?.invalidate()
  }

  private func hoverTick() {
    guard settings.openOn == .hover, expanded else { return }
    if pointerInMenuBar() || menuOpen() { lastPointerInBar = Date(); return }
    if Date().timeIntervalSince(lastPointerInBar) > 0.45 { collapse() }
  }

  private func pointerInMenuBar() -> Bool {
    let p = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
    let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
    return p.y >= screen.frame.maxY - barHeight - 2
  }

  // MARK: - tracking tucked icons (opt-in, Accessibility)

  /// Scan once the bar has settled after opening. Hidden icons only exist
  /// for Accessibility while on screen, so this never runs while collapsed.
  private func scheduleScan() {
    scanTimer?.invalidate(); scanTimer = nil
    guard settings.trackTucked, expanded, TuckedScanner.isTrusted else { return }
    scanTimer = timer(0.45, tolerance: 0.1) { $0.scan() }
  }

  private func scan(then: (() -> Void)? = nil) {
    guard settings.trackTucked, expanded, TuckedScanner.isTrusted,
          let dividerFrame = divider.button?.window?.frame else { then?(); return }
    let dividerX = dividerFrame.minX
    let hiddenX = hiddenDivider?.button?.window?.frame.minX
    let includeHidden = mode == .all
    TuckedScanner.scan { [weak self] found in
      guard let self, self.expanded else { then?(); return }
      let tuckedSet = tuckedItems(found.map(\.item), dividerMinX: dividerX,
                                  hiddenDividerMinX: includeHidden ? nil : hiddenX)
      self.setTucked(tuckedSet.compactMap { t in found.first { $0.item == t } })
      then?()
    }
  }

  private func setTucked(_ list: [TuckedScanner.Found]) {
    tucked = list
    refresh()
    onTuckedChange(list.map(\.item))
  }

  /// Open, scan, then hand over the fresh list.
  func withFreshScan(_ body: @escaping ([TuckedScanner.Found]) -> Void) {
    guard settings.trackTucked, TuckedScanner.isTrusted else { body([]); return }
    let wasExpanded = expanded
    if !wasExpanded { expand(); scanTimer?.invalidate(); scanTimer = nil }
    let delay = wasExpanded ? 0.0 : 0.45
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      self.scan { body(self.tucked) }
    }
  }

  /// Quick open: a menu of tucked icons under the arrow. Type to jump to
  /// one (menus do type-select natively), Return opens its own menu.
  func quickOpen() {
    guard settings.trackTucked else { onOpenSettings(); return }
    guard TuckedScanner.isTrusted else { TuckedScanner.requestTrust(); return }
    withFreshScan { [weak self] list in
      guard let self, let button = self.arrow.button else { return }
      let menu = NSMenu(title: "Tucked icons")
      if list.isEmpty {
        menu.addItem(withTitle: "No tucked icons", action: nil, keyEquivalent: "")
      }
      for (i, f) in list.enumerated() {
        let item = NSMenuItem(title: f.item.displayName, action: #selector(self.quickOpenChose(_:)), keyEquivalent: "")
        item.target = self
        item.tag = i
        menu.addItem(item)
      }
      NSApp.activate(ignoringOtherApps: true)
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }
  }

  @objc private func quickOpenChose(_ sender: NSMenuItem) {
    guard tucked.indices.contains(sender.tag) else { return }
    let target = tucked[sender.tag]
    // Let our menu finish closing before opening theirs.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { TuckedScanner.press(target) }
  }

  /// Moves a tucked icon right of the arrow with the same ⌘-drag a person
  /// would use, then rescans.
  func untuck(_ item: BarItem) {
    withFreshScan { [weak self] list in
      guard let self, let found = list.first(where: { $0.item.pid == item.pid && $0.item.label == item.label }),
            let arrowFrame = self.arrow.button?.window?.frame,
            let top = NSScreen.screens.first?.frame.maxY else { return }
      let from = CGPoint(x: found.item.frame.midX, y: found.item.frame.midY)
      // Accessibility and CGEvent use a top-left origin; window frames don't.
      let to = CGPoint(x: arrowFrame.maxX + 6, y: top - arrowFrame.midY)
      TuckedScanner.commandDrag(from: from, to: to) { [weak self] in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.scan() }
      }
    }
  }

  // MARK: - clicks and menu

  @objc private func arrowClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    // On macOS 27 the menu bar hands status items clicks with the modifier
    // flags stripped, so also ask the keyboard what's held right now.
    let flags = event.modifierFlags.union(NSEvent.modifierFlags)
    switch event.type {
    case .rightMouseUp:
      showMenu()
    case .leftMouseUp:
      if flags.contains(.control) { showMenu() }
    case .leftMouseDown:
      if flags.contains(.control) { return }
      flags.contains(.option) ? toggleAll() : toggle()
    default:
      break
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(withTitle: expanded ? "Tuck Away" : "Show Tucked Icons", action: #selector(menuToggle), keyEquivalent: "").target = self
    if hiddenDivider != nil {
      menu.addItem(withTitle: mode == .all ? "Hide Hidden Icons" : "Show Hidden Icons Too", action: #selector(menuToggleAll), keyEquivalent: "").target = self
    }
    if settings.trackTucked, !tucked.isEmpty {
      let open = NSMenuItem(title: "Open Tucked Icon", action: nil, keyEquivalent: "")
      let sub = NSMenu()
      for (i, f) in tucked.enumerated() {
        let item = NSMenuItem(title: f.item.displayName, action: #selector(menuOpenTucked(_:)), keyEquivalent: "")
        item.target = self
        item.tag = i
        sub.addItem(item)
      }
      open.submenu = sub
      menu.addItem(open)
    }
    menu.addItem(.separator())
    menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
    menu.addItem(withTitle: "How to Tuck Icons", action: #selector(menuHelp), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    arrow.menu = menu
    arrow.button?.performClick(nil)
  }

  // Detach the menu again so the next left-click toggles instead.
  nonisolated func menuDidClose(_ menu: NSMenu) {
    Task { @MainActor in self.arrow.menu = nil }
  }

  @objc private func menuToggle() { toggle() }
  @objc private func menuToggleAll() { toggleAll() }
  @objc private func menuSettings() { onOpenSettings() }
  @objc private func menuOpenTucked(_ sender: NSMenuItem) {
    guard tucked.indices.contains(sender.tag) else { return }
    let target = tucked[sender.tag].item
    // Re-find it once open: positions from a collapsed-era scan are stale.
    withFreshScan { list in
      guard let f = list.first(where: { $0.item.pid == target.pid && $0.item.label == target.label }) else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { TuckedScanner.press(f) }
    }
  }
  @objc private func menuHelp() {
    let alert = NSAlert()
    alert.messageText = "Tucking icons"
    var text = "Hold ⌘ and drag any menu bar icon to the left of Tuck's divider ( | ) to tuck it away. Drag it back to the right of the arrow to keep it visible.\n\nClick the arrow or press the shortcut to show or hide tucked icons. Hold the shortcut to peek."
    if hiddenDivider != nil {
      text += "\n\nIcons left of the dashed divider stay hidden even when Tuck is open. ⌥-click the arrow to show them too."
    }
    alert.informativeText = text
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
