import AppKit
import SwiftUI

/// What the panel shows, pushed in by the app delegate whenever the status
/// controller's state changes while the panel is up.
@MainActor
final class PanelModel: ObservableObject {
  @Published var expanded = false
  @Published var showingAll = false
  @Published var hasHiddenSection = false
  @Published var tucked: [BarItem] = []
  @Published var shown = false

  var toggle: () -> Void = {}
  var toggleAll: () -> Void = {}
  var openTucked: (BarItem) -> Void = { _ in }
  var openSettings: () -> Void = {}
  var showHelp: () -> Void = {}
}

/// Tuck's menu: a panel of cards that slides down out of the menu bar under
/// the arrow, like a drawer. Replaces the plain right-click NSMenu.
///
/// The window never moves. Its content slides inside it and the window's
/// top edge clips it, so the panel appears to come out from under the bar.
@MainActor
final class MenuPanel {
  private let model: PanelModel
  private let settings: SettingsModel
  private var window: DrawerWindow?
  private var monitors: [Any] = []
  /// The arrow's window: its clicks are left to the arrow, which toggles.
  private weak var anchorWindow: NSWindow?

  /// Side and bottom room for the drawn shadow.
  static let shadowMargin: CGFloat = 18
  static let width: CGFloat = 280

  init(model: PanelModel, settings: SettingsModel) {
    self.model = model
    self.settings = settings
  }

  var isShown: Bool { window != nil }

  func toggle(under button: NSStatusBarButton) { isShown ? close() : show(under: button) }

  func show(under button: NSStatusBarButton) {
    guard window == nil, let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
    let host = NSHostingView(rootView: PanelRoot(model: model, settings: settings, close: { [weak self] in self?.close() }))
    let size = host.fittingSize
    let anchor = buttonWindow.frame
    anchorWindow = buttonWindow
    let m = Self.shadowMargin
    // Centered under the arrow, kept on screen.
    var x = anchor.midX - size.width / 2
    x = min(max(x, screen.frame.minX + 6 - m), screen.frame.maxX - 6 - size.width + m)
    let top = anchor.minY
    let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)

    let w = DrawerWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false // drawn by SwiftUI so it slides with the content
    w.level = .popUpMenu
    w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    w.isReleasedWhenClosed = false
    w.onCancel = { [weak self] in self?.close() }
    w.contentView = host
    w.setAccessibilityLabel("Tuck")
    window = w
    w.makeKeyAndOrderFront(nil)
    // Let the first frame render hidden, then slide.
    DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    installMonitors()
  }

  func close() {
    guard let w = window else { return }
    window = nil
    removeMonitors()
    model.shown = false
    DispatchQueue.main.asyncAfter(deadline: .now() + PanelRoot.closeDuration + 0.02) { w.orderOut(nil) }
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
}

/// Borderless panels can't become key by default; this one must, for Escape
/// and keyboard navigation. Non-activating, so the front app keeps focus.
final class DrawerWindow: NSPanel {
  var onCancel: () -> Void = {}
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onCancel() }
}

// MARK: - views

private enum Metric {
  static let radius: CGFloat = 13
  static let cardRadius: CGFloat = 9
  static let pad: CGFloat = 8
}

struct PanelRoot: View {
  @ObservedObject var model: PanelModel
  @ObservedObject var settings: SettingsModel
  let close: () -> Void
  @State private var height: CGFloat = 400

  static let closeDuration = 0.16
  private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  var body: some View {
    let m = MenuPanel.shadowMargin
    PanelContent(model: model, settings: settings, close: close)
      .frame(width: MenuPanel.width)
      .background(
        ZStack {
          VisualEffect()
          // Denser than a stock menu, so busy windows behind don't show through.
          Color(nsColor: .windowBackgroundColor).opacity(0.55)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)))
      .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
      .background(GeometryReader { g in Color.clear.onAppear { height = g.size.height } })
      // The drawer: slide down from above the window's top edge, which clips it.
      .offset(y: model.shown || reduceMotion ? 0 : -(height + 8))
      .opacity(model.shown ? 1 : (reduceMotion ? 0 : 0.4))
      .animation(model.shown
                 ? (reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.86))
                 : .easeIn(duration: Self.closeDuration), value: model.shown)
      .padding(EdgeInsets(top: 3, leading: m, bottom: m, trailing: m))
      .clipped()
  }
}

private struct PanelContent: View {
  @ObservedObject var model: PanelModel
  @ObservedObject var settings: SettingsModel
  let close: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      header
      if settings.s.trackTucked { tuckedCard }
      optionsCard
      footer
    }
    .padding(Metric.pad)
  }

  // MARK: cards

  private var header: some View {
    Card {
      CardTitle("Tuck", value: statusText)
      Button {
        model.toggle()
        close()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: settings.s.iconStyle.symbol(open: model.expanded))
            .font(.system(size: 11, weight: .bold))
            .frame(width: 14)
          Text(model.expanded ? "Tuck Away" : "Show Tucked Icons")
            .font(.system(size: 13, weight: .medium))
          Spacer(minLength: 4)
          if settings.s.hotKey != .none {
            Text(settings.s.hotKey.label)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .contentShape(Rectangle())
      }
      .buttonStyle(PrimaryRowStyle())
      .help(model.expanded ? "Tuck the icons left of the divider away" : "Show the icons tucked left of the divider")

      if model.hasHiddenSection {
        Button {
          model.toggleAll()
          close()
        } label: {
          Label(model.showingAll ? "Hide Always-Hidden Icons" : "Show Always-Hidden Icons Too",
                systemImage: model.showingAll ? "eye.slash" : "eye")
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .help("Same as ⌥-clicking the arrow")
      }
    }
  }

  private var statusText: String {
    if model.showingAll { return "All shown" }
    if model.expanded { return "Showing" }
    let n = model.tucked.count
    return settings.s.trackTucked && n > 0 ? "\(n) tucked" : "Tucked"
  }

  private var tuckedCard: some View {
    Card {
      CardTitle("Tucked", value: model.tucked.isEmpty ? nil : "\(model.tucked.count)")
      if !TuckedScanner.isTrusted {
        Button {
          TuckedScanner.requestTrust()
          close()
        } label: {
          RowLabel(text: "Allow Accessibility to list icons", systemImage: "lock")
        }
        .buttonStyle(HoverRowStyle())
      } else if model.tucked.isEmpty {
        Text("No tucked icons yet. Open Tuck once to list them.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 2)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.tucked.prefix(10).enumerated()), id: \.offset) { _, item in
            Button {
              close()
              model.openTucked(item)
            } label: {
              HStack(spacing: 8) {
                AppIcon(pid: item.pid)
                Text(item.displayName)
                  .font(.system(size: 12))
                  .lineLimit(1)
                  .truncationMode(.tail)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 6)
              .frame(height: 24)
              .contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            .help("Open \(item.displayName)")
          }
        }
      }
    }
  }

  private var optionsCard: some View {
    Card {
      CardTitle("Options")
      OptionRow(title: "Auto-hide", detail: settings.s.autoHide ? "after \(settings.s.autoHideSeconds)s" : nil,
                isOn: $settings.s.autoHide)
      OptionRow(title: "Hide on app switch", isOn: $settings.s.collapseOnAppSwitch)
      OptionRow(title: "Always-hidden section", isOn: $settings.s.alwaysHidden)
    }
  }

  private var footer: some View {
    HStack(spacing: 0) {
      FooterButton(systemImage: "gearshape", help: "Settings…") { close(); model.openSettings() }
      FooterButton(systemImage: "questionmark.circle", help: "How to Tuck Icons") { close(); model.showHelp() }
      FooterButton(systemImage: "power", help: "Quit Tuck") { NSApp.terminate(nil) }
    }
    .padding(.top, 2)
  }
}

// MARK: - building blocks

private struct Card<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 6) { content }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
        .fill(Color.primary.opacity(0.055)))
      .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
  }
}

private struct CardTitle: View {
  let title: String
  let value: String?
  init(_ title: String, value: String? = nil) { self.title = title; self.value = value }
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.4)
        .foregroundStyle(Color.accentColor)
      Spacer(minLength: 8)
      if let value {
        Text(value)
          .font(.system(size: 12, weight: .medium).monospacedDigit())
      }
    }
    .padding(.horizontal, 2)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

private struct OptionRow: View {
  let title: String
  var detail: String? = nil
  @Binding var isOn: Bool
  var body: some View {
    HStack(spacing: 6) {
      Text(title).font(.system(size: 12))
      if let detail {
        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(.accentColor)
    }
    .padding(.horizontal, 2)
    .frame(height: 20)
    .contentShape(Rectangle())
    .onTapGesture { isOn.toggle() }
    .accessibilityElement(children: .combine)
  }
}

private struct RowLabel: View {
  let text: String
  let systemImage: String
  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.system(size: 12))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 6)
      .frame(height: 24)
      .contentShape(Rectangle())
  }
}

private struct AppIcon: View {
  let pid: pid_t
  var body: some View {
    if let icon = NSRunningApplication(processIdentifier: pid)?.icon,
       NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.MenuBarAgent" {
      Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
    } else {
      Image(systemName: "menubar.rectangle")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
    }
  }
}

private struct FooterButton: View {
  let systemImage: String
  let help: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .regular))
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(HoverRowStyle(radius: 7))
    .help(help)
    .accessibilityLabel(help)
  }
}

/// The main action: tinted with the accent, brighter on hover and press.
private struct PrimaryRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverWrapper { hovering in
      configuration.label
        .foregroundStyle(.primary)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color.accentColor.opacity(configuration.isPressed ? 0.42 : hovering ? 0.3 : 0.2)))
    }
  }
}

/// Plain rows: no fill until hovered, like menu items.
private struct HoverRowStyle: ButtonStyle {
  var radius: CGFloat = 6
  func makeBody(configuration: Configuration) -> some View {
    HoverWrapper { hovering in
      configuration.label
        .foregroundStyle(.primary)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.09 : 0)))
    }
  }
}

private struct HoverWrapper<Content: View>: View {
  @ViewBuilder let content: (Bool) -> Content
  @State private var hovering = false
  var body: some View {
    content(hovering)
      .onHover { hovering = $0 }
      .animation(.easeOut(duration: 0.1), value: hovering)
  }
}

private struct VisualEffect: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = .menu
    v.blendingMode = .behindWindow
    v.state = .active
    return v
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
