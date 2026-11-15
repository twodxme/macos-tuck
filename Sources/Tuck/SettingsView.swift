import AppKit
import ServiceManagement
import SwiftUI

/// Observable wrapper the settings window binds to; every change is saved
/// and pushed to the status controller at once.
@MainActor
final class SettingsModel: ObservableObject {
  @Published var s: TuckSettings {
    didSet {
      guard s != oldValue else { return }
      s.save(to: .standard)
      if s.spacing != oldValue.spacing { SettingsModel.applySpacing(s.spacing) }
      onChange(s)
    }
  }
  @Published var launchAtLogin: Bool
  @Published var loginError: String?
  @Published var tucked: [BarItem] = []
  @Published var trusted = TuckedScanner.isTrusted
  @Published var pane: SettingsPane = .general
  var onChange: (TuckSettings) -> Void = { _ in }
  var untuck: (BarItem) -> Void = { _ in }
  var refreshTucked: () -> Void = {}

  init(settings: TuckSettings) {
    s = settings
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func setLaunchAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      loginError = nil
    } catch {
      loginError = "Couldn't change it: \(error.localizedDescription). Move Tuck to /Applications and try again."
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  /// Writes (or removes) the macOS-wide spacing preferences for this Mac.
  /// Apps read them at launch, so they apply as apps relaunch.
  static func applySpacing(_ spacing: IconSpacing) {
    let app = kCFPreferencesAnyApplication, user = kCFPreferencesCurrentUser, host = kCFPreferencesCurrentHost
    let values = spacing.values
    CFPreferencesSetValue("NSStatusItemSpacing" as CFString, values.map { $0.spacing as CFNumber }, app, user, host)
    CFPreferencesSetValue("NSStatusItemSelectionPadding" as CFString, values.map { $0.padding as CFNumber }, app, user, host)
    CFPreferencesSynchronize(app, user, host)
  }

  static func openSystemSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
  }
}


// MARK: - settings window

enum SettingsPane: String, CaseIterable, Identifiable {
  case general, hiding, tucked, appearance, about
  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .hiding: return "Hiding"
    case .tucked: return "Tucked Icons"
    case .appearance: return "Appearance"
    case .about: return "About"
    }
  }

  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .hiding: return "eye.slash"
    case .tucked: return "list.bullet"
    case .appearance: return "paintbrush"
    case .about: return "info.circle"
    }
  }
}

struct SettingsView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    HStack(spacing: 0) {
      Sidebar(pane: $model.pane)
        .frame(width: 184)
      Divider()
      Group {
        switch model.pane {
        case .general: GeneralPane(model: model)
        case .hiding: HidingPane(model: model)
        case .tucked: TuckedPane(model: model)
        case .appearance: AppearancePane(model: model)
        case .about: AboutPane()
        }
      }
      .formStyle(.grouped)
      .padding(.top, 22) // clear of the transparent title bar
      .frame(width: 660 - 185, alignment: .top)
      .frame(maxHeight: .infinity, alignment: .top)
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(width: 660, height: 500)
    .ignoresSafeArea()
  }
}

// MARK: sidebar

private struct Sidebar: View {
  @Binding var pane: SettingsPane

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 10) {
        TuckLogo(size: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text("Tuck").font(.system(size: 14, weight: .semibold))
          Text("Version \(appVersion)").font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 46)
      .padding(.bottom, 14)

      ForEach(SettingsPane.allCases) { p in
        SidebarRow(pane: p, selected: pane == p) { pane = p }
      }
      Spacer()
    }
    .padding(.horizontal, 10)
    .frame(maxHeight: .infinity)
    .background(VisualEffect(material: .sidebar, state: .followsWindowActiveState))
  }
}

private struct SidebarRow: View {
  let pane: SettingsPane
  let selected: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: pane.symbol)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(selected ? Color.white : Color.accentColor)
          .frame(width: 22, height: 22)
          .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Color.accentColor : Color.accentColor.opacity(0.14)))
        Text(pane.title).font(.system(size: 13))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .frame(height: 32)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(Color.primary.opacity(selected ? 0.1 : hovering ? 0.05 : 0)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // The selection highlight already shows where you are; a focus ring on
    // top of it just looks like a glitch.
    .focusable(false)
    .onHover { hovering = $0 }
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

// MARK: panes

private struct GeneralPane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Form {
      Section {
        Picker("Open on", selection: $model.s.openOn) {
          ForEach(OpenOn.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260, alignment: .trailing)
        Picker("Shortcut", selection: $model.s.hotKey) {
          ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
        }
      } header: {
        SectionTitle("Opening")
      } footer: {
        Caption("Tap the shortcut to show or hide. Hold it to peek: icons tuck away again when you let go.")
      }

      Section {
        Toggle("Start open", isOn: $model.s.startOpen)
        Toggle("Launch at login", isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        ))
        if let err = model.loginError {
          Text(err).font(.caption).foregroundStyle(.red)
        }
      } header: {
        SectionTitle("Startup")
      }
    }
  }
}

private struct HidingPane: View {
  @ObservedObject var model: SettingsModel
  private var hover: Bool { model.s.openOn == .hover }

  var body: some View {
    Form {
      Section {
        BarDiagram(alwaysHidden: model.s.alwaysHidden)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)
      } header: {
        SectionTitle("How it works")
      } footer: {
        Caption("Hold ⌘ and drag a menu bar icon left of Tuck's divider ( | ) to tuck it, right of the arrow to bring it back.")
      }

      Section {
        Toggle("Tuck away automatically", isOn: $model.s.autoHide)
          .disabled(hover)
        if model.s.autoHide && !hover {
          Stepper(value: $model.s.autoHideSeconds, in: TuckSettings.secondsRange) {
            HStack {
              Text("After")
              Spacer()
              Text("\(model.s.autoHideSeconds) second\(model.s.autoHideSeconds == 1 ? "" : "s")")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
        Toggle("Tuck away when I switch apps", isOn: $model.s.collapseOnAppSwitch)
          .disabled(hover)
        Toggle("Open while ⌘-dragging menu bar icons", isOn: $model.s.openWhileDragging)
      } header: {
        SectionTitle("Tucking away")
      } footer: {
        Caption(hover
                ? "In hover mode Tuck closes once the pointer leaves the menu bar."
                : "Tuck never closes under the pointer or while a menu is open.")
      }

      Section {
        Toggle("Add an always-hidden section", isOn: $model.s.alwaysHidden)
      } header: {
        SectionTitle("Always hidden")
      } footer: {
        Caption("Icons left of the dashed divider stay hidden even when Tuck is open. ⌥-click the arrow to show them.")
      }
    }
  }
}

private struct TuckedPane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Form {
      Section {
        Toggle("Count and list tucked icons", isOn: $model.s.trackTucked)
        if model.s.trackTucked {
          HStack(spacing: 8) {
            Circle()
              .fill(model.trusted ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
            Text(model.trusted ? "Accessibility allowed" : "Needs Accessibility permission")
            Spacer()
            if !model.trusted {
              Button("Open Settings…") {
                TuckedScanner.requestTrust()
                SettingsModel.openSystemSettings("com.apple.preference.security?Privacy_Accessibility")
              }
              .controlSize(.small)
            }
          }
          .accessibilityElement(children: .combine)
        }
      } header: {
        SectionTitle("Tracking")
      } footer: {
        Caption("Accessibility lets Tuck see which icons are tucked and move them for you. Nothing leaves your Mac.")
      }

      if model.s.trackTucked && model.trusted {
        Section {
          Toggle("Show count on the arrow", isOn: $model.s.showCount)
          Picker("Quick open shortcut", selection: $model.s.quickOpenHotKey) {
            ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
          }
          if model.s.quickOpenHotKey != .none && model.s.quickOpenHotKey == model.s.hotKey {
            Text("Same as the main shortcut, so it's off.").font(.caption).foregroundStyle(.red)
          }
        } header: {
          SectionTitle("Options")
        }

        Section {
          if model.tucked.isEmpty {
            Text("Nothing tucked, or Tuck hasn't looked yet.")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(model.tucked.enumerated()), id: \.offset) { _, item in
            HStack(spacing: 8) {
              BarItemIcon(item: item)
              Text(item.displayName).lineLimit(1).truncationMode(.tail)
              Spacer()
              Button("Untuck") { model.untuck(item) }
                .controlSize(.small)
            }
          }
        } header: {
          HStack {
            SectionTitle("Tucked now")
            Spacer()
            Button {
              model.refreshTucked()
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh the list")
            .accessibilityLabel("Refresh the list")
          }
        }
      }
    }
  }
}

private struct AppearancePane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Form {
      Section {
        HStack(spacing: 8) {
          ForEach(IconStyle.allCases) { style in
            ArrowTile(style: style, selected: model.s.iconStyle == style) { model.s.iconStyle = style }
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
      } header: {
        SectionTitle("Arrow")
      }

      Section {
        Toggle("Show divider while open", isOn: $model.s.showDivider)
        Toggle("Show tooltip on the arrow", isOn: $model.s.showTooltip)
      } header: {
        SectionTitle("Menu bar")
      }

      Section {
        Picker("Icon spacing", selection: $model.s.spacing) {
          ForEach(IconSpacing.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
      } header: {
        SectionTitle("Spacing")
      } footer: {
        Caption("Changes spacing for every app's icon, so more fit beside the notch. Apps pick it up when they relaunch; log out to apply it everywhere.")
      }
    }
  }
}

private struct AboutPane: View {
  var body: some View {
    VStack(spacing: 10) {
      TuckLogo(size: 64)
        .padding(.top, 36)
      Text("Tuck").font(.system(size: 22, weight: .semibold))
      Text("Version \(appVersion)").foregroundStyle(.secondary)
      Text("Tucks menu bar icons away behind an arrow.\nFree and open source, MIT License.")
        .multilineTextAlignment(.center)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 4)
      HStack(spacing: 10) {
        Button("GitHub") { open("https://github.com/twodxme/macos-tuck") }
        Button("Report an Issue") { open("https://github.com/twodxme/macos-tuck/issues") }
      }
      .padding(.top, 8)

      VStack(alignment: .leading, spacing: 4) {
        SectionTitle("Scripting")
        Text("open \"tuck://toggle\"\nexpand · collapse · all · menu · quickopen · settings")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .padding(12)
      .frame(maxWidth: 400, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
      .padding(.top, 18)
    }
    .frame(maxWidth: .infinity)
  }

  private func open(_ s: String) {
    if let url = URL(string: s) { NSWorkspace.shared.open(url) }
  }
}

// MARK: building blocks

private var appVersion: String {
  Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}

private struct Caption: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }
}

private struct TuckLogo: View {
  let size: CGFloat
  var body: some View {
    // macOS hands back the icon already masked, with the icon grid's ~10%
    // transparent margin on each side, so draw it larger to fill `size`.
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .interpolation(.high)
      .frame(width: size * 1.24, height: size * 1.24)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

private struct ArrowTile: View {
  let style: IconStyle
  let selected: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: style.symbols.left)
          .font(.system(size: 15, weight: .semibold))
          .frame(height: 22)
        Text(style == .double ? "Double" : style.label)
          .font(.system(size: 10))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 58)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.07 : 0.04)))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel(style.label)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

/// A sketch of the menu bar sections, so the divider trick explains itself.
private struct BarDiagram: View {
  let alwaysHidden: Bool

  var body: some View {
    HStack(spacing: 6) {
      if alwaysHidden {
        Zone(label: "Always hidden", dots: 2, faded: true)
        Glyph("⋮")
      }
      Zone(label: "Tucked", dots: 3, faded: false)
      Glyph("|")
      Image(systemName: "chevron.left")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 22, height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.15)))
      Zone(label: "Always shown", dots: 3, faded: false)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(alwaysHidden
      ? "Menu bar, left to right: always-hidden icons, dashed divider, tucked icons, divider, Tuck's arrow, always-shown icons."
      : "Menu bar, left to right: tucked icons, divider, Tuck's arrow, always-shown icons.")
  }

  private struct Zone: View {
    let label: String
    let dots: Int
    let faded: Bool
    var body: some View {
      VStack(spacing: 5) {
        HStack(spacing: 5) {
          ForEach(0..<dots, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(faded ? 0.22 : 0.5)).frame(width: 12, height: 12)
          }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
        Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      }
    }
  }

  private struct Glyph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
      Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
        .frame(height: 22)
        .padding(.bottom, 15)
    }
  }
}

@MainActor
final class SettingsWindow {
  private var window: NSWindow?
  private var observers: [NSObjectProtocol] = []
  private let model: SettingsModel

  init(model: SettingsModel) { self.model = model }

  /// Settings is built on demand and torn down on close: a closed window
  /// would otherwise keep its whole SwiftUI view graph (~7 MB) alive.
  func show(pane: SettingsPane? = nil) {
    if let pane { model.pane = pane }
    if window == nil {
      let host = NSHostingController(rootView: SettingsView(model: model))
      // Fixed size: left to itself the hosting controller adds the title
      // bar's height under the full-size content view.
      host.sizingOptions = []
      let w = SettingsNSWindow(contentViewController: host)
      w.title = "Tuck Settings"
      // The sidebar runs up under the traffic lights.
      w.styleMask = [.titled, .closable, .fullSizeContentView]
      w.titlebarAppearsTransparent = true
      w.titleVisibility = .hidden
      w.isMovableByWindowBackground = true
      w.isReleasedWhenClosed = false
      w.setContentSize(NSSize(width: 660, height: 500))
      w.center()
      window = w
      let nc = NotificationCenter.default
      // Coming back from System Settings after granting Accessibility.
      observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.model.trusted != TuckedScanner.isTrusted else { return }
          self.model.trusted = TuckedScanner.isTrusted
          if self.model.trusted && self.model.s.trackTucked { self.model.refreshTucked() }
        }
      })
      observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.tearDown() }
      })
    }
    model.launchAtLogin = SMAppService.mainApp.status == .enabled
    model.trusted = TuckedScanner.isTrusted
    // The tucked list shows what the last scan found; a fresh one would
    // have to un-tuck the bar, so only the Refresh button asks for that.
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  private func tearDown() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    // Let the close finish before dropping the last reference.
    let w = window
    window = nil
    DispatchQueue.main.async { w?.contentViewController = nil }
  }
}

/// Tuck has no app menu (it lives in the menu bar), so nothing maps ⌘W to
/// Close; the window handles it itself.
private final class SettingsNSWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
       event.charactersIgnoringModifiers == "w" {
      performClose(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
