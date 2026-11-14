# Tuck for macOS

Tuck the menu bar icons you rarely need behind a divider. Click the arrow, press a shortcut, or let it fold itself away again. The macOS sibling of [Tuck for Omarchy](https://github.com/twodxme/omarchy-tuck).

```
tucked                                    ‹  [ always-visible icons ]  Sat 2:04 PM
open                     [ tucked icons ] | ›  [ always-visible icons ]  Sat 2:04 PM
⌥-click   [ hidden icons ] ⋮ [ tucked icons ] | ›  [ always-visible icons ]  Sat 2:04 PM
```

Tiny and asleep almost all the time: 0% CPU and no wakeups while tucked away, about 20 MB of memory, a 0.3 MB app.

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask twodxme/tap/tuck
```

Or download `Tuck.zip` from the [latest release](https://github.com/twodxme/macos-tuck/releases/latest), unzip it, and move Tuck.app to /Applications.

Tuck isn't notarized (that needs a paid Apple developer account), so macOS blocks the first launch of a downloaded copy. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

Or build it yourself; only the Command Line Tools are needed, no Xcode:

```bash
scripts/build-app.sh        # -> build/Tuck.app, universal, ad-hoc signed
cp -R build/Tuck.app /Applications/
```

## Use

1. Hold **⌘** and drag the menu bar icons you want out of the way to the **left of Tuck's divider** ( | ).
2. **Click** the arrow to show or hide them, or press **⌥⌘\\** from anywhere. **Hold** the shortcut to peek: they tuck away again when you let go.
3. **Right-click** the arrow for Settings, help, and Quit.

Tuck folds itself away after a few seconds, when you switch to another app, but never under the pointer or while a menu is open.

**Always-hidden section** (Settings → Always hidden): a second, dashed divider. Icons left of it stay hidden even while Tuck is open; **⌥-click** the arrow to show them too.

**Tracking tucked icons** (Settings → Tucked icons, needs Accessibility): a count on the arrow, a list of tucked icons with **Untuck** buttons, **Open Tucked Icon** in the right-click menu, and a **quick open** shortcut that lists tucked icons under the arrow: type a few letters, press Return, and that icon's menu opens without untucking anything.

Links for scripts, Raycast, or Shortcuts:

```bash
open tuck://toggle      # or expand, collapse, all, quickopen, settings
```

## Settings

| Setting | Values | Default | |
|---|---|---|---|
| Open on | Click, Hover | Click | Hover opens when the pointer reaches the arrow and closes once it leaves the menu bar. |
| Tuck away automatically | on/off, 1–300 s | on, 10 s | Click mode. Waits while the pointer is in the menu bar or a menu is open. |
| Tuck away when I switch apps | on/off | on | Click mode. |
| Open while ⌘-dragging menu bar icons | on/off | off | Opens as you start rearranging, so icons can be dropped into the tucked area. Listens for mouse presses, hence off by default. |
| Start open | on/off | off | |
| Shortcut | None, ⌥⌘\\, ⌃⌥⌘T, ⇧⌘\\, ⌃⌥\\, ⌥⌘/, ⌃⌥⌘O | ⌥⌘\\ | Tap to toggle, hold to peek. Needs no permission. |
| Launch at login | on/off | off | Tuck must be in /Applications. |
| Always-hidden section | on/off | off | |
| Count and list tucked icons | on/off | off | Needs Accessibility. |
| Show count on the arrow | on/off | on | |
| Quick open shortcut | as above | None | Ignored if it's the same as the main shortcut. |
| Arrow | Chevron, Arrow, Triangle, Double chevron, Dots | Chevron | |
| Show divider while open | on/off | on | |
| Tooltip | on/off | on | |
| Menu bar icon spacing | macOS default, Compact, Tight | macOS default | Changes every app's icon spacing (`NSStatusItemSpacing`), so more fit beside the notch. Apps pick it up when they relaunch; log out to apply everywhere. |

Settings live in `com.twodxme.tuck` defaults, so `defaults write com.twodxme.tuck autoHideSeconds -int 30` works too (restart Tuck after). Values Tuck doesn't understand fall back to the default.

One expert key has no UI: if icons stay visible on some display, set the collapsed divider width by hand (100–5000 points; delete the key to go back to automatic):

```bash
defaults write com.twodxme.tuck collapsedLength -float 900
```

## Permissions

None by default. The shortcut uses Carbon hot keys, and ⌘-drag detection uses a mouse-press monitor; neither needs a permission.

Accessibility is asked for only when you turn on **Count and list tucked icons**: macOS has no other way to see other apps' menu bar icons or to move them. Because Tuck is ad-hoc signed, macOS treats each new version as a new app, so after updating you may need to switch Tuck off and on again under **Privacy & Security → Accessibility**.

## How it works

macOS gives apps no way to hide another app's menu bar item. Tuck adds a divider and an arrow, and while tucked stretches the divider so everything left of it is pushed off screen: the approach of Hidden Bar, Dozer, and Ice. Recent macOS drops a menu bar item wider than about half the screen, so the divider is sized to just past the space right of the notch (or just under half the screen without one) rather than a fixed huge width. Tuck refuses to collapse if the divider ends up right of its arrow (that would push the arrow away too) and says so in the arrow's tooltip.

The short fade as icons tuck and untuck is drawn by macOS, not Tuck. Settings has a shortcut to **Reduce Motion** if you'd like to try it.

Nothing polls while Tuck is tucked away. Timers exist only while it's open (auto-hide, hover), and every listener is installed only in the state that needs it.

## Develop

```bash
swift build
scripts/test.sh                 # swift-testing, works with only the CLT installed
/usr/bin/log stream --level info --predicate 'subsystem == "com.twodxme.tuck"'
```

The log shows every state change (`mode open`, `mode collapsed`, `mode all`) and why a collapse was refused.

Releases: push a `v*` tag and GitHub Actions builds, tests, and attaches `Tuck.zip` to a release.

## License

MIT
