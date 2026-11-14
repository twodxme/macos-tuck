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
  case none, optCmdBackslash, ctrlOptCmdT, shiftCmdBackslash, ctrlOptBackslash
  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: return "None"
    case .optCmdBackslash: return "⌥⌘\\"
    case .ctrlOptCmdT: return "⌃⌥⌘T"
    case .shiftCmdBackslash: return "⇧⌘\\"
    case .ctrlOptBackslash: return "⌃⌥\\"
    }
  }

  /// (virtual key code, Carbon modifier mask)
  var combo: (keyCode: UInt32, modifiers: UInt32)? {
    let cmd: UInt32 = 1 << 8, shift: UInt32 = 1 << 9, opt: UInt32 = 1 << 11, ctrl: UInt32 = 1 << 12
    let backslash: UInt32 = 0x2A, t: UInt32 = 0x11
    switch self {
    case .none: return nil
    case .optCmdBackslash: return (backslash, opt | cmd)
    case .ctrlOptCmdT: return (t, ctrl | opt | cmd)
    case .shiftCmdBackslash: return (backslash, shift | cmd)
    case .ctrlOptBackslash: return (backslash, ctrl | opt)
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

  static let secondsRange = 1...300

  enum Key {
    static let openOn = "openOn", autoHide = "autoHide", autoHideSeconds = "autoHideSeconds"
    static let startOpen = "startOpen", iconStyle = "iconStyle", showDivider = "showDivider"
    static let showTooltip = "showTooltip", hotKey = "hotKey"
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
  }

  func tooltip(open: Bool) -> String {
    let first = open ? "Tuck icons away" : "Show tucked icons"
    let second: String
    switch (openOn, autoHide) {
    case (.hover, _): second = "Opens while the pointer is over it"
    case (.click, true): second = "Tucks itself away after \(autoHideSeconds) second\(autoHideSeconds == 1 ? "" : "s")"
    case (.click, false): second = "Stays open until you close it"
    }
    return "\(first)\n\(second)\nRight-click for settings"
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
func collapsedDividerLength(screenWidth: CGFloat, rightOfNotch: CGFloat?) -> CGFloat {
  let ceiling = screenWidth / 2 - 40
  let target = (rightOfNotch ?? screenWidth / 2) + 50
  return max(200, min(target, ceiling))
}
