# MacAppSwitcher

Minimal native macOS floating app switcher prototype built with SwiftPM, AppKit, and SwiftUI.

The compact bar stays visible at the top-center of external screens and shows recently used apps for each screen.

## Run during development

```bash
swift run MacAppSwitcher
```

## Build during development

```bash
swift build
```

## Build a macOS `.app`

```bash
./scripts/build-app.sh
```

This creates:

```text
dist/MacAppSwitcher.app
```

Then it replaces the installed app at:

```text
/Applications/MacAppSwitcher.app
```

Open it with:

```bash
open /Applications/MacAppSwitcher.app
```

## Launch at login

After building/installing the app to `/Applications`:

1. Open **System Settings**.
2. Go to **General → Login Items & Extensions**.
3. In **Open at Login**, click `+`.
4. Select `/Applications/MacAppSwitcher.app`.

The app is an accessory app (`LSUIElement`), so it does not appear in the Dock.

## Quit and relaunch

Use the `…` menu in the floating bar and choose **Quitter complètement**.

To relaunch after quitting:

```bash
open /Applications/MacAppSwitcher.app
```

Or, during development:

```bash
swift run MacAppSwitcher
```
