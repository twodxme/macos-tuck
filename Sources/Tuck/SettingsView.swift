import AppKit
import ServiceManagement
import SwiftUI

/// Observable wrapper the settings window binds to; every change is saved
/// and pushed to the status controller at once.
@MainActor
final class SettingsModel: ObservableObject {
  @Published var s: TuckSettings { didSet { if s != oldValue { s.save(to: .standard); onChange(s) } } }
  @Published var launchAtLogin: Bool
  @Published var loginError: String?
  var onChange: (TuckSettings) -> Void = { _ in }

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
        Text(model.s.openOn == .hover
             ? "In hover mode it closes once the pointer leaves the menu bar."
             : "Waits while the pointer is in the menu bar.")
          .font(.caption).foregroundStyle(.secondary)

        Toggle("Start open", isOn: $model.s.startOpen)
        Picker("Shortcut", selection: $model.s.hotKey) {
          ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Launch at login", isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        ))
        if let err = model.loginError {
          Text(err).font(.caption).foregroundStyle(.red)
        }
      }

      Section("Look") {
        Picker("Arrow", selection: $model.s.iconStyle) {
          ForEach(IconStyle.allCases) { style in
            Label(style.label, systemImage: style.symbols.left).tag(style)
          }
        }
        Toggle("Show divider while open", isOn: $model.s.showDivider)
        Toggle("Tooltip", isOn: $model.s.showTooltip)
      }

      Section("Tucking icons") {
        Text("Hold ⌘ and drag a menu bar icon to the left of Tuck's divider ( | ) to tuck it. Drag it to the right of the arrow to bring it back.")
          .font(.callout).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 380)
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
    }
    model.launchAtLogin = SMAppService.mainApp.status == .enabled
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
