# Tuck for macOS

Tuck the menu bar icons you rarely need behind a divider. Click the arrow, press a shortcut, or let it fold itself away again after a few seconds. The macOS sibling of [Tuck for Omarchy](https://github.com/twodxme/omarchy-tuck).

```
open       [ tucked icons ] | ›  [ always-visible icons ]  Sat 2:04 PM
tucked                        ‹  [ always-visible icons ]  Sat 2:04 PM
```

## Install

Build it (only the Command Line Tools are needed, no Xcode):

```bash
scripts/build-app.sh        # -> build/Tuck.app, universal, ad-hoc signed
cp -R build/Tuck.app /Applications/
open /Applications/Tuck.app
```

A downloaded copy is ad-hoc signed, not notarized, so the first launch needs a right-click on Tuck.app → **Open** → **Open**.

## Use

1. Hold **⌘** and drag the menu bar icons you want out of the way to the **left of Tuck's divider** ( | ).
2. Click the **arrow** to tuck them away or bring them back.
3. **Right-click** the arrow for Settings, help, and Quit.

The shortcut **⌥⌘\\** toggles it from anywhere. Scripts and tools like Raycast or Shortcuts can use links:

```bash
open tuck://toggle      # or expand, collapse, settings
```

## Settings

| Setting | Values | Default | |
|---|---|---|---|
| Open on | Click, Hover | Click | Hover opens when the pointer reaches the arrow and closes once it leaves the menu bar. |
| Tuck away automatically | on/off | on | Click mode: close again on its own. |
| After … seconds | 1–300 | 10 | Waits while the pointer is in the menu bar. |
| Start open | on/off | off | Show tucked icons when Tuck launches. |
| Shortcut | None, ⌥⌘\\, ⌃⌥⌘T, ⇧⌘\\, ⌃⌥\\ | ⌥⌘\\ | Global; needs no Accessibility permission. |
| Launch at login | on/off | off | Uses macOS's login items (Tuck must be in /Applications). |
| Arrow | Chevron, Arrow, Triangle, Double chevron, Dots | Chevron | |
| Show divider while open | on/off | on | The thin line that marks the boundary. |
| Tooltip | on/off | on | |

They're stored in `com.twodxme.tuck` defaults, so `defaults write com.twodxme.tuck autoHideSeconds -int 30` works too (restart Tuck after). Values Tuck doesn't understand fall back to the default.

## How it works

macOS gives apps no way to hide another app's menu bar item. Tuck adds two items, a divider and an arrow, and while tucked stretches the divider so everything to its left is pushed off screen. It's the same approach as Hidden Bar, Dozer, and Ice. Recent macOS drops a menu bar item wider than about half the screen, so the divider is sized to just past the space right of the notch (or just under half the screen without one) rather than a fixed huge width. Tuck refuses to collapse if the divider ends up to the right of its arrow (that would push the arrow away too) and says so in the arrow's tooltip.

Not possible without the Accessibility permission, so not in Tuck: counting or listing tucked icons, and untucking them from Settings. Drag them back instead.

## Develop

```bash
swift build
scripts/test.sh                 # swift-testing, works with only the CLT installed
/usr/bin/log stream --level info --predicate 'subsystem == "com.twodxme.tuck"'
```

The log line on every open and close shows where the divider and arrow sit, which is the quickest way to debug placement.

## License

MIT
