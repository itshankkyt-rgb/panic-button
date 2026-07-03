# ============================================================
# Panic Button (windowed app)
# Press the configured hotkey to instantly force-kill whatever
# window/game currently has focus. Has a real UI + tray icon.
#
# Usage:
#   .\PanicButton.ps1                  Launch the app (hides its own console)
#   .\PanicButton.ps1 -EnableAutostart Add to Windows startup (HKCU Run key)
#   .\PanicButton.ps1 -DisableAutostart Remove from Windows startup
# ============================================================
param(
    [switch]$EnableAutostart,
    [switch]$DisableAutostart
)

# ---------- autostart toggle (registry Run key, no vbs/bat needed) ----------
if ($EnableAutostart -or $DisableAutostart) {
    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValueName = 'PanicButton'
    if ($EnableAutostart) {
        $launchCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Set-ItemProperty -Path $runKeyPath -Name $runValueName -Value $launchCommand
        Write-Host "Panic Button will now start automatically when you log in."
    } else {
        Remove-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue
        Write-Host "Autostart disabled."
    }
    return
}

# ---------- hide this process's own console window ----------
# Done in-process (no relaunch, no vbs/bat wrapper) so double-clicking /
# "Run with PowerShell" / the startup entry above don't leave a console behind.
Add-Type -Name ConsoleWindow -Namespace PanicButtonInternal -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consoleHandle = [PanicButtonInternal.ConsoleWindow]::GetConsoleWindow()
if ($consoleHandle -ne [IntPtr]::Zero) {
    [PanicButtonInternal.ConsoleWindow]::ShowWindow($consoleHandle, 0) | Out-Null  # SW_HIDE
}

$script:AppVersion = '1.2.0'
$script:VersionCheckUrl = 'https://raw.githubusercontent.com/itshankkyt-rgb/panic-button/main/VERSION'
$script:LatestScriptUrl = 'https://raw.githubusercontent.com/itshankkyt-rgb/panic-button/main/PanicButton.ps1'

$ConfigPath = "$PSScriptRoot\config.json"

# Processes we refuse to kill even if focused, so the OS itself never gets nuked.
$ProtectedProcessNames = @(
    'explorer', 'dwm', 'csrss', 'winlogon', 'wininit', 'services', 'lsass',
    'svchost', 'powershell', 'powershell_ise', 'pwsh', 'PanicButton'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High-DPI awareness - without this, Windows bitmap-scales the UI on
# non-100% displays, which is what makes it look blurry/asymmetric.
# (SetHighDpiMode needs .NET Framework 4.7+; older versions just skip it.)
try { [System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null } catch {}
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class HotkeyForm : Form
{
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public const int HOTKEY_ID = 9000;
    public const int WM_HOTKEY = 0x0312;
    private bool _registered = false;

    public event EventHandler HotkeyPressed;

    public bool RegisterGlobalHotkey(uint modifiers, uint key)
    {
        if (_registered) UnregisterHotKey(this.Handle, HOTKEY_ID);
        _registered = RegisterHotKey(this.Handle, HOTKEY_ID, modifiers, key);
        return _registered;
    }

    public void UnregisterGlobalHotkey()
    {
        if (_registered) { UnregisterHotKey(this.Handle, HOTKEY_ID); _registered = false; }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID)
        {
            if (HotkeyPressed != null) HotkeyPressed(this, EventArgs.Empty);
        }
        base.WndProc(ref m);
    }

    public static uint GetForegroundProcessId()
    {
        IntPtr hwnd = GetForegroundWindow();
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        return pid;
    }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

# ---------- config load/save ----------
function Load-Config {
    $default = [pscustomobject]@{ Modifier = 'None'; Key = 'F9'; Armed = $true }
    if (Test-Path $ConfigPath) {
        try { return (Get-Content $ConfigPath -Raw | ConvertFrom-Json) } catch { return $default }
    }
    return $default
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$script:cfg = Load-Config

function Get-ModifierValue([string]$modifierNames) {
    $map = @{ 'Alt' = 0x0001; 'Control' = 0x0002; 'Shift' = 0x0004; 'Win' = 0x0008; 'None' = 0x0000 }
    $value = 0
    foreach ($modifierName in ($modifierNames -split ',')) {
        $modifierName = $modifierName.Trim()
        if ($map.ContainsKey($modifierName)) { $value = $value -bor $map[$modifierName] }
    }
    return [uint32]$value
}

function Format-HotkeyLabel($modifier, $key) {
    if ($modifier -eq 'None' -or [string]::IsNullOrWhiteSpace($modifier)) { return $key }
    return "$modifier+$key"
}

# ---------- colors / theme ----------
$colBg      = [System.Drawing.Color]::FromArgb(18, 18, 20)
$colPanel   = [System.Drawing.Color]::FromArgb(28, 28, 32)
$colAccent  = [System.Drawing.Color]::FromArgb(225, 45, 45)
$colGreen   = [System.Drawing.Color]::FromArgb(60, 200, 110)
$colGray    = [System.Drawing.Color]::FromArgb(140, 140, 150)
$colText    = [System.Drawing.Color]::FromArgb(235, 235, 240)
$fontTitle  = [System.Drawing.Font]::new("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$fontLabel  = [System.Drawing.Font]::new("Segoe UI", 10)
$fontMono   = [System.Drawing.Font]::new("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$fontSmall  = [System.Drawing.Font]::new("Segoe UI", 8.5)

# ---------- build form ----------
$form = [HotkeyForm]::new()
$form.Text = "Panic Button v$($script:AppVersion)"
$form.Size = [System.Drawing.Size]::new(380, 505)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.BackColor = $colBg
$form.ForeColor = $colText
$form.KeyPreview = $true
$form.Icon = [System.Drawing.SystemIcons]::Shield

$lblTitle = [System.Windows.Forms.Label]::new()
$lblTitle.Text = "PANIC BUTTON"
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = $colAccent
$lblTitle.AutoSize = $false
$lblTitle.TextAlign = "MiddleCenter"
$lblTitle.Location = [System.Drawing.Point]::new(0, 20)
$lblTitle.Size = [System.Drawing.Size]::new(380, 36)
$form.Controls.Add($lblTitle)

# status dot + text
$lblStatus = [System.Windows.Forms.Label]::new()
$lblStatus.Font = $fontLabel
$lblStatus.TextAlign = "MiddleCenter"
$lblStatus.Location = [System.Drawing.Point]::new(0, 64)
$lblStatus.Size = [System.Drawing.Size]::new(380, 24)
$form.Controls.Add($lblStatus)

# hotkey panel
$panelHotkey = [System.Windows.Forms.Panel]::new()
$panelHotkey.BackColor = $colPanel
$panelHotkey.Location = [System.Drawing.Point]::new(30, 100)
$panelHotkey.Size = [System.Drawing.Size]::new(320, 70)
$form.Controls.Add($panelHotkey)

$lblHotkeyCaption = [System.Windows.Forms.Label]::new()
$lblHotkeyCaption.Text = "CURRENT HOTKEY"
$lblHotkeyCaption.Font = $fontSmall
$lblHotkeyCaption.ForeColor = $colGray
$lblHotkeyCaption.AutoSize = $false
$lblHotkeyCaption.TextAlign = "MiddleCenter"
$lblHotkeyCaption.Location = [System.Drawing.Point]::new(0, 8)
$lblHotkeyCaption.Size = [System.Drawing.Size]::new(320, 16)
$panelHotkey.Controls.Add($lblHotkeyCaption)

$lblHotkeyValue = [System.Windows.Forms.Label]::new()
$lblHotkeyValue.Font = $fontMono
$lblHotkeyValue.ForeColor = $colText
$lblHotkeyValue.TextAlign = "MiddleCenter"
$lblHotkeyValue.Location = [System.Drawing.Point]::new(0, 26)
$lblHotkeyValue.Size = [System.Drawing.Size]::new(320, 30)
$panelHotkey.Controls.Add($lblHotkeyValue)

# buttons row
function New-FlatButton($text, $x, $y, $width, $height, $backColor, $foreColor) {
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $text
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $backColor
    $button.ForeColor = $foreColor
    $button.Font = $fontLabel
    $button.Location = [System.Drawing.Point]::new($x, $y)
    $button.Size = [System.Drawing.Size]::new($width, $height)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

$btnChangeKey = New-FlatButton "Change Hotkey" 30 185 150 34 $colPanel $colText
$form.Controls.Add($btnChangeKey)

$btnToggleArm = New-FlatButton "Disarm" 200 185 150 34 $colAccent ([System.Drawing.Color]::White)
$form.Controls.Add($btnToggleArm)

# history
$lblHistoryCaption = [System.Windows.Forms.Label]::new()
$lblHistoryCaption.Text = "KILL HISTORY"
$lblHistoryCaption.Font = $fontSmall
$lblHistoryCaption.ForeColor = $colGray
$lblHistoryCaption.Location = [System.Drawing.Point]::new(30, 232)
$lblHistoryCaption.Size = [System.Drawing.Size]::new(320, 16)
$form.Controls.Add($lblHistoryCaption)

$lstHistory = [System.Windows.Forms.ListBox]::new()
$lstHistory.Location = [System.Drawing.Point]::new(30, 252)
$lstHistory.Size = [System.Drawing.Size]::new(320, 130)
$lstHistory.BackColor = $colPanel
$lstHistory.ForeColor = $colText
$lstHistory.BorderStyle = "FixedSingle"
$lstHistory.Font = $fontSmall
$form.Controls.Add($lstHistory)

# update notice - hidden until a newer version is actually found
$lnkUpdate = [System.Windows.Forms.LinkLabel]::new()
$lnkUpdate.Font = $fontSmall
$lnkUpdate.TextAlign = "MiddleCenter"
$lnkUpdate.LinkColor = $colAccent
$lnkUpdate.ActiveLinkColor = $colAccent
$lnkUpdate.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
$lnkUpdate.Location = [System.Drawing.Point]::new(30, 388)
$lnkUpdate.Size = [System.Drawing.Size]::new(320, 18)
$lnkUpdate.Visible = $false
$form.Controls.Add($lnkUpdate)

$btnHide = New-FlatButton "Hide to Tray" 30 412 150 34 $colPanel $colText
$form.Controls.Add($btnHide)

$btnExit = New-FlatButton "Exit" 200 412 150 34 $colPanel $colGray
$form.Controls.Add($btnExit)

# ---------- tray icon ----------
$icon = [System.Windows.Forms.NotifyIcon]::new()
$icon.Icon = [System.Drawing.SystemIcons]::Shield
$icon.Visible = $true
$menu = [System.Windows.Forms.ContextMenuStrip]::new()
$showItem = $menu.Items.Add("Show")
$exitItem = $menu.Items.Add("Exit Panic Button")
$icon.ContextMenuStrip = $menu

# ---------- state ----------
$script:listening = $false
$script:reallyExiting = $false
$script:latestVersion = $null

# ---------- update check (read-only, once per launch) ----------
# Fetches a single small text file from GitHub to compare versions.
# Nothing is downloaded/installed unless you click the link that appears.
function Start-UpdateCheck {
    $updateCheckJob = Start-Job -ScriptBlock {
        param($url)
        try { (Invoke-RestMethod -Uri $url -TimeoutSec 5).ToString().Trim() } catch { $null }
    } -ArgumentList $script:VersionCheckUrl

    $updateTimer = [System.Windows.Forms.Timer]::new()
    $updateTimer.Interval = 1500
    $updateTimer.Add_Tick({
        if ($updateCheckJob.State -notin @('Completed', 'Failed')) { return }
        $updateTimer.Stop()
        $updateTimer.Dispose()
        $latestVersionString = Receive-Job -Job $updateCheckJob -ErrorAction SilentlyContinue
        Remove-Job -Job $updateCheckJob -Force -ErrorAction SilentlyContinue
        if (-not $latestVersionString) { return }
        try {
            if ([version]$latestVersionString -gt [version]$script:AppVersion) {
                $script:latestVersion = $latestVersionString
                $lnkUpdate.Text = "Update available: v$latestVersionString - click to install"
                $lnkUpdate.Visible = $true
            }
        } catch {}
    })
    $updateTimer.Start()
}

function Install-Update {
    $confirmResult = [System.Windows.Forms.MessageBox]::Show(
        "Download and install version $($script:latestVersion)? Panic Button will restart.",
        "Panic Button Update", 'YesNo', 'Question')
    if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $newScriptContent = Invoke-RestMethod -Uri $script:LatestScriptUrl -TimeoutSec 15
        if ([string]::IsNullOrWhiteSpace($newScriptContent) -or $newScriptContent.Length -lt 500) {
            throw "Downloaded content looks invalid - aborting."
        }
        Set-Content -Path $PSCommandPath -Value $newScriptContent -Encoding UTF8

        $script:reallyExiting = $true
        $form.UnregisterGlobalHotkey()
        $icon.Visible = $false
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        [System.Windows.Forms.Application]::Exit()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Update failed: $_", "Panic Button", 'OK', 'Error') | Out-Null
    }
}

function Refresh-StatusUI {
    $label = Format-HotkeyLabel $script:cfg.Modifier $script:cfg.Key
    $lblHotkeyValue.Text = $label
    if ($script:cfg.Armed) {
        $lblStatus.Text = "* ARMED"
        $lblStatus.ForeColor = $colGreen
        $btnToggleArm.Text = "Disarm"
        $btnToggleArm.BackColor = $colAccent
        $icon.Text = "Panic Button - armed ($label)"
    } else {
        $lblStatus.Text = "* DISARMED"
        $lblStatus.ForeColor = $colGray
        $btnToggleArm.Text = "Arm"
        $btnToggleArm.BackColor = $colGreen
        $icon.Text = "Panic Button - disarmed"
    }
}

function Apply-Hotkey {
    $form.UnregisterGlobalHotkey()
    if ($script:cfg.Armed) {
        $modifierValue = Get-ModifierValue $script:cfg.Modifier
        $keyValue = [uint32][System.Windows.Forms.Keys]::($script:cfg.Key)
        $ok = $form.RegisterGlobalHotkey($modifierValue, $keyValue)
        if (-not $ok) {
            $icon.ShowBalloonTip(2500, "Panic Button", "Could not register hotkey - it may be in use by another app.", 'Error')
        }
    }
    Refresh-StatusUI
}

function Add-HistoryEntry($text) {
    $stamp = Get-Date -Format "HH:mm:ss"
    $lstHistory.Items.Insert(0, "[$stamp] $text")
    while ($lstHistory.Items.Count -gt 30) { $lstHistory.Items.RemoveAt($lstHistory.Items.Count - 1) }
}

# ---------- events ----------
$form.add_HotkeyPressed({
    $targetPid = [HotkeyForm]::GetForegroundProcessId()
    if ($targetPid -eq 0) { return }
    try { $proc = Get-Process -Id $targetPid -ErrorAction Stop } catch { return }

    if ($ProtectedProcessNames -contains $proc.ProcessName) {
        Add-HistoryEntry "Refused (protected): $($proc.ProcessName)"
        return
    }

    # taskkill /F /T is used instead of Stop-Process because Windows PowerShell 5.1's
    # Stop-Process has no tree-kill: it only signals the one PID, not child processes.
    # (.NET's Process.Kill(entireProcessTree) exists, but only on PS7+/.NET 5+.)
    Start-Process -FilePath "taskkill.exe" -ArgumentList "/F","/T","/PID",$targetPid -WindowStyle Hidden -ErrorAction SilentlyContinue
    Add-HistoryEntry "Killed: $($proc.ProcessName) (PID $targetPid)"
    $icon.ShowBalloonTip(1500, "Panic Button", "Killed: $($proc.ProcessName)", 'Info')
})

$btnChangeKey.Add_Click({
    $script:listening = $true
    $lblHotkeyValue.Text = "Press a key..."
    $btnChangeKey.Enabled = $false
})

$form.Add_KeyDown({
    param($eventSender, $eventArgs)
    if (-not $script:listening) { return }
    $modifierKeyNames = @('ControlKey', 'ShiftKey', 'Menu', 'LWin', 'RWin')
    if ($modifierKeyNames -contains $eventArgs.KeyCode.ToString()) { return }

    $modifierList = [System.Collections.Generic.List[string]]::new()
    if ($eventArgs.Control) { $modifierList.Add('Control') }
    if ($eventArgs.Alt)     { $modifierList.Add('Alt') }
    if ($eventArgs.Shift)   { $modifierList.Add('Shift') }
    $modifierString = if ($modifierList.Count -gt 0) { $modifierList -join ', ' } else { 'None' }

    $script:cfg.Modifier = $modifierString
    $script:cfg.Key = $eventArgs.KeyCode.ToString()
    Save-Config $script:cfg
    Apply-Hotkey

    $script:listening = $false
    $btnChangeKey.Enabled = $true
    $eventArgs.Handled = $true
    $eventArgs.SuppressKeyPress = $true
})

$btnToggleArm.Add_Click({
    $script:cfg.Armed = -not $script:cfg.Armed
    Save-Config $script:cfg
    Apply-Hotkey
})

$lnkUpdate.Add_Click({ Install-Update })

$btnHide.Add_Click({ $form.Hide() })
$showItem.Add_Click({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$icon.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })

$doExit = {
    $script:reallyExiting = $true
    $form.UnregisterGlobalHotkey()
    $icon.Visible = $false
    $icon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}
$btnExit.Add_Click($doExit)
$exitItem.Add_Click($doExit)

$form.Add_FormClosing({
    param($eventSender, $eventArgs)
    if (-not $script:reallyExiting) {
        $eventArgs.Cancel = $true
        $form.Hide()
    }
})

# ---------- go ----------
Refresh-StatusUI
Apply-Hotkey
Start-UpdateCheck
[System.Windows.Forms.Application]::Run($form)
