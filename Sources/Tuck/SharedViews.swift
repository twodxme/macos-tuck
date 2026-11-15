import AppKit
import SwiftUI

/// Views the menu panel and Settings share.

/// Section title: small, uppercase, accent-colored, with an optional value
/// on the right.
struct SectionTitle: View {
  let title: String
  var value: String? = nil
  init(_ title: String, value: String? = nil) { self.title = title; self.value = value }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.4)
        .foregroundStyle(Color.accentColor)
      if let value {
        Spacer(minLength: 8)
        Text(value).font(.system(size: 12, weight: .medium).monospacedDigit())
      }
    }
    .padding(.horizontal, 2)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// A menu bar item's app icon, or a generic one for system items.
struct BarItemIcon: View {
  let pid: pid_t
  var body: some View {
    let app = NSRunningApplication(processIdentifier: pid)
    if let icon = app?.icon, app?.bundleIdentifier != "com.apple.MenuBarAgent" {
      Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
    } else {
      Image(systemName: "menubar.rectangle").foregroundStyle(.secondary).frame(width: 16, height: 16)
    }
  }
}

/// An NSVisualEffectView background.
struct Material: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  var state: NSVisualEffectView.State = .active
  init(_ material: NSVisualEffectView.Material, state: NSVisualEffectView.State = .active) {
    self.material = material
    self.state = state
  }

  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = material
    v.blendingMode = .behindWindow
    v.state = state
    return v
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

