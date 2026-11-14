import Foundation
import Testing
@testable import Tuck

@Suite struct SettingsTests {
  func defaults() -> UserDefaults {
    let name = "tuck-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
  }

  @Test func emptyDefaultsGiveDefaults() {
    #expect(TuckSettings.load(from: defaults()) == TuckSettings())
  }

  @Test func roundTrip() {
    let d = defaults()
    var s = TuckSettings()
    s.openOn = .hover; s.autoHide = false; s.autoHideSeconds = 42; s.startOpen = true
    s.iconStyle = .triangle; s.showDivider = false; s.showTooltip = false; s.hotKey = .ctrlOptCmdT
    s.collapseOnAppSwitch = false; s.openWhileDragging = true; s.alwaysHidden = true
    s.trackTucked = true; s.showCount = false; s.quickOpenHotKey = .optCmdSlash; s.spacing = .tight
    s.save(to: d)
    #expect(TuckSettings.load(from: d) == s)
  }

  @Test func junkFallsBack() {
    let d = defaults()
    d.set("<b>sideways</b>", forKey: TuckSettings.Key.openOn)
    d.set("nope", forKey: TuckSettings.Key.iconStyle)
    d.set("ctrl-alt-delete", forKey: TuckSettings.Key.hotKey)
    d.set(99_999, forKey: TuckSettings.Key.autoHideSeconds)
    let s = TuckSettings.load(from: d)
    #expect(s.openOn == .click)
    #expect(s.iconStyle == .chevron)
    #expect(s.hotKey == .optCmdBackslash)
    #expect(s.autoHideSeconds == 300)
  }

  @Test func secondsClamp() {
    #expect(TuckSettings.clampSeconds(0) == 1)
    #expect(TuckSettings.clampSeconds(-5) == 1)
    #expect(TuckSettings.clampSeconds(301) == 300)
    #expect(TuckSettings.clampSeconds(30) == 30)
  }

  @Test func arrowPointsWhereItOpens() {
    #expect(IconStyle.chevron.symbol(open: false) == "chevron.left")
    #expect(IconStyle.chevron.symbol(open: true) == "chevron.right")
    #expect(IconStyle.dots.symbol(open: true) == "ellipsis")
  }

  @Test func neverCollapseOverTheArrow() {
    #expect(canCollapse(dividerMinX: 100, arrowMinX: 140))
    #expect(!canCollapse(dividerMinX: 160, arrowMinX: 140))
    #expect(!canCollapse(dividerMinX: nil, arrowMinX: 140))
    #expect(!canCollapse(dividerMinX: 100, arrowMinX: nil))
  }

  @Test func hotKeyCombos() {
    #expect(HotKeyPreset.none.combo == nil)
    #expect(HotKeyPreset.optCmdBackslash.combo?.keyCode == 0x2A)
    #expect(HotKeyPreset.optCmdBackslash.combo?.modifiers == (1 << 11 | 1 << 8))
  }

  @Test func tooltipDescribesMode() {
    var s = TuckSettings()
    #expect(s.tooltip(open: false).hasPrefix("Show tucked icons\nTucks itself away after 10 seconds"))
    s.autoHideSeconds = 1
    #expect(s.tooltip(open: true).contains("after 1 second\n"))
    s.openOn = .hover
    #expect(s.tooltip(open: true).contains("pointer is over it"))
  }

  @Test func collapsedLengthStaysUnderHalfTheScreen() {
    // The notched 2048-point display it was measured on: 880–1000 works.
    let notched = collapsedDividerLength(screenWidth: 2048, rightOfNotch: 898.5)
    #expect(notched > 880 && notched < 1000)
    // No notch: just under half the screen.
    #expect(collapsedDividerLength(screenWidth: 1920, rightOfNotch: nil) == 920)
    // Never over the ceiling, never silly small.
    #expect(collapsedDividerLength(screenWidth: 1000, rightOfNotch: 900) == 460)
    #expect(collapsedDividerLength(screenWidth: 200, rightOfNotch: nil) == 200)
  }

  @Test func newSettingsDefaultsAndJunk() {
    let d = defaults()
    let s0 = TuckSettings.load(from: d)
    #expect(s0.collapseOnAppSwitch && !s0.openWhileDragging && !s0.alwaysHidden && !s0.trackTucked)
    #expect(s0.spacing == .system && s0.quickOpenHotKey == .none && s0.collapsedLengthOverride == 0)
    d.set("roomy", forKey: TuckSettings.Key.spacing)
    d.set(42.0, forKey: TuckSettings.Key.collapsedLength)       // too small to be real
    #expect(TuckSettings.load(from: d).spacing == .system)
    #expect(TuckSettings.load(from: d).collapsedLengthOverride == 0)
    d.set(1200.0, forKey: TuckSettings.Key.collapsedLength)
    #expect(TuckSettings.load(from: d).collapsedLengthOverride == 1200)
  }

  @Test func overrideWinsAndIsNeverSaved() {
    #expect(collapsedDividerLength(screenWidth: 2048, rightOfNotch: 898.5, override: 1200) == 1200)
    let d = defaults()
    var s = TuckSettings(); s.collapsedLengthOverride = 1500
    s.save(to: d)
    #expect(d.object(forKey: TuckSettings.Key.collapsedLength) == nil)
  }

  @Test func quickOpenNeverShadowsTheMainShortcut() {
    var s = TuckSettings()
    s.quickOpenHotKey = s.hotKey
    #expect(s.effectiveQuickOpenHotKey == .none)
    s.quickOpenHotKey = .optCmdSlash
    #expect(s.effectiveQuickOpenHotKey == .optCmdSlash)
  }

  @Test func spacingValues() {
    #expect(IconSpacing.system.values == nil)
    #expect(IconSpacing.tight.values! == (4, 4))
  }

  @Test func dropdownDetection() {
    let bar: CGFloat = 43.5, width: CGFloat = 2048
    // Nothing but the menu bar's own strips: closed.
    #expect(!dropdownOpen([WindowSnapshot(layer: 24, bounds: CGRect(x: 0, y: 0, width: 2048, height: 43.5)),
                           WindowSnapshot(layer: 25, bounds: CGRect(x: 1400, y: 0, width: 30, height: 43.5))],
                          barHeight: bar, screenWidth: width))
    // A pop-up menu (Tuck's own measured at layer 101, y -30): open.
    #expect(dropdownOpen([WindowSnapshot(layer: 101, bounds: CGRect(x: 1441, y: -30, width: 340, height: 278))],
                         barHeight: bar, screenWidth: width))
    // A floating panel hanging from the bar (a status item popover): open.
    #expect(dropdownOpen([WindowSnapshot(layer: 8, bounds: CGRect(x: 1500, y: 44, width: 300, height: 400))],
                         barHeight: bar, screenWidth: width))
    // An ordinary window, or a floating one mid-screen: closed.
    #expect(!dropdownOpen([WindowSnapshot(layer: 0, bounds: CGRect(x: 0, y: 44, width: 800, height: 600)),
                           WindowSnapshot(layer: 3, bounds: CGRect(x: 400, y: 400, width: 300, height: 300))],
                          barHeight: bar, screenWidth: width))
  }

  @Test func tuckedAreThoseLeftOfTheDivider() {
    func item(_ name: String, _ x: CGFloat, _ w: CGFloat = 24) -> BarItem {
      BarItem(app: name, label: "", frame: CGRect(x: x, y: 0, width: w, height: 24), pid: 1)
    }
    let items = [item("A", 1286), item("B", 1357), item("C", 1457), item("Visible", 1539)]
    // Divider at 1489: A, B, C are tucked, nearest the divider first.
    #expect(tuckedItems(items, dividerMinX: 1489).map(\.app) == ["C", "B", "A"])
    // With the hidden divider at 1340, A is always-hidden, not tucked.
    #expect(tuckedItems(items, dividerMinX: 1489, hiddenDividerMinX: 1340).map(\.app) == ["C", "B"])
  }

  @Test func displayNames() {
    let r = CGRect(x: 0, y: 0, width: 20, height: 20)
    #expect(BarItem(app: "Tailscale", label: "", frame: r, pid: 1).displayName == "Tailscale")
    #expect(BarItem(app: "Google Drive", label: "Google Drive", frame: r, pid: 1).displayName == "Google Drive")
    #expect(BarItem(app: "iStat Menus Menubar", label: "CPU 19%", frame: r, pid: 1).displayName == "iStat Menus Menubar: CPU 19%")
    #expect(BarItem(app: "MenuBarAgent", label: "", frame: r, pid: 1).displayName == "System item")
    #expect(BarItem(app: "MenuBarAgent", label: "Wi-Fi", frame: r, pid: 1).displayName == "Wi-Fi")
  }
}
