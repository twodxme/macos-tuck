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
}
