<p align="center"><img src="docs/icon.png" alt="Tuck's icon: a white glass chevron on a pink rounded square" width="128"></p>

# Tuck for macOS

<p>
  <a href="https://github.com/twodxme/macos-tuck/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/twodxme/macos-tuck?color=E0156B"></a>
  <a href="https://github.com/twodxme/macos-tuck/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/twodxme/macos-tuck/ci.yml?branch=main&label=tests"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/twodxme/macos-tuck?color=blue"></a>
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-555">
  <img alt="No third-party dependencies" src="https://img.shields.io/badge/dependencies-none-2EA44F">
  <img alt="No network access" src="https://img.shields.io/badge/network-none-2EA44F">
  <img alt="Signed build provenance" src="https://img.shields.io/badge/build-attested-2EA44F?logo=sigstore&logoColor=white">
</p>

Tuck the menu bar icons you rarely need behind a divider. Click the arrow, press a shortcut, or let it fold itself away again. The macOS sibling of [Tuck for Omarchy](https://github.com/twodxme/omarchy-tuck).

**Tucked away:** one arrow, and a count of what's behind it.

![Tuck tucked away: an arrow with the number 5 sits left of the always-visible icons](docs/tucked.png)

**Open:** the tucked icons slide out left of the divider ( | ).

![Tuck open: five tucked icons appear left of a thin divider and the arrow](docs/open.png)

**⌥-click:** icons in the always-hidden section, left of the dashed divider, show too.

![Tuck showing everything: one more icon appears left of a dashed divider](docs/all.png)

Tiny and asleep almost all the time: 0% CPU and no wakeups while tucked away, about 25 MB of memory (35 MB once you've opened its menu or Settings), a 2 MB app. Never touches the network, collects nothing, and needs no permissions unless you opt in. Works on macOS 13 and later, tested on macOS 27.

## Install

With [Homebrew](https://brew.sh):

```bash
brew tap twodxme/tap
brew trust twodxme/tap      # newer Homebrew asks you to trust third-party taps
brew install --cask tuck
```

Or download `Tuck.zip` from the [latest release](https://github.com/twodxme/macos-tuck/releases/latest), unzip it, and move Tuck.app to /Applications.

Tuck isn't notarized (that needs a paid Apple developer account), so macOS blocks its first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

Or build it yourself; only the Command Line Tools are needed, no Xcode:

```bash
scripts/build-app.sh        # -> build/Tuck.app, universal, ad-hoc signed
cp -R build/Tuck.app /Applications/
```

## Privacy and trust

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/privacy-dark.png">
  <img src="docs/privacy-light.png" alt="Privacy at a glance. Data Not Collected: Tuck doesn't collect, store, or send any data. No network: never connects to anything. No tracking: no analytics or crash reports. No permissions: Accessibility only if you opt in. Open source: MIT, zero dependencies." width="548">
</picture>

Tuck sits in your menu bar all day, so here is exactly what it does and doesn't do, and how to check each point yourself.

- **No network.** Tuck never connects to anything: no analytics, telemetry, crash reporting, update checks, or accounts. The only web addresses in the code are the *GitHub* and *Report an Issue* buttons in Settings → About, which open your browser when you click them. Check: `grep -rn "http" Sources/`.
- **No permissions by default.** Accessibility is asked for only if you turn on icon tracking, and only to see and move menu bar icons. See [Permissions](#permissions).
- **Writes only its own settings,** to `com.twodxme.tuck` in your user defaults. One exception, only if you choose *Compact* or *Tight* icon spacing: the two macOS-wide keys `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`. Setting spacing back to *macOS default* removes them.
- **Small enough to read.** About 2,200 lines of Swift with no third-party dependencies, only Apple's frameworks. MIT licensed.
- **Releases are built in public, and you can prove it.** Each release is built by [GitHub Actions](.github/workflows/release.yml) from the tagged commit, after the tests pass. Since 1.2.2 every `Tuck.zip` carries a signed [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) (Sigstore), so you can check that a download came from this repository's workflow and which commit it was built from, and a SHA-256 checksum. Homebrew checks the checksum for you; for a manual download:

  ```bash
  gh attestation verify Tuck.zip -R twodxme/macos-tuck   # built here, by CI, from this commit
  shasum -a 256 -c Tuck.zip.sha256                        # matches the published checksum
  ```

  Or skip the download and [build it yourself](#install).
- **Honest about signing.** Tuck is ad-hoc signed and not notarized, because notarizing needs a paid Apple developer account. That is why macOS asks you to approve the first launch.

### Uninstall

Quit Tuck from its menu, then delete it. Tuck's divider goes with the app, so every icon comes back.

```bash
brew uninstall --zap --cask tuck          # Homebrew: app and settings
# or by hand:
rm -rf /Applications/Tuck.app
defaults delete com.twodxme.tuck
```

If you changed icon spacing, set it back to *macOS default* in Settings first, or remove it afterwards with `defaults -currentHost delete -g NSStatusItemSpacing; defaults -currentHost delete -g NSStatusItemSelectionPadding`.

## Use

1. Hold **⌘** and drag the menu bar icons you want out of the way to the **left of Tuck's divider** ( | ). Drag them right of the arrow to bring them back.
2. **Click** the arrow to show or hide them, or press **⌥⌘\\** from anywhere.
3. **Hold** the shortcut to peek: the icons tuck away again when you let go.
4. **Right-click** (or ⌃-click) the arrow for Tuck's menu.

### The menu

Right-click the arrow and Tuck's menu slides down out of the menu bar like a drawer: show or tuck away with one click, flip the everyday options, open a tucked icon, or get to Settings, help, and Quit. Escape, a click elsewhere, or another click on the arrow closes it.

<img src="docs/menu.png" alt="Tuck's menu: a dark panel with a Tuck card holding a Show Tucked Icons button and the shortcut, an Options card with Auto-hide, Hide on app switch and Always-hidden section switches, and Settings, help and Quit buttons" width="316">

Tuck folds itself away after a few seconds, or as soon as you switch to another app, but never under the pointer or while a menu is open.

### Always-hidden section

Turn on **Settings → Always hidden** and a second, dashed divider appears. Icons left of it stay hidden even while Tuck is open: the place for icons you need once a month. **⌥-click** the arrow (or `open tuck://all`) to show them too.

### Tracking tucked icons

Turn on **Settings → Count and list tucked icons** (it asks for Accessibility; see [Permissions](#permissions)) and Tuck can:

- show **how many icons are tucked**, next to the arrow
- list them in Settings with an **Untuck** button each, which moves the icon right of the arrow for you
- list them in the menu too, with app icons: click one to open it
- **quick open**: a shortcut that lists tucked icons under the arrow. Type a few letters, press Return, and that icon's menu opens without untucking anything.

![Quick open: a menu under the arrow lists the tucked icons by name](docs/quick-open.png)

### Links

For scripts, Raycast, Shortcuts, or a keyboard tool:

```bash
open tuck://toggle      # show or hide
open tuck://expand      # show
open tuck://collapse    # hide
open tuck://all         # show the always-hidden section too, or back
open tuck://quickopen   # the quick open menu
open tuck://menu        # Tuck's menu
open tuck://settings
```

## Settings

Settings has five sections in a sidebar: General, Hiding, Tucked Icons, Appearance, and About. Hiding sketches how the menu bar is split up, so the divider trick explains itself.

<p>
  <img src="docs/settings.png" alt="Tuck's Settings, Hiding section: a sketch of the menu bar sections, then the tuck-away options and the always-hidden switch" width="49%">
  <img src="docs/settings-appearance.png" alt="Tuck's Settings, Appearance section: arrow styles as tiles, divider and tooltip switches, and icon spacing" width="49%">
</p>

| Setting | Default | |
|---|---|---|
| **Open on** | Click | *Hover* opens when the pointer reaches the arrow and closes once it leaves the menu bar. |
| **Tuck away automatically** | on, 10 s | 1–300 seconds. Waits while the pointer is in the menu bar or a menu is open. |
| **Tuck away when I switch apps** | on | |
| **Open while ⌘-dragging menu bar icons** | off | Opens as you start rearranging, so icons can be dropped into the tucked area. |
| **Start open** | off | |
| **Shortcut** | ⌥⌘\\ | Also ⌃⌥⌘T, ⇧⌘\\, ⌃⌥\\, ⌥⌘/, ⌃⌥⌘O, or none. Tap to toggle, hold to peek. |
| **Launch at login** | off | Tuck must be in /Applications. |
| **Always-hidden section** | off | |
| **Count and list tucked icons** | off | Needs Accessibility. |
| **Show count on the arrow** | on | |
| **Quick open shortcut** | none | Same choices as the main shortcut; ignored if they clash. |
| **Arrow** | Chevron | Arrow, Triangle, Double chevron, Dots. |
| **Show divider while open** | on | |
| **Show tooltip on the arrow** | on | |
| **Menu bar icon spacing** | macOS default | *Compact* or *Tight* fit more icons beside the notch. Changes every app's spacing; apps pick it up when they relaunch, all of them after you log out. |

Settings live in `com.twodxme.tuck` defaults, so `defaults write com.twodxme.tuck autoHideSeconds -int 30` works too (restart Tuck after). Values Tuck doesn't understand fall back to the default.

One expert key has no UI. If icons stay visible on some display, set the collapsed divider width by hand (100–5000 points; delete the key to go back to automatic):

```bash
defaults write com.twodxme.tuck collapsedLength -float 900
```

## Permissions

**None by default.** The shortcut uses Carbon hot keys and ⌘-drag detection uses a mouse-press monitor; neither needs a permission.

**Accessibility**, only if you turn on *Count and list tucked icons*: macOS has no other way to see other apps' menu bar icons or move them. Tuck is ad-hoc signed, so macOS treats every new version as a new app. After an update, remove Tuck from **Privacy & Security → Accessibility** with **−** and switch the setting off and on again so it asks afresh (or run `tccutil reset Accessibility com.twodxme.tuck`).

## Resource use

Tuck is built to disappear. Here it is in Activity Monitor a few minutes after launch, with its menu opened and closed in between: no CPU, no idle wake-ups, and just over half a second of CPU time in total.

![Activity Monitor filtered to Tuck: 0.0 % CPU, 0.59 seconds of CPU time, 4 threads, 0 idle wake ups](docs/activity-monitor.png)

- **Nothing polls while tucked.** Timers exist only while Tuck is open (auto-hide, hover) and carry tolerance, so macOS can batch them with its own wakeups.
- **Listeners are event-driven and scoped.** The app-switch observer exists only while open, the ⌘-drag monitor only while tucked and only if you turned it on.
- **Accessibility scans run only while open**, in the background, asking apps in parallel with a short timeout so a frozen app can't stall them (~0.3 s).
- **Small build**: optimized for size and stripped; the universal binary is about 0.8 MB, the whole app (icon included) about 2 MB.

The short fade as icons tuck and untuck is drawn by macOS, not Tuck. Tuck's own work takes about 8 ms; the rest (roughly a fifth of a second before macOS redraws, then its fade) happens in the system menu bar process and can't be shortened by an app.

## How it works

macOS gives apps no way to hide another app's menu bar icon. Tuck adds a divider and an arrow, and while tucked stretches the divider so everything left of it is pushed off screen: the approach of Hidden Bar, Dozer, and Ice. The always-hidden section is a second divider that stays stretched while Tuck is open.

Recent macOS drops a menu bar item wider than about half the screen, so the divider is sized to just past the space right of the notch (or just under half the screen without one) instead of a fixed huge width, and resized when displays change. Tuck refuses to collapse if the divider ends up right of its arrow (that would push the arrow away too) and says so in the arrow's tooltip.

A few macOS 27 details Tuck works around: clicks on menu bar icons arrive without their modifier keys (so ⌥-click reads the keyboard directly), freshly created icons report no position for about 0.3 s (so launch waits for real ones), and scroll events never reach menu bar icons.

## Develop

```bash
swift build
scripts/test.sh                 # swift-testing, works with only the CLT installed
scripts/make-icon.sh            # redraw Resources/AppIcon.icns from scripts/make-icon.swift
scripts/make-trust-card.sh      # redraw the privacy card in docs/
/usr/bin/log stream --level info --predicate 'subsystem == "com.twodxme.tuck"'
```

The log shows every state change (`mode open`, `mode collapsed`, `mode all`) and why a collapse was refused.

Push a `v*` tag and GitHub Actions tests, builds, and publishes a release with `Tuck.zip` and its SHA-256. Then bump `version` and `sha256` in the [tap's cask](https://github.com/twodxme/homebrew-tap/blob/main/Casks/tuck.rb).

## License

MIT
