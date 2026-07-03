# ============================================================
# Panic Button (windowed app)
# Press the configured hotkey to instantly force-kill whatever
# window/game currently has focus. Has a real UI + tray icon.
# ============================================================

$ConfigPath = "$PSScriptRoot\config.json"

# Processes we refuse to kill even if focused, so the OS itself never gets nuked.
$ProtectedProcessNames = @(
    'explorer', 'dwm', 'csrss', 'winlogon', 'wininit', 'services', 'lsass',
    'svchost', 'powershell', 'powershell_ise', 'pwsh', 'PanicButton'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

function Get-ModifierValue([string]$names) {
    $map = @{ 'Alt' = 0x0001; 'Control' = 0x0002; 'Shift' = 0x0004; 'Win' = 0x0008; 'None' = 0x0000 }
    $val = 0
    foreach ($n in ($names -split ',')) {
        $n = $n.Trim()
        if ($map.ContainsKey($n)) { $val = $val -bor $map[$n] }
    }
    return [uint32]$val
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
$fontTitle  = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$fontLabel  = New-Object System.Drawing.Font("Segoe UI", 10)
$fontMono   = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$fontSmall  = New-Object System.Drawing.Font("Segoe UI", 8.5)

# ---------- build form ----------
$form = New-Object HotkeyForm
$form.Text = "Panic Button"
$form.Size = New-Object System.Drawing.Size(380, 480)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $colBg
$form.ForeColor = $colText
$form.KeyPreview = $true
$form.Icon = [System.Drawing.SystemIcons]::Shield

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "PANIC BUTTON"
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = $colAccent
$lblTitle.AutoSize = $false
$lblTitle.TextAlign = "MiddleCenter"
$lblTitle.Location = New-Object System.Drawing.Point(0, 20)
$lblTitle.Size = New-Object System.Drawing.Size(380, 36)
$form.Controls.Add($lblTitle)

# status dot + text
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Font = $fontLabel
$lblStatus.TextAlign = "MiddleCenter"
$lblStatus.Location = New-Object System.Drawing.Point(0, 64)
$lblStatus.Size = New-Object System.Drawing.Size(380, 24)
$form.Controls.Add($lblStatus)

# hotkey panel
$panelHotkey = New-Object System.Windows.Forms.Panel
$panelHotkey.BackColor = $colPanel
$panelHotkey.Location = New-Object System.Drawing.Point(30, 100)
$panelHotkey.Size = New-Object System.Drawing.Size(320, 70)
$form.Controls.Add($panelHotkey)

$lblHotkeyCaption = New-Object System.Windows.Forms.Label
$lblHotkeyCaption.Text = "CURRENT HOTKEY"
$lblHotkeyCaption.Font = $fontSmall
$lblHotkeyCaption.ForeColor = $colGray
$lblHotkeyCaption.AutoSize = $false
$lblHotkeyCaption.TextAlign = "MiddleCenter"
$lblHotkeyCaption.Location = New-Object System.Drawing.Point(0, 8)
$lblHotkeyCaption.Size = New-Object System.Drawing.Size(320, 16)
$panelHotkey.Controls.Add($lblHotkeyCaption)

$lblHotkeyValue = New-Object System.Windows.Forms.Label
$lblHotkeyValue.Font = $fontMono
$lblHotkeyValue.ForeColor = $colText
$lblHotkeyValue.TextAlign = "MiddleCenter"
$lblHotkeyValue.Location = New-Object System.Drawing.Point(0, 26)
$lblHotkeyValue.Size = New-Object System.Drawing.Size(320, 30)
$panelHotkey.Controls.Add($lblHotkeyValue)

# buttons row
function New-FlatButton($text, $x, $y, $w, $h, $bg, $fg) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $bg
    $btn.ForeColor = $fg
    $btn.Font = $fontLabel
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Size = New-Object System.Drawing.Size($w, $h)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

$btnChangeKey = New-FlatButton "Change Hotkey" 30 185 150 34 $colPanel $colText
$form.Controls.Add($btnChangeKey)

$btnToggleArm = New-FlatButton "Disarm" 200 185 150 34 $colAccent ([System.Drawing.Color]::White)
$form.Controls.Add($btnToggleArm)

# history
$lblHistoryCaption = New-Object System.Windows.Forms.Label
$lblHistoryCaption.Text = "KILL HISTORY"
$lblHistoryCaption.Font = $fontSmall
$lblHistoryCaption.ForeColor = $colGray
$lblHistoryCaption.Location = New-Object System.Drawing.Point(30, 232)
$lblHistoryCaption.Size = New-Object System.Drawing.Size(320, 16)
$form.Controls.Add($lblHistoryCaption)

$lstHistory = New-Object System.Windows.Forms.ListBox
$lstHistory.Location = New-Object System.Drawing.Point(30, 252)
$lstHistory.Size = New-Object System.Drawing.Size(320, 130)
$lstHistory.BackColor = $colPanel
$lstHistory.ForeColor = $colText
$lstHistory.BorderStyle = "FixedSingle"
$lstHistory.Font = $fontSmall
$form.Controls.Add($lstHistory)

$btnHide = New-FlatButton "Hide to Tray" 30 396 150 34 $colPanel $colText
$form.Controls.Add($btnHide)

$btnExit = New-FlatButton "Exit" 200 396 150 34 $colPanel $colGray
$form.Controls.Add($btnExit)

# ---------- tray icon ----------
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Shield
$icon.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$showItem = $menu.Items.Add("Show")
$exitItem = $menu.Items.Add("Exit Panic Button")
$icon.ContextMenuStrip = $menu

# ---------- state ----------
$script:listening = $false
$script:reallyExiting = $false

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
        $modVal = Get-ModifierValue $script:cfg.Modifier
        $vkVal  = [uint32][System.Windows.Forms.Keys]::($script:cfg.Key)
        $ok = $form.RegisterGlobalHotkey($modVal, $vkVal)
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
    param($s, $e)
    if (-not $script:listening) { return }
    $modKeys = @('ControlKey','ShiftKey','Menu','LWin','RWin')
    if ($modKeys -contains $e.KeyCode.ToString()) { return }

    $mods = @()
    if ($e.Control) { $mods += 'Control' }
    if ($e.Alt)     { $mods += 'Alt' }
    if ($e.Shift)   { $mods += 'Shift' }
    $modStr = if ($mods.Count -gt 0) { $mods -join ', ' } else { 'None' }

    $script:cfg.Modifier = $modStr
    $script:cfg.Key = $e.KeyCode.ToString()
    Save-Config $script:cfg
    Apply-Hotkey

    $script:listening = $false
    $btnChangeKey.Enabled = $true
    $e.Handled = $true
    $e.SuppressKeyPress = $true
})

$btnToggleArm.Add_Click({
    $script:cfg.Armed = -not $script:cfg.Armed
    Save-Config $script:cfg
    Apply-Hotkey
})

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
    param($s, $e)
    if (-not $script:reallyExiting) {
        $e.Cancel = $true
        $form.Hide()
    }
})

# ---------- go ----------
Refresh-StatusUI
Apply-Hotkey
[System.Windows.Forms.Application]::Run($form)
