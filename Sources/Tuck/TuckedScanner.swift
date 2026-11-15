import AppKit
import ApplicationServices

/// Finds menu bar icons through Accessibility (opt-in, `trackTucked`).
///
/// macOS has no API listing other apps' status items; each app exposes its
/// own through the AXExtrasMenuBar attribute. Icons pushed off screen are
/// not reported, so scans only run while Tuck is open. Apps are asked in
/// parallel with a short timeout, so one frozen app can't stall a scan
/// (a full scan takes ~0.3 s, on a background queue).
enum TuckedScanner {
  struct Found: @unchecked Sendable {
    var item: BarItem
    var element: AXUIElement
  }

  static var isTrusted: Bool { AXIsProcessTrusted() }

  /// Shows macOS's "allow Accessibility" prompt if Tuck isn't trusted yet.
  static func requestTrust() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  /// Every menu bar icon on screen except Tuck's own, in screen coordinates
  /// with a top-left origin (as Accessibility reports them).
  static func scan(completion: @escaping @MainActor ([Found]) -> Void) {
    let me = ProcessInfo.processInfo.processIdentifier
    let apps = NSWorkspace.shared.runningApplications
      // Background-only processes can't own menu bar icons; skipping them
      // roughly halves the apps to ask.
      .filter { $0.processIdentifier != me && ($0.activationPolicy != .prohibited || $0.localizedName == "MenuBarAgent") }
      .map { ($0.processIdentifier, $0.localizedName ?? "App") }
    DispatchQueue.global(qos: .utility).async {
      var results = [[Found]](repeating: [], count: apps.count)
      let lock = NSLock()
      DispatchQueue.concurrentPerform(iterations: apps.count) { i in
        let found = items(pid: apps[i].0, app: apps[i].1)
        lock.lock(); results[i] = found; lock.unlock()
      }
      let all = results.flatMap { $0 }
      DispatchQueue.main.async { MainActor.assumeIsolated { completion(all) } }
    }
  }

  private static func items(pid: pid_t, app: String) -> [Found] {
    let el = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(el, 0.3)
    guard let bar: AXUIElement = attribute(el, "AXExtrasMenuBar"),
          let kids: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
    return kids.compactMap { k in
      var p = CGPoint.zero, s = CGSize.zero
      guard let pos: AXValue = attribute(k, kAXPositionAttribute), AXValueGetValue(pos, .cgPoint, &p),
            let size: AXValue = attribute(k, kAXSizeAttribute), AXValueGetValue(size, .cgSize, &s) else { return nil }
      let desc: String = attribute(k, kAXDescriptionAttribute) ?? ""
      let title: String = attribute(k, kAXTitleAttribute) ?? ""
      let label = desc.isEmpty ? title : desc
      return Found(item: BarItem(app: app, label: label, frame: CGRect(origin: p, size: s), pid: pid), element: k)
    }
  }

  private static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
  }

  /// Opens an icon's menu the way a click would.
  static func press(_ found: Found) {
    if AXUIElementPerformAction(found.element, kAXPressAction as CFString) != .success {
      click(at: CGPoint(x: found.item.frame.midX, y: found.item.frame.midY))
    }
  }

  private static func click(at p: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
      CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
  }

  /// ⌘-drags an icon from one point to another, the same gesture a person
  /// uses to rearrange the menu bar. Runs off the main thread (it paces the
  /// drag with short sleeps) and puts the pointer back afterwards.
  static func commandDrag(from: CGPoint, to: CGPoint, done: @escaping @MainActor () -> Void) {
    let back = CGEvent(source: nil)?.location ?? from
    DispatchQueue.global(qos: .userInitiated).async {
      let src = CGEventSource(stateID: .hidSystemState)
      func post(_ t: CGEventType, _ p: CGPoint) {
        let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
        usleep(16_000)
      }
      let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
      cmdDown?.flags = .maskCommand
      cmdDown?.post(tap: .cghidEventTap)
      post(.mouseMoved, from)
      post(.leftMouseDown, from)
      usleep(250_000)
      for i in 1...20 {
        let t = CGFloat(i) / 20
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
      }
      usleep(150_000)
      post(.leftMouseUp, to)
      CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)?.post(tap: .cghidEventTap)
      CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)?.post(tap: .cghidEventTap)
      DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
    }
  }
}
