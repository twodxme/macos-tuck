import AppKit
import os

private let log = Logger(subsystem: "com.twodxme.tuck", category: "status")

/// Two status items do the work:
///
///   [ tucked icons … ] [ divider | ] [ arrow ‹ ] [ always-visible icons … ]
///
/// macOS lays status items out right to left and gives apps no way to hide
/// another app's item, so Tuck stretches its divider to 10,000 points while
/// collapsed. Everything left of it is pushed off screen; ⌘-dragging an icon
/// across the divider tucks or untucks it. The same trick as Hidden Bar,
/// Dozer and Ice.
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
  private let arrow: NSStatusItem
  private let divider: NSStatusItem
  private let collapsedLength: CGFloat = 10_000
  private var autoHideTimer: Timer?
  private var hoverOpenTimer: Timer?
  private var hoverWatch: Timer?
  private var trackingArea: NSTrackingArea?
  private var lastPointerInBar = Date()

  private(set) var expanded = true
  var settings: TuckSettings { didSet { apply(old: oldValue) } }
  var onOpenSettings: () -> Void = {}

  init(settings: TuckSettings) {
    self.settings = settings
    // Created first, so it sits to the right of the divider. The autosave
    // names keep wherever the user ⌘-drags them across launches.
    arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    arrow.autosaveName = "TuckArrow"
    divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    divider.autosaveName = "TuckDivider"
    super.init()

    if let button = arrow.button {
      button.target = self
      button.action = #selector(arrowClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    // Not disabled: macOS dims a disabled status button, which made the line
    // nearly invisible. With no action, clicks on it simply do nothing.
    divider.button?.toolTip = "Tuck divider: ⌘-drag icons to its left to tuck them"
    apply(old: nil)
    // Start open for a moment so both items get laid out and measured, then
    // collapse unless the user wants it open.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      guard let self else { return }
      if !self.settings.startOpen { self.collapse() }
    }
  }

  // MARK: - state

  func toggle() { expanded ? collapse() : expand() }

  func expand() {
    expanded = true
    divider.length = NSStatusItem.variableLength
    refresh()
    restartAutoHide()
    logState("expand")
  }

  /// Where the two items sit, for `log stream --predicate 'subsystem == "com.twodxme.tuck"'`.
  func logState(_ what: String) {
    let d = divider.button?.window?.frame ?? .zero, a = arrow.button?.window?.frame ?? .zero
    log.info("\(what, privacy: .public) expanded=\(self.expanded) divider=\(NSStringFromRect(d), privacy: .public) arrow=\(NSStringFromRect(a), privacy: .public) dividerLength=\(self.divider.length)")
  }

  func collapse() {
    guard canCollapse(dividerMinX: divider.button?.window?.frame.minX,
                      arrowMinX: arrow.button?.window?.frame.minX) else {
      // The divider is on the wrong side of the arrow (or not laid out yet).
      // Stay open rather than hide the arrow; the tooltip explains.
      expanded = true
      refresh(misplaced: true)
      logState("collapse refused: divider not left of arrow")
      return
    }
    expanded = false
    autoHideTimer?.invalidate()
    divider.length = collapsedLength
    refresh()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.logState("collapse") }
  }

  private func apply(old: TuckSettings?) {
    refresh()
    if old?.openOn != settings.openOn { installHoverTracking() }
    if expanded { restartAutoHide() }
  }

  private func refresh(misplaced: Bool = false) {
    if let button = arrow.button {
      let name = settings.iconStyle.symbol(open: expanded)
      let image = NSImage(systemSymbolName: name, accessibilityDescription: expanded ? "Tuck icons away" : "Show tucked icons")
      image?.isTemplate = true
      button.image = image
      button.toolTip = misplaced
        ? "Drag Tuck's divider to the left of its arrow (hold ⌘ and drag) so it can tuck icons away."
        : (settings.showTooltip ? settings.tooltip(open: expanded) : nil)
    }
    if let button = divider.button {
      // While collapsed the divider is 10,000 points of nothing; while open
      // it marks the boundary, unless the user prefers no marker.
      if expanded && settings.showDivider {
        button.image = StatusController.dividerImage
        button.title = ""
      } else {
        button.image = nil
        button.title = expanded ? " " : ""
      }
    }
  }

  /// A 2-point bar, 16 tall, drawn as a template so it follows the menu
  /// bar's light/dark appearance at full strength.
  static let dividerImage: NSImage = {
    let size = NSSize(width: 8, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: NSRect(x: (rect.width - 2) / 2, y: 0, width: 2, height: rect.height), xRadius: 1, yRadius: 1).fill()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Tuck divider"
    return image
  }()

  // MARK: - auto-hide

  private func restartAutoHide() {
    autoHideTimer?.invalidate()
    guard expanded, settings.openOn == .click, settings.autoHide else { return }
    let interval = TimeInterval(settings.autoHideSeconds)
    autoHideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.autoHideFired() }
    }
  }

  private func autoHideFired() {
    // Never collapse under the pointer: wait for it to leave the menu bar.
    if pointerInMenuBar() {
      autoHideTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.autoHideFired() }
      }
      return
    }
    collapse()
  }

  // MARK: - hover mode

  private func installHoverTracking() {
    hoverWatch?.invalidate()
    if let area = trackingArea { arrow.button?.removeTrackingArea(area) }
    trackingArea = nil
    guard settings.openOn == .hover, let button = arrow.button else { return }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
    button.addTrackingArea(area)
    trackingArea = area
    // Close once the pointer has been off the menu bar for a moment, so
    // moving from the arrow onto a revealed icon keeps it open.
    hoverWatch = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.hoverTick() }
    }
  }

  @objc func mouseEntered(with event: NSEvent) {
    guard settings.openOn == .hover, !expanded else { return }
    hoverOpenTimer?.invalidate()
    hoverOpenTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.expand() }
    }
  }

  @objc func mouseExited(with event: NSEvent) {
    hoverOpenTimer?.invalidate()
  }

  private func hoverTick() {
    guard settings.openOn == .hover, expanded else { return }
    if pointerInMenuBar() { lastPointerInBar = Date(); return }
    if Date().timeIntervalSince(lastPointerInBar) > 0.45 { collapse() }
  }

  private func pointerInMenuBar() -> Bool {
    let p = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
    let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
    return p.y >= screen.frame.maxY - barHeight - 2
  }

  // MARK: - clicks and menu

  @objc private func arrowClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    if isSecondary { showMenu() } else { toggle() }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(withTitle: expanded ? "Tuck Away" : "Show Tucked Icons", action: #selector(menuToggle), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
    menu.addItem(withTitle: "How to Tuck Icons", action: #selector(menuHelp), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    arrow.menu = menu
    arrow.button?.performClick(nil)
  }

  // Detach the menu again so the next left-click toggles instead of opening it.
  nonisolated func menuDidClose(_ menu: NSMenu) {
    Task { @MainActor in self.arrow.menu = nil }
  }

  @objc private func menuToggle() { toggle() }
  @objc private func menuSettings() { onOpenSettings() }
  @objc private func menuHelp() {
    let alert = NSAlert()
    alert.messageText = "Tucking icons"
    alert.informativeText = "Hold ⌘ and drag any menu bar icon to the left of Tuck's divider ( | ) to tuck it away. Drag it back to the right of the arrow to keep it visible.\n\nClick the arrow to show or hide tucked icons."
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
