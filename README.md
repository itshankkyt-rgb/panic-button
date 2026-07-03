# Panic Button

A global hotkey that instantly force-closes whatever window/game currently has focus. No confirmation, no "are you sure" — just gone.

Press the hotkey (`F9` by default) and whatever window is currently focused gets force-killed instantly, including its whole process tree (`taskkill /F /T`). Useful as a true panic button for instantly leaving a game — faster and more reliable than Alt+F4, which some games intercept or delay with a confirmation prompt.

This is a real Windows app (PowerShell + WinForms), not a background-only script. The full source is in [`PanicButton.ps1`](PanicButton.ps1) — read it before you run it.

![status](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)

## How to run it

Double-click **`Launch PanicButton.vbs`**. No install, no admin rights needed.

A small dark-themed window appears showing it's armed. From there you can:

- **Hide to Tray** (or just hit the X) — tucks it into the system tray; the hotkey keeps working while hidden.
- Click the tray icon (shield, near your clock) to bring the window back, or right-click it for Show/Exit.
- **Change Hotkey** — click it, then press any key/combo to rebind. Saved automatically for next launch.
- **Disarm** — temporarily disables the hotkey without closing the app.

## Run at startup (optional)

Run `Enable Autostart.bat` once — it copies the silent launcher into your Windows Startup folder. Run `Disable Autostart.bat` to remove it.

## ⚠️ Important

- **Fully universal by design**: it kills whatever window has focus when you press the hotkey, with no exceptions besides a short list of core Windows processes (`explorer`, `dwm`, `csrss`, `winlogon`, `wininit`, `services`, `lsass`, `svchost`, and PowerShell/the app itself). If your browser, Discord, or anything else is focused when you hit the key, that's what dies. Know what's focused before you press it.
- **No saving happens first.** Unsaved progress in whatever gets closed is lost, same as a crash or power-cut. Don't use it on anything with unsaved work you care about.
- **Local only.** No networking, no telemetry, no persistence beyond the Startup shortcut you control.

## Requirements

Windows 10 or 11. Nothing to install — it runs on PowerShell + .NET, both built into Windows.

## Files

| File | Purpose |
|---|---|
| `PanicButton.ps1` | The app itself (readable source) |
| `Launch PanicButton.vbs` | Silent launcher — use this to run it |
| `Enable Autostart.bat` | Adds it to Windows startup |
| `Disable Autostart.bat` | Removes it from Windows startup |

## License

MIT — see [LICENSE](LICENSE). Use at your own risk. Not affiliated with any game or platform.
