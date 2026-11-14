import Foundation

/// Arrow glyphs, as SF Symbol names: (points left, points right).
enum IconStyle: String, CaseIterable, Identifiable {
  case chevron, arrow, triangle, double, dots
  var id: String { rawValue }

  var label: String {
    switch self {
    case .chevron: return "Chevron"
    case .arrow: return "Arrow"
    case .triangle: return "Triangle"
    case .double: return "Double chevron"
    case .dots: return "Dots"
    }
  }

  var symbols: (left: String, right: String) {
    switch self {
    case .chevron: return ("chevron.left", "chevron.right")
    case .arrow: return ("arrow.left", "arrow.right")
    case .triangle: return ("arrowtriangle.left.fill", "arrowtriangle.right.fill")
    case .double: return ("chevron.left.2", "chevron.right.2")
    case .dots: return ("ellipsis", "ellipsis")
    }
  }

  /// Collapsed, the arrow points to where the hidden icons will appear (left);
  /// open, back toward the divider.
  func symbol(open: Bool) -> String { open ? symbols.right : symbols.left }
}

enum OpenOn: String, CaseIterable, Identifiable {
  case click, hover
  var id: String { rawValue }
  var label: String { self == .click ? "Click" : "Hover" }
}

/// Global shortcut presets. A free-form recorder would need a lot of UI for
/// little gain; these cover the common picks and avoid system shortcuts.
enum HotKeyPreset: String, CaseIterable, Identifiable {
  case none, optCmdBackslash, ctrlOptCmdT, shiftCmdBackslash, ctrlOptBackslash, optCmdSlash, ctrlOptCmdO
  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: return "None"
    case .optCmdBackslash: return "⌥⌘\\"
    case .ctrlOptCmdT: return "⌃⌥⌘T"
    case .shiftCmdBackslash: return "⇧⌘\\"
    case .ctrlOptBackslash: return "⌃⌥\\"
    case .optCmdSlash: return "⌥⌘/"
    case .ctrlOptCmdO: return "⌃⌥⌘O"
    }
  }

  /// (virtual key code, Carbon modifier mask)
  var combo: (keyCode: UInt32, modifiers: UInt32)? {
    let cmd: UInt32 = 1 << 8, shift: UInt32 = 1 << 9, opt: UInt32 = 1 << 11, ctrl: UInt32 = 1 << 12
    let backslash: UInt32 = 0x2A, t: UInt32 = 0x11, slash: UInt32 = 0x2C, o: UInt32 = 0x1F
    switch self {
    case .none: return nil
    case .optCmdBackslash: return (backslash, opt | cmd)
    case .ctrlOptCmdT: return (t, ctrl | opt | cmd)
    case .shiftCmdBackslash: return (backslash, shift | cmd)
    case .ctrlOptBackslash: return (backslash, ctrl | opt)
    case .optCmdSlash: return (slash, opt | cmd)
    case .ctrlOptCmdO: return (o, ctrl | opt | cmd)
    }
  }
}

/// Menu bar icon spacing, written to the macOS-wide preferences
/// `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` (current host).
/// Apps read them at launch, so it takes effect as they relaunch, fully
/// after logging out. Tighter spacing fits more icons beside the notch.
enum IconSpacing: String, CaseIterable, Identifiable {
  case system, compact, tight
  var id: String { rawValue }
  var label: String {
    switch self {
    case .system: return "macOS default"
    case .compact: return "Compact"
    case .tight: return "Tight"
    }
  }
  /// (spacing, selection padding), or nil to remove the override.
  var values: (spacing: Int, padding: Int)? {
    switch self {
    case .system: return nil
    case .compact: return (8, 8)
    case .tight: return (4, 4)
    }
  }
}

/// Every setting, read from and written to UserDefaults, validated so a bad
/// value written with `defaults write` lands on the default instead of
/// breaking the app. Pure logic lives here so tests can cover it.
struct TuckSettings: Equatable {
  var openOn: OpenOn = .click
  var autoHide = true
  var autoHideSeconds = 10
  var startOpen = false
  var iconStyle: IconStyle = .chevron
  var showDivider = true
  var showTooltip = true
  var hotKey: HotKeyPreset = .optCmdBackslash
  /// Tuck away as soon as another app comes to the front.
  var collapseOnAppSwitch = true
  /// Open while ⌘-dragging icons in the menu bar, so they can be dropped
  /// into the tucked area. Off by default: it listens for mouse presses.
  var openWhileDragging = false
  /// A second, always-hidden section left of the tucked one; ⌥-click the
  /// arrow (or use tuck://all) to show it.
  var alwaysHidden = false
  /// Count, list and quick-open tucked icons. Needs Accessibility.
  var trackTucked = false
  var showCount = true
  var quickOpenHotKey: HotKeyPreset = .none
  var spacing: IconSpacing = .system
  /// Expert override for the collapsed divider width (points; 0 = automatic),
  /// for displays where the automatic width doesn't hide everything. Only
  /// settable with `defaults write`, never from the UI.
  var collapsedLengthOverride: Double = 0

  static let secondsRange = 1...300

  enum Key {
    static let openOn = "openOn", autoHide = "autoHide", autoHideSeconds = "autoHideSeconds"
    static let startOpen = "startOpen", iconStyle = "iconStyle", showDivider = "showDivider"
    static let showTooltip = "showTooltip", hotKey = "hotKey"
    static let collapseOnAppSwitch = "collapseOnAppSwitch", openWhileDragging = "openWhileDragging"
    static let alwaysHidden = "alwaysHidden", trackTucked = "trackTucked", showCount = "showCount"
    static let quickOpenHotKey = "quickOpenHotKey", spacing = "spacing"
    static let collapsedLength = "collapsedLength"
  }

  static func clampSeconds(_ value: Int) -> Int {
    min(secondsRange.upperBound, max(secondsRange.lowerBound, value))
  }

  static func load(from d: UserDefaults) -> TuckSettings {
    var s = TuckSettings()
    s.openOn = OpenOn(rawValue: d.string(forKey: Key.openOn) ?? "") ?? s.openOn
    if d.object(forKey: Key.autoHide) != nil { s.autoHide = d.bool(forKey: Key.autoHide) }
    if d.object(forKey: Key.autoHideSeconds) != nil {
      s.autoHideSeconds = clampSeconds(d.integer(forKey: Key.autoHideSeconds))
    }
    if d.object(forKey: Key.startOpen) != nil { s.startOpen = d.bool(forKey: Key.startOpen) }
    s.iconStyle = IconStyle(rawValue: d.string(forKey: Key.iconStyle) ?? "") ?? s.iconStyle
    if d.object(forKey: Key.showDivider) != nil { s.showDivider = d.bool(forKey: Key.showDivider) }
    if d.object(forKey: Key.showTooltip) != nil { s.showTooltip = d.bool(forKey: Key.showTooltip) }
    s.hotKey = HotKeyPreset(rawValue: d.string(forKey: Key.hotKey) ?? "") ?? s.hotKey
    func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
    s.collapseOnAppSwitch = bool(Key.collapseOnAppSwitch, s.collapseOnAppSwitch)
    s.openWhileDragging = bool(Key.openWhileDragging, s.openWhileDragging)
    s.alwaysHidden = bool(Key.alwaysHidden, s.alwaysHidden)
    s.trackTucked = bool(Key.trackTucked, s.trackTucked)
    s.showCount = bool(Key.showCount, s.showCount)
    s.quickOpenHotKey = HotKeyPreset(rawValue: d.string(forKey: Key.quickOpenHotKey) ?? "") ?? s.quickOpenHotKey
    s.spacing = IconSpacing(rawValue: d.string(forKey: Key.spacing) ?? "") ?? s.spacing
    let override = d.double(forKey: Key.collapsedLength)
    s.collapsedLengthOverride = (100...5000).contains(override) ? override : 0
    return s
  }

  func save(to d: UserDefaults) {
    d.set(openOn.rawValue, forKey: Key.openOn)
    d.set(autoHide, forKey: Key.autoHide)
    d.set(TuckSettings.clampSeconds(autoHideSeconds), forKey: Key.autoHideSeconds)
    d.set(startOpen, forKey: Key.startOpen)
    d.set(iconStyle.rawValue, forKey: Key.iconStyle)
    d.set(showDivider, forKey: Key.showDivider)
    d.set(showTooltip, forKey: Key.showTooltip)
    d.set(hotKey.rawValue, forKey: Key.hotKey)
    d.set(collapseOnAppSwitch, forKey: Key.collapseOnAppSwitch)
    d.set(openWhileDragging, forKey: Key.openWhileDragging)
    d.set(alwaysHidden, forKey: Key.alwaysHidden)
    d.set(trackTucked, forKey: Key.trackTucked)
    d.set(showCount, forKey: Key.showCount)
    d.set(quickOpenHotKey.rawValue, forKey: Key.quickOpenHotKey)
    d.set(spacing.rawValue, forKey: Key.spacing)
    // collapsedLengthOverride is never written: it stays a hand-set expert key.
  }

  /// The quick-open shortcut, unless it clashes with the toggle shortcut.
  var effectiveQuickOpenHotKey: HotKeyPreset {
    quickOpenHotKey == hotKey ? .none : quickOpenHotKey
  }

  func tooltip(open: Bool) -> String {
    let first = open ? "Tuck icons away" : "Show tucked icons"
    let second: String
    switch (openOn, autoHide) {
    case (.hover, _): second = "Opens while the pointer is over it"
    case (.click, true): second = "Tucks itself away after \(autoHideSeconds) second\(autoHideSeconds == 1 ? "" : "s")"
    case (.click, false): second = "Stays open until you close it"
    }
    let third = alwaysHidden ? "⌥-click to show hidden icons too\n" : ""
    return "\(first)\n\(second)\n\(third)Right-click for settings"
  }
}

/// The one rule that keeps Tuck from hiding itself: collapsing only makes
/// sense while the divider sits to the left of the arrow. If the user has
/// dragged them the other way round, stretching the divider would push the
/// arrow off screen with no way back.
func canCollapse(dividerMinX: CGFloat?, arrowMinX: CGFloat?) -> Bool {
  guard let d = dividerMinX, let a = arrowMinX else { return false }
  return d < a
}

/// How wide the divider gets while collapsed. Since macOS 26/27 the menu bar
/// silently drops a status item wider than about half the screen (a 10,000
/// point divider simply vanished and hid nothing), and a divider that fits
/// entirely in the visible bar leaves macOS's own « overflow marker behind.
/// So aim just past the bar space right of the notch (or half the screen
/// without one), staying under the half-screen ceiling. Measured on a
/// 2048-point notched display: 880–1000 hide cleanly, 600 leaves «, 1024+
/// hides nothing.
func collapsedDividerLength(screenWidth: CGFloat, rightOfNotch: CGFloat?, override: Double = 0) -> CGFloat {
  if override > 0 { return CGFloat(override) }
  let ceiling = screenWidth / 2 - 40
  let target = (rightOfNotch ?? screenWidth / 2) + 50
  return max(200, min(target, ceiling))
}

/// A window as `CGWindowListCopyWindowInfo` reports it, reduced to what the
/// "is a menu open?" check needs. Bounds are in top-left-origin points.
struct WindowSnapshot: Equatable {
  var layer: Int
  var bounds: CGRect
}

/// True while some app's dropdown hangs from the menu bar: a pop-up menu
/// (layer 101) anywhere, or any floating panel touching the bar's bottom
/// edge (status item popovers). The bar's own windows (layers 24/25) and
/// full-width strips are not dropdowns.
func dropdownOpen(_ windows: [WindowSnapshot], barHeight: CGFloat, screenWidth: CGFloat) -> Bool {
  windows.contains { w in
    if w.layer == 101 { return true }
    guard (3..<1000).contains(w.layer), w.layer != 24, w.layer != 25 else { return false }
    guard w.bounds.width < screenWidth - 1, w.bounds.height > 10 else { return false }
    return w.bounds.minY <= barHeight + 8 && w.bounds.maxY > barHeight
  }
}

/// A menu bar icon found through Accessibility.
struct BarItem: Equatable {
  var app: String
  var label: String
  var frame: CGRect
  var pid: pid_t

  /// What to call it in lists: its own label when it has one, else its app.
  /// System items without a label get a plain name instead of "MenuBarAgent".
  var displayName: String {
    let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let short = l.count > 40 ? String(l.prefix(39)) + "…" : l
    let appName = ["MenuBarAgent", "SystemUIServer", "ControlCenter", "Control Center"].contains(app) ? "System item" : app
    if short.isEmpty || short == app { return appName }
    return appName == "System item" ? short : "\(appName): \(short)"
  }
}

/// Icons sitting left of the divider (tucked), nearest the divider first.
/// `hiddenDividerMinX` splits off the always-hidden section when present.
func tuckedItems(_ items: [BarItem], dividerMinX: CGFloat, hiddenDividerMinX: CGFloat? = nil) -> [BarItem] {
  items
    .filter { $0.frame.maxX <= dividerMinX + 2 && $0.frame.width > 0 }
    .filter { hiddenDividerMinX == nil || $0.frame.minX >= hiddenDividerMinX! - 2 }
    .sorted { $0.frame.minX > $1.frame.minX }
}
