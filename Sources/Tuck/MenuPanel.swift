import AppKit

/// What the panel shows. The app delegate keeps it current and calls
/// `MenuPanel.refresh()` when it changes while the panel is up.
@MainActor
final class PanelModel {
  var expanded = false
  var showingAll = false
  var hasHiddenSection = false
  var tucked: [BarItem] = []

  var toggle: () -> Void = {}
  var toggleAll: () -> Void = {}
  var openTucked: (BarItem) -> Void = { _ in }
  var openSettings: () -> Void = {}
  var showHelp: () -> Void = {}
}

/// Tuck's menu: a panel of cards that slides down out of the menu bar under
/// the arrow, like a drawer.
///
/// Plain AppKit on purpose: it opens far more often than Settings, and
/// SwiftUI's one-time setup alone would add ~10 MB to Tuck's footprint.
///
/// The window never moves. The card slides inside it and the window's top
/// edge clips it, so it appears to come out from under the bar.
@MainActor
final class MenuPanel {
  private let model: PanelModel
  private let settings: SettingsModel
  private var window: DrawerWindow?
  private var slider: ShadowView?
  private var monitors: [Any] = []
  /// The arrow's window: its clicks are left to the arrow, which toggles.
  private weak var anchorWindow: NSWindow?

  static let width: CGFloat = 280
  /// Room for the shadow on the sides and bottom, and a hairline gap on top.
  static let margin: CGFloat = 18, gap: CGFloat = 3
  static let openDuration = 0.3, closeDuration = 0.16

  init(model: PanelModel, settings: SettingsModel) {
    self.model = model
    self.settings = settings
  }

  var isShown: Bool { window != nil }

  func toggle(under button: NSStatusBarButton) { isShown ? close() : show(under: button) }

  func show(under button: NSStatusBarButton) {
    guard window == nil, let anchor = button.window else { return }
    anchorWindow = anchor

    let w = DrawerWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false // the card draws its own, so it slides with it
    w.level = .popUpMenu
    w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    w.isReleasedWhenClosed = false
    w.onCancel = { [weak self] in self?.close() }
    w.setAccessibilityLabel("Tuck")
    let clip = NSView()
    clip.wantsLayer = true
    clip.layer?.masksToBounds = true
    w.contentView = clip
    window = w

    let slider = ShadowView()
    clip.addSubview(slider)
    self.slider = slider
    layOut(anchor: anchor)

    // Start above the window's top edge, then slide down into place.
    let home = slider.frame
    let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if !still { slider.frame.origin.y = clip.bounds.height + 8 }
    slider.alphaValue = still ? 0 : 0.4
    w.makeKeyAndOrderFront(nil)
    w.makeFirstResponder(nil) // no focus ring until someone presses Tab
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = still ? 0.12 : Self.openDuration
      // Quick out, long settle: the feel of a light spring without overshoot.
      ctx.timingFunction = still ? CAMediaTimingFunction(name: .easeOut) : CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
      slider.animator().frame = home
      slider.animator().alphaValue = 1
    }
    installMonitors()
  }

  func close() {
    guard let w = window, let slider else { return }
    window = nil
    self.slider = nil
    removeMonitors()
    let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let top = w.contentView?.bounds.height ?? 0
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = Self.closeDuration
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      if !still { slider.animator().frame.origin.y = top + 8 }
      slider.animator().alphaValue = still ? 0 : 0.4
    }, completionHandler: { w.orderOut(nil) })
  }

  /// Rebuilds the cards in place, for state that changed while open.
  func refresh() {
    guard let anchor = anchorWindow, window != nil else { return }
    // After the current event: a switch may be mid-action.
    DispatchQueue.main.async { [weak self] in self?.layOut(anchor: anchor) }
  }

  /// Builds the card and sizes the window: centered under the arrow, top
  /// edge against the menu bar, kept on screen.
  private func layOut(anchor: NSWindow) {
    guard let w = window, let slider, let screen = anchor.screen ?? NSScreen.main else { return }
    let card = PanelCard(content: content())
    let size = card.fittingSize
    let m = Self.margin
    let outer = NSSize(width: size.width + 2 * m, height: size.height + m + Self.gap)
    var x = anchor.frame.midX - outer.width / 2
    x = min(max(x, screen.frame.minX + 6 - m), screen.frame.maxX - 6 - outer.width + m)
    w.setFrame(NSRect(x: x, y: anchor.frame.minY - outer.height, width: outer.width, height: outer.height), display: false)
    slider.frame = NSRect(x: m, y: m, width: size.width, height: size.height)
    slider.subviews.forEach { $0.removeFromSuperview() }
    card.frame = slider.bounds
    card.autoresizingMask = [.width, .height]
    slider.addSubview(card)
  }

  /// Any click outside the panel closes it, as a menu would.
  private func installMonitors() {
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    // On macOS 27 a click on the arrow reaches MenuBarAgent first, so it
    // shows up here as a click in another app; leave those to the arrow.
    if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if let a = self.anchorWindow?.frame, a.contains(NSEvent.mouseLocation) { return }
        self.close()
      }
    }) { monitors.append(g) }
    if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
      let target = event.window.map(ObjectIdentifier.init)
      MainActor.assumeIsolated {
        guard let self, let w = self.window else { return }
        let mine = [w, self.anchorWindow].compactMap { $0 }.map(ObjectIdentifier.init)
        if let target, mine.contains(target) { return }
        self.close()
      }
      return event
    }) { monitors.append(l) }
  }

  private func removeMonitors() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
  }

  // MARK: - content

  private func content() -> [NSView] {
    var cards = [header()]
    if settings.s.trackTucked { cards.append(tuckedCard()) }
    cards.append(optionsCard())
    cards.append(footer())
    return cards
  }

  private var statusText: String {
    if model.showingAll { return "All shown" }
    if model.expanded { return "Showing" }
    let n = model.tucked.count
    return settings.s.trackTucked && n > 0 ? "\(n) tucked" : "Tucked"
  }

  private func header() -> NSView {
    let s = settings.s
    var rows: [NSView] = [sectionTitle("Tuck", value: statusText)]
    let hotKey = s.hotKey == .none ? nil : label(s.hotKey.label, size: 11, weight: .medium, color: .secondaryLabelColor)
    rows.append(HoverButton(
      style: .primary, height: 30, inset: 10,
      views: [symbol(s.iconStyle.symbol(open: model.expanded), size: 11, weight: .bold, width: 14),
              label(model.expanded ? "Tuck Away" : "Show Tucked Icons", size: 13, weight: .medium)],
      trailing: hotKey,
      help: model.expanded ? "Tuck the icons left of the divider away" : "Show the icons tucked left of the divider"
    ) { [weak self] in self?.model.toggle(); self?.close() })
    if model.hasHiddenSection {
      rows.append(HoverButton(
        style: .plain, height: 24, inset: 10,
        views: [symbol(model.showingAll ? "eye.slash" : "eye", size: 12, weight: .regular, width: 16),
                label(model.showingAll ? "Hide Always-Hidden Icons" : "Show Always-Hidden Icons Too", size: 12)],
        help: "Same as ⌥-clicking the arrow"
      ) { [weak self] in self?.model.toggleAll(); self?.close() })
    }
    return CardView(rows: rows)
  }

  private func tuckedCard() -> NSView {
    var rows: [NSView] = [sectionTitle("Tucked", value: model.tucked.isEmpty ? nil : "\(model.tucked.count)")]
    if !TuckedScanner.isTrusted {
      rows.append(HoverButton(
        style: .plain, height: 24, inset: 6,
        views: [symbol("lock", size: 12, weight: .regular, width: 16), label("Allow Accessibility to list icons", size: 12)]
      ) { [weak self] in TuckedScanner.requestTrust(); self?.close() })
    } else if model.tucked.isEmpty {
      let note = label("No tucked icons yet. Open Tuck once to list them.", size: 11, color: .secondaryLabelColor)
      note.lineBreakMode = .byWordWrapping
      note.maximumNumberOfLines = 2
      rows.append(note)
    } else {
      for item in model.tucked.prefix(10) {
        let icon = NSImageView(image: item.icon ?? symbolImage("menubar.rectangle", size: 11, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        pin(icon, width: 16, height: 16)
        let name = label(item.displayName, size: 12)
        name.lineBreakMode = .byTruncatingTail
        rows.append(HoverButton(style: .plain, height: 24, inset: 6, views: [icon, name], help: "Open \(item.displayName)") { [weak self] in
          self?.close()
          self?.model.openTucked(item)
        })
      }
    }
    return CardView(rows: rows)
  }

  private func optionsCard() -> NSView {
    let s = settings.s
    return CardView(rows: [
      sectionTitle("Options"),
      OptionRow(title: "Auto-hide", detail: s.autoHide ? "after \(s.autoHideSeconds)s" : nil, isOn: s.autoHide) { [weak self] on in
        self?.settings.s.autoHide = on
      },
      OptionRow(title: "Hide on app switch", isOn: s.collapseOnAppSwitch) { [weak self] on in
        self?.settings.s.collapseOnAppSwitch = on
      },
      OptionRow(title: "Always-hidden section", isOn: s.alwaysHidden) { [weak self] on in
        self?.settings.s.alwaysHidden = on
      },
    ])
  }

  private func footer() -> NSView {
    let items: [(String, String, () -> Void)] = [
      ("gearshape", "Settings…", { [weak self] in self?.close(); self?.model.openSettings() }),
      ("questionmark.circle", "How to Tuck Icons", { [weak self] in self?.close(); self?.model.showHelp() }),
      ("power", "Quit Tuck", { NSApp.terminate(nil) }),
    ]
    let buttons = items.map { name, help, action -> NSView in
      let b = HoverButton(style: .plain, height: 28, inset: 0, radius: 7,
                          views: [symbol(name, size: 13, weight: .regular, width: nil)], centered: true, help: help, action: action)
      b.setAccessibilityLabel(help)
      return b
    }
    let row = NSStackView(views: buttons)
    row.distribution = .fillEqually
    row.spacing = 0
    row.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
    return row
  }
}

/// Borderless panels can't become key by default; this one must, for Escape
/// and keyboard navigation. Non-activating, so the front app keeps focus.
final class DrawerWindow: NSPanel {
  var onCancel: () -> Void = {}
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onCancel() }
}

// MARK: - building blocks

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
  let l = NSTextField(labelWithString: text)
  l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
  l.textColor = color
  l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  return l
}

private func symbolImage(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage {
  let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
  return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
}

private func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, width: CGFloat?) -> NSImageView {
  let v = NSImageView(image: symbolImage(name, size: size, weight: weight))
  v.contentTintColor = .labelColor
  if let width { pin(v, width: width) }
  return v
}

private func pin(_ v: NSView, width: CGFloat? = nil, height: CGFloat? = nil) {
  v.translatesAutoresizingMaskIntoConstraints = false
  if let width { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
  if let height { v.heightAnchor.constraint(equalToConstant: height).isActive = true }
}

/// Small uppercase accent title, with an optional value on the right.
private func sectionTitle(_ title: String, value: String? = nil) -> NSView {
  let t = NSTextField(labelWithAttributedString: NSAttributedString(string: title.uppercased(), attributes: [
    .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .kern: 0.4, .foregroundColor: NSColor.controlAccentColor,
  ]))
  var views: [NSView] = [t, NSView()]
  if let value { views.append(label(value, size: 12, weight: .medium, mono: true)) }
  let row = NSStackView(views: views)
  row.alignment = .firstBaseline
  row.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
  row.setAccessibilityElement(true)
  row.setAccessibilityRole(.staticText)
  row.setAccessibilityLabel([title, value].compactMap { $0 }.joined(separator: ", "))
  return row
}

/// Stacks views top to bottom, each as wide as the stack minus its insets.
private func column(_ views: [NSView], spacing: CGFloat, inset: CGFloat) -> NSStackView {
  let s = NSStackView(views: views)
  s.orientation = .vertical
  s.alignment = .leading
  s.spacing = spacing
  s.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
  for v in views { v.widthAnchor.constraint(equalTo: s.widthAnchor, constant: -2 * inset).isActive = true }
  return s
}

private func fill(_ child: NSView, in parent: NSView) {
  parent.addSubview(child)
  child.translatesAutoresizingMaskIntoConstraints = false
  NSLayoutConstraint.activate([
    child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
    child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
    child.topAnchor.constraint(equalTo: parent.topAnchor),
    child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
  ])
}

/// Carries the card's drop shadow; it's what slides.
final class ShadowView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.28
    layer?.shadowRadius = 12
    layer?.shadowOffset = CGSize(width: 0, height: -6)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 13, cornerHeight: 13, transform: nil)
  }
}

/// The panel itself: menu material, denser than a stock menu, with a
/// hairline border, holding the cards.
private final class PanelCard: NSVisualEffectView {
  init(content: [NSView]) {
    super.init(frame: .zero)
    material = .menu
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 13
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    fill(Tint(), in: self)
    let stack = column(content, spacing: 6, inset: 8)
    fill(stack, in: self)
    stack.widthAnchor.constraint(equalToConstant: MenuPanel.width).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }

  /// Darkens the material so busy windows behind don't show through.
  private final class Tint: NSView {
    override func draw(_ dirtyRect: NSRect) {
      NSColor.windowBackgroundColor.withAlphaComponent(0.55).setFill()
      bounds.fill()
      NSColor.labelColor.withAlphaComponent(0.12).setStroke()
      let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 13, yRadius: 13)
      p.lineWidth = 0.5
      p.stroke()
    }
  }
}

/// A rounded, faintly filled card holding rows.
private final class CardView: NSView {
  init(rows: [NSView]) {
    super.init(frame: .zero)
    fill(column(rows, spacing: 6, inset: 8), in: self)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ dirtyRect: NSRect) {
    let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 9, yRadius: 9)
    NSColor.labelColor.withAlphaComponent(0.055).setFill()
    p.fill()
    NSColor.labelColor.withAlphaComponent(0.07).setStroke()
    p.lineWidth = 0.5
    p.stroke()
  }
}

/// A row that acts as a button: no fill until hovered, like a menu item
/// (`.plain`), or tinted with the accent (`.primary`). Keyboard and
/// VoiceOver use it like a button.
private final class HoverButton: NSView {
  enum Style { case primary, plain }
  private let style: Style
  private let radius: CGFloat
  private let action: () -> Void
  private var hovering = false { didSet { needsDisplay = true } }
  private var pressed = false { didSet { needsDisplay = true } }

  init(style: Style, height: CGFloat, inset: CGFloat, radius: CGFloat = 6, views: [NSView], trailing: NSView? = nil,
       centered: Bool = false, help: String? = nil, action: @escaping () -> Void) {
    self.style = style
    self.radius = radius
    self.action = action
    super.init(frame: .zero)
    var all = views
    if let trailing { all += [NSView(), trailing] } else if !centered { all.append(NSView()) }
    let row = NSStackView(views: all)
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
    if centered {
      addSubview(row)
      row.translatesAutoresizingMaskIntoConstraints = false
      row.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
      row.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    } else {
      fill(row, in: self)
    }
    pin(self, height: height)
    toolTip = help
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(views.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " "))
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                   owner: self, userInfo: nil))
  }
  required init?(coder: NSCoder) { fatalError() }

  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }
  override func mouseDown(with event: NSEvent) { pressed = true }
  override func mouseUp(with event: NSEvent) {
    pressed = false
    if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
  }

  override var acceptsFirstResponder: Bool { true }
  override func keyDown(with event: NSEvent) {
    if [" ", "\r"].contains(event.charactersIgnoringModifiers) { action() } else { super.keyDown(with: event) }
  }
  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill() }
  override func accessibilityPerformPress() -> Bool { action(); return true }

  override func draw(_ dirtyRect: NSRect) {
    let color: NSColor, alpha: CGFloat
    switch style {
    case .primary: color = .controlAccentColor; alpha = pressed ? 0.42 : hovering ? 0.3 : 0.2
    case .plain: color = .labelColor; alpha = pressed ? 0.16 : hovering ? 0.09 : 0
    }
    guard alpha > 0 else { return }
    color.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
  }
}

/// Title, optional detail, and a small switch on the right. Clicking
/// anywhere on the row flips it.
private final class OptionRow: NSView {
  private let toggle = NSSwitch()
  private let changed: (Bool) -> Void

  init(title: String, detail: String? = nil, isOn: Bool, changed: @escaping (Bool) -> Void) {
    self.changed = changed
    super.init(frame: .zero)
    toggle.controlSize = .mini
    toggle.state = isOn ? .on : .off
    toggle.target = self
    toggle.action = #selector(flipped)
    toggle.setAccessibilityLabel(title)
    var views: [NSView] = [label(title, size: 12)]
    if let detail { views.append(label(detail, size: 11, color: .secondaryLabelColor)) }
    views += [NSView(), toggle]
    let row = NSStackView(views: views)
    row.spacing = 6
    row.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
    fill(row, in: self)
    pin(self, height: 20)
  }
  required init?(coder: NSCoder) { fatalError() }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard frame.contains(point) else { return nil }
    let inSwitch = toggle.convert(point, from: superview)
    return toggle.bounds.contains(inSwitch) ? toggle : self
  }
  override func mouseDown(with event: NSEvent) {} // claim it, so mouseUp comes here
  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    toggle.state = toggle.state == .on ? .off : .on
    flipped()
  }
  @objc private func flipped() { changed(toggle.state == .on) }
}
