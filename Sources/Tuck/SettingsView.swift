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

struct SettingsView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Form {
      Section("Behavior") {
        Picker("Open on", selection: $model.s.openOn) {
          ForEach(OpenOn.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        Toggle("Tuck away automatically", isOn: $model.s.autoHide)
          .disabled(model.s.openOn == .hover)
        if model.s.openOn == .click && model.s.autoHide {
          Stepper(value: $model.s.autoHideSeconds, in: TuckSettings.secondsRange) {
            Text("After \(model.s.autoHideSeconds) second\(model.s.autoHideSeconds == 1 ? "" : "s")")
          }
        }
        Toggle("Tuck away when I switch apps", isOn: $model.s.collapseOnAppSwitch)
          .disabled(model.s.openOn == .hover)
        Toggle("Open while ⌘-dragging menu bar icons", isOn: $model.s.openWhileDragging)
        Text(model.s.openOn == .hover
             ? "In hover mode it closes once the pointer leaves the menu bar."
             : "Never closes under the pointer or while a menu is open.")
          .font(.caption).foregroundStyle(.secondary)

        Toggle("Start open", isOn: $model.s.startOpen)
        Picker("Shortcut", selection: $model.s.hotKey) {
          ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
        }
        Text("Tap to show or hide. Hold to peek: icons tuck away again when you let go.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Launch at login", isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        ))
        if let err = model.loginError {
          Text(err).font(.caption).foregroundStyle(.red)
        }
      }

      Section("Always hidden") {
        Toggle("Add an always-hidden section", isOn: $model.s.alwaysHidden)
        Text("Icons left of the dashed divider stay hidden even when Tuck is open. ⌥-click the arrow to show them.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("Tucked icons") {
        Toggle("Count and list tucked icons", isOn: $model.s.trackTucked)
        if model.s.trackTucked {
          if !model.trusted {
            Text("Needs Accessibility permission, which also lets Tuck move icons for you.")
              .font(.caption).foregroundStyle(.secondary)
            Button("Open Accessibility Settings…") {
              TuckedScanner.requestTrust()
              SettingsModel.openSystemSettings("com.apple.preference.security?Privacy_Accessibility")
            }
          } else {
            Toggle("Show count on the arrow", isOn: $model.s.showCount)
            Picker("Quick open shortcut", selection: $model.s.quickOpenHotKey) {
              ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
            }
            if model.s.quickOpenHotKey != .none && model.s.quickOpenHotKey == model.s.hotKey {
              Text("Same as the main shortcut, so it's off.").font(.caption).foregroundStyle(.red)
            }
            if model.tucked.isEmpty {
              Text("Nothing tucked, or Tuck hasn't looked yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(model.tucked.enumerated()), id: \.offset) { _, item in
              HStack {
                Text(item.displayName).lineLimit(1)
                Spacer()
                Button("Untuck") { model.untuck(item) }
              }
            }
            Button("Refresh List") { model.refreshTucked() }
          }
        }
        Text("Hold ⌘ and drag a menu bar icon left of Tuck's divider ( | ) to tuck it, right of the arrow to bring it back.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("Look") {
        Picker("Arrow", selection: $model.s.iconStyle) {
          ForEach(IconStyle.allCases) { style in
            Label(style.label, systemImage: style.symbols.left).tag(style)
          }
        }
        Toggle("Show divider while open", isOn: $model.s.showDivider)
        Toggle("Tooltip", isOn: $model.s.showTooltip)
        Picker("Menu bar icon spacing", selection: $model.s.spacing) {
          ForEach(IconSpacing.allCases) { Text($0.label).tag($0) }
        }
        Text("Changes spacing for every app's icon, so more fit beside the notch. Apps pick it up when they relaunch; log out to apply it everywhere.")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Text("The fade when icons tuck is drawn by macOS.")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Reduce Motion…") {
            SettingsModel.openSystemSettings("com.apple.preference.universalaccess?Seeing_Display")
          }
          .controlSize(.small)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }
}

@MainActor
final class SettingsWindow {
  private var window: NSWindow?
  private let model: SettingsModel

  init(model: SettingsModel) { self.model = model }

  func show() {
    if window == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
      w.title = "Tuck Settings"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      window = w
      // Coming back from System Settings after granting Accessibility.
      NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.model.trusted != TuckedScanner.isTrusted else { return }
          self.model.trusted = TuckedScanner.isTrusted
          if self.model.trusted && self.model.s.trackTucked { self.model.refreshTucked() }
        }
      }
    }
    model.launchAtLogin = SMAppService.mainApp.status == .enabled
    model.trusted = TuckedScanner.isTrusted
    if model.s.trackTucked && model.trusted { model.refreshTucked() }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
