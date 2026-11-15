import AppKit
import SwiftUI

/// Shared bits for the Settings window.

/// Section title: small, uppercase, accent-colored (as in Tuck's menu).
struct SectionTitle: View {
  let title: String
  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title.uppercased())
      .font(.system(size: 11, weight: .semibold))
      .tracking(0.4)
      .foregroundStyle(Color.accentColor)
      .accessibilityAddTraits(.isHeader)
  }
}

extension BarItem {
  /// The owning app's icon; nil for system items, which have no useful one.
  var icon: NSImage? {
    let app = NSRunningApplication(processIdentifier: pid)
    return app?.bundleIdentifier == "com.apple.MenuBarAgent" ? nil : app?.icon
  }
}

/// A menu bar item's app icon, or a generic one for system items.
struct BarItemIcon: View {
  let item: BarItem
  var body: some View {
    if let icon = item.icon {
      Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
    } else {
      Image(systemName: "menubar.rectangle").foregroundStyle(.secondary).frame(width: 16, height: 16)
    }
  }
}

/// An NSVisualEffectView background.
struct VisualEffect: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let state: NSVisualEffectView.State

  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = material
    v.blendingMode = .behindWindow
    v.state = state
    return v
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

