# Panic Button

A global hotkey that instantly force-closes whatever window/game currently has focus. No confirmation, no "are you sure" — just gone.

Press the hotkey (`F9` by default) and whatever window is currently focused gets force-killed instantly, including its whole process tree (`taskkill /F /T`). Useful as a true panic button for instantly leaving a game — faster and more reliable than Alt+F4, which some games intercept or delay with a confirmation prompt.

This is a real Windows app (PowerShell + WinForms), not a background-only script. The full source is in [`PanicButton.ps1`](PanicButton.ps1) — read it before you run it.

![status](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)

## How to run it

Right-click **`PanicButton.ps1`** → **Run with PowerShell**. No install, no admin rights, no execution-policy setup needed — the script hides its own console window on launch, so that's the only file you need. (No `.vbs`/`.bat` wrapper — it's pure PowerShell end to end, since VBScript is being phased out of Windows.)

A small dark-themed window appears showing it's armed. From there you can:

- **Hide to Tray** (or just hit the X) — tucks it into the system tray; the hotkey keeps working while hidden.
- Click the tray icon (shield, near your clock) to bring the window back, or right-click it for Show/Exit.
- **Change Hotkey** — click it, then press any key/combo to rebind. Saved automatically for next launch.
- **Disarm** — temporarily disables the hotkey without closing the app.

## Run at startup (optional)

Open a PowerShell prompt in this folder and run:

```powershell
.\PanicButton.ps1 -EnableAutostart
```

This adds a single entry to your user-level `HKCU:\...\Run` registry key (no admin rights needed) pointing back at this script. To remove it:

```powershell
.\PanicButton.ps1 -DisableAutostart
```

## Updates

Once per launch, the app makes a single read-only request to a small [`VERSION`](VERSION) file in this repo to check if a newer release exists. That's the only network activity, and it does not run automatically — no code is downloaded or replaced without you clicking. If a newer version is found, a link appears in the app ("Update available: vX.X.X — click to install"); clicking it downloads the current `PanicButton.ps1` from this repo, overwrites your local copy, and restarts the app. If you'd rather not have even the version check happen, just delete the `Start-UpdateCheck` call near the bottom of the script — everything else works identically without it.

## ⚠️ Important

- **Fully universal by design**: it kills whatever window has focus when you press the hotkey, with no exceptions besides a short list of core Windows processes (`explorer`, `dwm`, `csrss`, `winlogon`, `wininit`, `services`, `lsass`, `svchost`, and PowerShell/the app itself). If your browser, Discord, or anything else is focused when you hit the key, that's what dies. Know what's focused before you press it.
- **No saving happens first.** Unsaved progress in whatever gets closed is lost, same as a crash or power-cut. Don't use it on anything with unsaved work you care about.
- **Network use is limited to the version check described above.** No telemetry, no data collection, no persistence beyond the Startup entry you control.

## Requirements

Windows 10 or 11. Nothing to install — it runs on PowerShell + .NET, both built into Windows.

## Files

Just one: `PanicButton.ps1`. No wrapper scripts in any other language — launching, hiding its own console, and enabling/disabling autostart are all handled by the script itself via `-EnableAutostart`/`-DisableAutostart` switches.

## Design notes

- **Why `taskkill /F /T` instead of `Stop-Process`?** Windows PowerShell 5.1's `Stop-Process` has no built-in tree-kill — it only signals the one PID, not its children. (.NET's `Process.Kill($true)` overload does support that, but it's PS7+/.NET 5+ only, and this is meant to run on stock Windows PowerShell 5.1 with zero dependencies.) `taskkill /T` handles that reliably on any Windows version.
- **High-DPI awareness** is explicitly enabled (`Application.SetHighDpiMode` + Per-Monitor-V2) so the UI renders crisp rather than OS-upscaled/blurry on scaled displays.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk. Not affiliated with any game or platform.
