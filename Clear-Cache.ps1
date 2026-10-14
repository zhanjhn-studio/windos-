# ============================================================
#  Windows 一键缓存清理工具
#  文件：Clear-Cache.ps1
#  用法：双击同目录下的 Clear-Cache.bat 即可启动（自动请求管理员权限）
# ============================================================

# ---------- 自提权为管理员 ----------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs
    } catch { }
    exit
}

# ---------- 加载 GUI 组件 ----------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- 内存清理底层接口（清理待机内存 + 清空工作集） ----------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class MemoryPurger
{
    [DllImport("ntdll.dll")]
    private static extern uint NtSetSystemInformation(int InfoClass, ref int Info, int Length);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    private static extern bool GlobalMemoryStatusEx(MEMORYSTATUSEX buffer);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct TOKEN_PRIVILEGES { public int PrivilegeCount; public long Luid; public uint Attributes; }

    [StructLayout(LayoutKind.Sequential)]
    public class MEMORYSTATUSEX
    {
        public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    private const int SystemMemoryListInformation = 80;
    private const int MemoryPurgeStandbyList = 4;
    private const int MemoryEmptyWorkingSets = 5;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x20;
    private const uint TOKEN_QUERY = 0x8;
    private const uint SE_PRIVILEGE_ENABLED = 0x2;

    // 启用 SeProfileSingleProcessPrivilege（清理待机内存所需）
    public static uint EnablePrivilege()
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token)) return 1;
        long luid;
        if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid)) return 2;
        TOKEN_PRIVILEGES tp;
        tp.PrivilegeCount = 1;
        tp.Luid = luid;
        tp.Attributes = SE_PRIVILEGE_ENABLED;
        if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return 3;
        return 0;
    }

    // 清理待机内存（Standby List）
    public static uint PurgeStandby()
    {
        int cmd = MemoryPurgeStandbyList;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, sizeof(int));
    }

    // 清空各进程工作集（Working Set）
    public static uint EmptyWorkingSets()
    {
        int cmd = MemoryEmptyWorkingSets;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, sizeof(int));
    }

    public static ulong GetAvailableBytes()
    {
        MEMORYSTATUSEX ms = new MEMORYSTATUSEX();
        GlobalMemoryStatusEx(ms);
        return ms.ullAvailPhys;
    }
}
"@

# ---------- 工具函数 ----------
function Get-DirSize {
    param([string[]]$Paths)
    $sum = 0.0
    foreach ($p in $Paths) {
        if ($p) {
            $sum += (Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        }
    }
    return $sum
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} 字节" -f $Bytes)
}

# ---------- 清理项定义 ----------
# Name：名称；Desc：说明；Safe：是否默认勾选；Action：清理脚本块（返回释放字节数，-1 表示无文件统计）
$script:cleaners = @(
    @{
        Name   = "用户临时文件"
        Desc   = "清理当前用户 %TEMP% 目录中的临时文件"
        Safe   = $true
        Action = {
            $s = Get-DirSize $env:TEMP
            Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            return $s
        }
    },
    @{
        Name   = "系统临时文件"
        Desc   = "清理 C:\Windows\Temp 中的系统临时文件"
        Safe   = $true
        Action = {
            $p = "$env:WINDIR\Temp"
            $s = Get-DirSize $p
            Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            return $s
        }
    },
    @{
        Name   = "DNS 解析缓存"
        Desc   = "刷新 DNS 缓存（ipconfig /flushdns），可解决部分网页无法访问的问题"
        Safe   = $true
        Action = {
            ipconfig /flushdns | Out-Null
            return -1
        }
    },
    @{
        Name   = "内存缓存"
        Desc   = "清理待机内存与工作集，释放被占用的物理内存（对正在运行的程序无影响）"
        Safe   = $true
        Action = {
            $before = [MemoryPurger]::GetAvailableBytes()
            [void][MemoryPurger]::EnablePrivilege()
            $r1 = [MemoryPurger]::PurgeStandby()
            $r2 = [MemoryPurger]::EmptyWorkingSets()
            Start-Sleep -Milliseconds 800
            $after = [MemoryPurger]::GetAvailableBytes()
            if ($r1 -ne 0 -and $r2 -ne 0) { return -1 }
            $freed = [double]($after - $before)
            if ($freed -lt 0) { $freed = 0 }
            return $freed
        }
    },
    @{
        Name   = "缩略图与图标缓存"
        Desc   = "清理缩略图/图标缓存（会短暂重启资源管理器，桌面会闪一下属正常现象）"
        Safe   = $true
        Action = {
            $paths = @(
                "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
                "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
                "$env:LOCALAPPDATA\IconCache.db"
            )
            $s = Get-DirSize $paths
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            foreach ($pt in $paths) {
                Remove-Item -Path $pt -Force -ErrorAction SilentlyContinue
            }
            Start-Process explorer
            return $s
        }
    },
    @{
        Name   = "Windows 更新缓存"
        Desc   = "清理 Windows 更新下载缓存，下次检查更新时可能需要重新下载"
        Safe   = $false
        Action = {
            $p = "$env:WINDIR\SoftwareDistribution\Download"
            $s = Get-DirSize $p
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service wuauserv -ErrorAction SilentlyContinue
            return $s
        }
    },
    @{
        Name   = "浏览器缓存"
        Desc   = "清理 Edge 与 Chrome 的缓存（不影响书签、密码、历史记录）"
        Safe   = $true
        Action = {
            $paths = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
            )
            $s = Get-DirSize $paths
            foreach ($pt in $paths) {
                Get-ChildItem -Path $pt -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $s
        }
    },
    @{
        Name   = "预取文件 (Prefetch)"
        Desc   = "清理 C:\Windows\Prefetch，可能略微增加下次启动程序的时间，一般不建议"
        Safe   = $false
        Action = {
            $p = "$env:WINDIR\Prefetch"
            $s = Get-DirSize $p
            Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            return $s
        }
    },
    @{
        Name   = "回收站"
        Desc   = "彻底清空回收站（不可恢复，请确认回收站内没有需要保留的文件）"
        Safe   = $false
        Action = {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            return -1
        }
    }
)

# ---------- 构建界面 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows 一键缓存清理工具"
$form.Size = New-Object System.Drawing.Size(580, 640)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei", 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "请勾选要清理的项目"
$lblTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblTitle.AutoSize = $true
$lblTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

$clb = New-Object System.Windows.Forms.CheckedListBox
$clb.Location = New-Object System.Drawing.Point(16, 40)
$clb.Size = New-Object System.Drawing.Size(544, 290)
$clb.CheckOnClick = $true
$clb.IntegralHeight = $false
$clb.Font = New-Object System.Drawing.Font("Microsoft YaHei", 9)
foreach ($c in $script:cleaners) {
    [void]$clb.Items.Add(("{0}  ——  {1}" -f $c.Name, $c.Desc))
    $clb.SetItemChecked($clb.Items.Count - 1, $c.Safe)
}
$form.Controls.Add($clb)

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = "全选"
$btnAll.Location = New-Object System.Drawing.Point(16, 340)
$btnAll.Size = New-Object System.Drawing.Size(100, 32)
$form.Controls.Add($btnAll)

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = "取消全选"
$btnNone.Location = New-Object System.Drawing.Point(126, 340)
$btnNone.Size = New-Object System.Drawing.Size(100, 32)
$form.Controls.Add($btnNone)

$btnClean = New-Object System.Windows.Forms.Button
$btnClean.Text = "开始清理"
$btnClean.Location = New-Object System.Drawing.Point(16, 382)
$btnClean.Size = New-Object System.Drawing.Size(544, 46)
$btnClean.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$btnClean.ForeColor = [System.Drawing.Color]::White
$btnClean.Font = New-Object System.Drawing.Font("Microsoft YaHei", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnClean)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "就绪"
$lblStatus.Location = New-Object System.Drawing.Point(16, 436)
$lblStatus.AutoSize = $true
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(16, 460)
$progress.Size = New-Object System.Drawing.Size(544, 16)
$form.Controls.Add($progress)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(16, 486)
$txtLog.Size = New-Object System.Drawing.Size(544, 104)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$form.Controls.Add($txtLog)

$script:results = New-Object System.Collections.ArrayList

# ---------- 事件 ----------
$btnAll.Add_Click({
    for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) }
})

$btnNone.Add_Click({
    for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) }
})

$btnClean.Add_Click({
    $checked = @()
    for ($i = 0; $i -lt $clb.Items.Count; $i++) {
        if ($clb.GetItemChecked($i)) { $checked += $i }
    }
    if ($checked.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show("请至少勾选一个要清理的项目。", "提示", "OK", "Information")
        return
    }

    $names = ($checked | ForEach-Object { $script:cleaners[$_].Name }) -join "、"
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        ("即将清理以下项目：" + [Environment]::NewLine + $names + [Environment]::NewLine + [Environment]::NewLine + "是否继续？"),
        "确认清理", "YesNo", "Warning")
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $btnClean.Enabled = $false
    $btnAll.Enabled = $false
    $btnNone.Enabled = $false
    $clb.Enabled = $false
    $script:results.Clear()
    $txtLog.Clear()

    $script:totalFreed = 0.0
    $progress.Minimum = 0
    $progress.Maximum = $checked.Count
    $progress.Value = 0

    $idx = 0
    foreach ($i in $checked) {
        $c = $script:cleaners[$i]
        $lblStatus.Text = "正在清理：" + $c.Name + " ..."
        [System.Windows.Forms.Application]::DoEvents()

        $freed = -1
        try {
            $freed = & $c.Action
        } catch {
            $freed = -1
        }

        if ($freed -ge 0) {
            $script:totalFreed += $freed
            [void]$script:results.Add(("{0}：已释放 {1}" -f $c.Name, (Format-Size $freed)))
        } else {
            [void]$script:results.Add(("{0}：已完成" -f $c.Name))
        }

        $idx++
        $progress.Value = $idx
        $txtLog.Text = ($script:results -join [Environment]::NewLine)
        [System.Windows.Forms.Application]::DoEvents()
    }

    $lblStatus.Text = "清理完成！共释放 " + (Format-Size $script:totalFreed)
    $txtLog.Text = ($script:results -join [Environment]::NewLine)

    $btnClean.Enabled = $true
    $btnAll.Enabled = $true
    $btnNone.Enabled = $true
    $clb.Enabled = $true
})

# ---------- 显示 ----------
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
