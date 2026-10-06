[CmdletBinding()]
param(
    [switch]$ConfigOnly,
    [switch]$NoUi,
    [switch]$RunSelection,
    [string]$RunSelected = '',
    [switch]$WeeklyUpdate,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Repository = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:HomeDirectory = [Environment]::GetFolderPath('UserProfile')
$script:LocalDirectory = Join-Path $script:HomeDirectory '.local'
$script:BinaryDirectory = Join-Path $script:LocalDirectory 'bin'
$script:OptDirectory = Join-Path $script:LocalDirectory 'opt'
$script:ConfigDirectory = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $script:HomeDirectory '.config' }
$script:StateDirectory = Join-Path $script:LocalDirectory 'state\terminal'
$script:SelectedTools = @()
$script:ProgressCurrent = 0
$script:ProgressTotal = 11
$script:NativeArchitecture = ''
$script:ScriptPath = $PSCommandPath
$script:SchedulerConfigured = $false

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch { }

$env:PATH = "$script:BinaryDirectory;$script:OptDirectory\go\bin;$script:OptDirectory\node;$script:HomeDirectory\.bun\bin;$script:HomeDirectory\.cargo\bin;$script:HomeDirectory\.opencode\bin;$script:OptDirectory\neovim\bin;$env:PATH"

function Write-Notice {
    param([string]$Message)
    Write-Host "`n› $Message"
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Warning $Message
}

function Stop-Install {
    param([string]$Message)
    throw $Message
}

function Write-ProgressStep {
    param([string]$Message)
    $script:ProgressCurrent++
    if ($RunSelection) {
        [Console]::Out.WriteLine("@@TERMINAL_PROGRESS`t{0}`t{1}`t{2}", $script:ProgressCurrent, $script:ProgressTotal, $Message)
    }
    else {
        Write-Notice $Message
    }
}

function Get-NativeArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($architecture) {
        '^(AMD64|x64)$' { return 'amd64' }
        '^(ARM64|AARCH64)$' { return 'arm64' }
        default { return $null }
    }
}

function Get-PowerShellExecutable {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    $powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($powershell) { return $powershell.Source }
    return $null
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ResolvedDirectoryPath {
    param([string]$Path)
    if (-not ('TerminalDotfilesPathResolver' -as [type])) {
        $definition = @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class TerminalDotfilesPathResolver {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint length, uint flags);

    public static string Resolve(string path) {
        using (SafeFileHandle handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            StringBuilder result = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandle(handle, result, (uint)result.Capacity, 0);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (length >= result.Capacity) throw new IOException("Resolved path is too long.");
            string resolved = result.ToString();
            if (resolved.StartsWith(@"\\?\") && !resolved.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) resolved = resolved.Substring(4);
            else if (resolved.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) resolved = @"\\" + resolved.Substring(8);
            return Path.GetFullPath(resolved).TrimEnd('\\');
        }
    }
}
'@
        Add-Type -TypeDefinition $definition
    }
    return [TerminalDotfilesPathResolver]::Resolve($Path)
}

function Test-Avx2Support {
    if (-not ('TerminalDotfilesProcessor' -as [type])) {
        $definition = 'using System.Runtime.InteropServices; public static class TerminalDotfilesProcessor { [DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int feature); }'
        Add-Type -TypeDefinition $definition
    }
    return [TerminalDotfilesProcessor]::IsProcessorFeaturePresent(40)
}

function Get-OpenCodeAssetPattern {
    if ($script:NativeArchitecture -eq 'arm64') { return 'opencode-windows-arm64.zip' }
    if (Test-Avx2Support) { return 'opencode-windows-x64.zip' }
    return 'opencode-windows-x64-baseline.zip'
}

function Get-BackupPath {
    param([string]$Path)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $candidate = "$Path.backup-$stamp"
    $suffix = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = "$Path.backup-$stamp-$suffix"
        $suffix++
    }
    return $candidate
}

function Backup-Path {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $backup = Get-BackupPath $Path
        Move-Item -LiteralPath $Path -Destination $backup
        Write-Notice "Preserved existing $Path at $backup"
    }
}

function Write-TextFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Set-ManagedCopy {
    param([string]$Source, [string]$Target)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { Stop-Install "Managed source is missing: $Source" }
    if ((Test-Path -LiteralPath $Target -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash) {
        Write-Notice "Already current: $Target"
        return
    }
    if (Test-Path -LiteralPath $Target) { Backup-Path $Target }
    $parent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target -Force
    Write-Notice "Copied managed config to $Target"
}

function Set-ManagedJunction {
    param([string]$Source, [string]$Target)
    $parent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    if (Test-Path -LiteralPath $Target) {
        $existing = Get-Item -LiteralPath $Target -Force
        if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            try {
                $resolvedExisting = Get-ResolvedDirectoryPath $Target
                $resolvedSource = Get-ResolvedDirectoryPath $Source
                if ($resolvedExisting.Equals($resolvedSource, [StringComparison]::OrdinalIgnoreCase)) {
                    Write-Notice "Already linked: $Target"
                    return
                }
            }
            catch { }
        }
        Backup-Path $Target
    }
    New-Item -ItemType Junction -Path $Target -Target $Source | Out-Null
    Write-Notice "Linked $Target to $Source"
}

function Add-UserPath {
    param([string[]]$Entries)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $paths = @()
    if ($userPath) { $paths = @($userPath -split ';' | Where-Object { $_ }) }
    foreach ($entry in $Entries) {
        $normalized = [System.IO.Path]::GetFullPath($entry).TrimEnd('\')
        if (-not (Test-Path -LiteralPath $entry)) { continue }
        $alreadyPresent = $false
        foreach ($current in $paths) {
            try {
                if ([System.IO.Path]::GetFullPath($current).TrimEnd('\').Equals($normalized, [StringComparison]::OrdinalIgnoreCase)) {
                    $alreadyPresent = $true
                    break
                }
            }
            catch { }
        }
        if (-not $alreadyPresent) { $paths = @($normalized) + $paths }
    }
    $newPath = $paths -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:Path = (($Entries | Where-Object { Test-Path -LiteralPath $_ }) -join ';') + ';' + $env:Path
}

function Get-GitHubReleaseAsset {
    param([string]$Repository, [string]$Pattern)
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers @{
        'User-Agent' = 'Mezuran-Terminal-installer'
        'Accept' = 'application/vnd.github+json'
    }
    $matches = @($release.assets | Where-Object { $_.name -like $Pattern })
    if ($matches.Count -ne 1) {
        Stop-Install "Expected one $Repository release asset matching '$Pattern'; found $($matches.Count)."
    }
    return $matches[0]
}

function Get-OfficialDownload {
    param([string]$Url, [string]$Destination)
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
}

function Install-ReleaseExecutable {
    param([string]$Name, [string]$Repository, [string]$Pattern, [switch]$ForceUpdate)
    if ((Test-Command "$Name.exe") -and -not $ForceUpdate) { Write-Notice "$Name is already available."; return }
    $asset = Get-GitHubReleaseAsset $Repository $Pattern
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $archive = Join-Path $temp $asset.name
        Get-OfficialDownload $asset.browser_download_url $archive
        Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $temp 'unpacked') -Force
        $executable = Get-ChildItem -LiteralPath (Join-Path $temp 'unpacked') -Filter "$Name.exe" -File -Recurse | Select-Object -First 1
        if (-not $executable) { Stop-Install "The $($asset.name) archive did not contain $Name.exe." }
        $target = Join-Path $script:BinaryDirectory "$Name.exe"
        if (Test-Path -LiteralPath $target) { Backup-Path $target }
        Copy-Item -LiteralPath $executable.FullName -Destination $target
        Write-Notice "Installed $Name to $target"
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-Neovim {
    if (Test-Command 'nvim.exe') { Write-Notice 'Neovim is already available.'; return }
    $assetName = if ($script:NativeArchitecture -eq 'arm64') { 'nvim-win-arm64.zip' } else { 'nvim-win64.zip' }
    $url = "https://github.com/neovim/neovim/releases/latest/download/$assetName"
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $archive = Join-Path $temp $assetName
        Get-OfficialDownload $url $archive
        $unpacked = Join-Path $temp 'unpacked'
        Expand-Archive -LiteralPath $archive -DestinationPath $unpacked -Force
        $executable = Get-ChildItem -LiteralPath $unpacked -Filter 'nvim.exe' -File -Recurse | Select-Object -First 1
        if (-not $executable) { Stop-Install "Neovim archive '$assetName' did not contain nvim.exe." }
        $source = $executable.Directory.FullName
        if ($executable.Directory.Name -eq 'bin') { $source = $executable.Directory.Parent.FullName }
        $target = Join-Path $script:OptDirectory 'neovim'
        if (Test-Path -LiteralPath $target) { Backup-Path $target }
        Move-Item -LiteralPath $source -Destination $target
        Write-Notice "Installed Neovim to $target"
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-CoreTools {
    $arch = if ($script:NativeArchitecture -eq 'arm64') { 'aarch64' } else { 'x86_64' }
    if (-not (Test-Command 'nvim.exe')) {
        Install-Neovim
    }
    Write-ProgressStep 'Neovim ready'
    Install-ReleaseExecutable 'starship' 'starship/starship' "starship-$arch-pc-windows-msvc.zip"
    Write-ProgressStep 'Starship ready'
    if ($script:NativeArchitecture -eq 'amd64' -or (Test-Command 'lsd.exe')) {
        Install-ReleaseExecutable 'lsd' 'lsd-rs/lsd' 'lsd-v*-x86_64-pc-windows-msvc.zip'
    }
    else { Write-WarningMessage 'lsd has no verified Windows arm64 release; skipping that core command.' }
    Write-ProgressStep 'lsd ready'
    Install-ReleaseExecutable 'bat' 'sharkdp/bat' "bat-v*-$arch-pc-windows-msvc.zip"
    Write-ProgressStep 'bat ready'
    if ($script:NativeArchitecture -eq 'amd64' -or (Test-Command 'glow.exe')) {
        Install-ReleaseExecutable 'glow' 'charmbracelet/glow' 'glow_*_Windows_x86_64.zip'
    }
    else { Write-WarningMessage 'Glow has no verified Windows arm64 release; skipping it.' }
    Write-ProgressStep 'Glow ready'
    if ($script:NativeArchitecture -eq 'amd64' -or (Test-Command 'pop.exe')) {
        Install-ReleaseExecutable 'pop' 'charmbracelet/pop' 'pop_*_Windows_x86_64.zip'
    }
    else { Write-WarningMessage 'Pop has no verified Windows arm64 release; skipping it.' }
    Write-ProgressStep 'Pop ready'
}

function Remove-JsonComments {
    param([string]$Text)
    $result = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $index = 0
    while ($index -lt $Text.Length) {
        $char = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
        if ($inString) {
            [void]$result.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            $index++
        }
        elseif ($char -eq '"') {
            $inString = $true
            [void]$result.Append($char)
            $index++
        }
        elseif ($char -eq '/' -and $next -eq '/') {
            $index += 2
            while ($index -lt $Text.Length -and $Text[$index] -ne "`n" -and $Text[$index] -ne "`r") { $index++ }
        }
        elseif ($char -eq '/' -and $next -eq '*') {
            $index += 2
            while ($index + 1 -lt $Text.Length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) {
                if ($Text[$index] -eq "`n" -or $Text[$index] -eq "`r") { [void]$result.Append($Text[$index]) }
                $index++
            }
            $index = [Math]::Min($Text.Length, $index + 2)
        }
        else {
            [void]$result.Append($char)
            $index++
        }
    }
    return $result.ToString()
}

function Remove-JsonTrailingCommas {
    param([string]$Text)
    $result = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        if ($inString) {
            [void]$result.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }
        if ($char -eq '"') {
            $inString = $true
            [void]$result.Append($char)
        }
        elseif ($char -eq ',') {
            $lookahead = $index + 1
            while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) { $lookahead++ }
            if ($lookahead -ge $Text.Length -or ($Text[$lookahead] -ne '}' -and $Text[$lookahead] -ne ']')) { [void]$result.Append($char) }
        }
        else { [void]$result.Append($char) }
    }
    return $result.ToString()
}

function Set-JsonProperties {
    param([string]$Path, [hashtable]$Values, [switch]$Jsonc)
    $config = [PSCustomObject]@{}
    if (Test-Path -LiteralPath $Path) {
        $text = [System.IO.File]::ReadAllText($Path)
        if ($Jsonc) { $text = Remove-JsonTrailingCommas (Remove-JsonComments $text) }
        $config = ConvertFrom-Json -InputObject $text
        if ($null -eq $config -or $config -isnot [PSCustomObject]) { Stop-Install "$Path must contain a JSON object." }
    }
    foreach ($key in $Values.Keys) {
        $config | Add-Member -MemberType NoteProperty -Name $key -Value $Values[$key] -Force
    }
    $content = ConvertTo-Json -InputObject $config -Depth 100
    if ((Test-Path -LiteralPath $Path) -and [System.IO.File]::ReadAllText($Path) -eq ($content + "`n")) { return }
    if (Test-Path -LiteralPath $Path) { Backup-Path $Path }
    Write-TextFile $Path ($content + "`n")
}

function Set-CodexThemeConfig {
    param([string]$Path)
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @(Get-Content -LiteralPath $Path) }
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[([^]]+)\]\s*(?:#.*)?$') {
            if ($Matches[1].Trim() -eq 'tui') {
                $sectionStart = $index
                for ($end = $index + 1; $end -lt $lines.Count; $end++) {
                    if ($lines[$end] -match '^\s*\[') { $sectionEnd = $end; break }
                }
                break
            }
        }
    }
    $setting = 'theme = "charm-dark"'
    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[-1].Trim()) { $lines += '' }
        $lines += '[tui]'
        $lines += $setting
    }
    else {
        $themeLine = -1
        for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
            if ($lines[$index] -match '^\s*theme\s*=') { $themeLine = $index; break }
        }
        if ($themeLine -ge 0) {
            $indent = [regex]::Match($lines[$themeLine], '^\s*').Value
            $lines[$themeLine] = $indent + $setting
        }
        else {
            $before = @($lines | Select-Object -First $sectionEnd)
            $after = @($lines | Select-Object -Skip $sectionEnd)
            $lines = $before + $setting + $after
        }
    }
    $content = ($lines -join "`n") + "`n"
    if ((Test-Path -LiteralPath $Path) -and [System.IO.File]::ReadAllText($Path) -eq $content) { return }
    if (Test-Path -LiteralPath $Path) { Backup-Path $Path }
    Write-TextFile $Path $content
}

function Install-ThemeAsset {
    param([string]$Source, [string]$Target)
    Set-ManagedCopy $Source $Target
}

function Install-ClaudeTheme {
    $config = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $script:HomeDirectory '.claude' }
    Install-ThemeAsset (Join-Path $script:Repository 'ai-themes\claude\charm-dark.json') (Join-Path $config 'themes\charm-dark.json')
    Set-JsonProperties (Join-Path $config 'settings.json') @{ theme = 'custom:charm-dark'; autoUpdatesChannel = 'stable' }
    Write-Notice 'Enabled the Charm Dark theme and stable channel for Claude Code.'
}

function Install-CodexTheme {
    $config = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $script:HomeDirectory '.codex' }
    Install-ThemeAsset (Join-Path $script:Repository 'ai-themes\codex\charm-dark.tmTheme') (Join-Path $config 'themes\charm-dark.tmTheme')
    Set-CodexThemeConfig (Join-Path $config 'config.toml')
    Write-Notice 'Enabled Charm Dark syntax highlighting for Codex.'
}

function Install-OpenCodeTheme {
    $xdg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { $script:ConfigDirectory }
    $config = Join-Path $xdg 'opencode'
    $cliSettings = Join-Path $config 'cli.json'
    $useCliSettings = Test-Path -LiteralPath $cliSettings
    if (-not $useCliSettings) {
        $openCodeCommand = Get-Command 'opencode.exe' -ErrorAction SilentlyContinue
        if ($openCodeCommand) {
            try {
                $versionOutput = (& $openCodeCommand.Source --version 2>$null | Out-String)
                if ($versionOutput -match '(?:^|\s)v?(\d+)\.') { $useCliSettings = [int]$Matches[1] -ge 2 }
            }
            catch { }
        }
    }
    if ($useCliSettings) {
        Install-ThemeAsset (Join-Path $script:Repository 'ai-themes\opencode\charm-v2.json') (Join-Path $config 'themes\charm-v2.json')
        Set-JsonProperties $cliSettings @{ theme = @{ name = 'charm-v2'; mode = 'dark' } }
    }
    else {
        Install-ThemeAsset (Join-Path $script:Repository 'ai-themes\opencode\charm.json') (Join-Path $config 'themes\charm.json')
        $settings = Join-Path $config 'tui.jsonc'
        if (-not (Test-Path -LiteralPath $settings)) { $settings = Join-Path $config 'tui.json' }
        Set-JsonProperties $settings @{ theme = 'charm' } -Jsonc
    }
    Write-Notice 'Enabled the Charm theme for OpenCode.'
}

function Invoke-OfficialPowerShellInstaller {
    param([string]$Url, [string[]]$Arguments = @())
    $scriptText = (Invoke-WebRequest -UseBasicParsing -Uri $Url).Content
    $installer = [scriptblock]::Create($scriptText)
    $addedWmiShim = $false
    if ($Url -like 'https://cursor.com/install*' -and -not (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) {
        function global:Get-WmiObject {
            param([Parameter(Position = 0)][string]$Class)
            Get-CimInstance -ClassName $Class
        }
        $addedWmiShim = $true
    }
    try {
        $global:LASTEXITCODE = 0
        & $installer @Arguments
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Stop-Install "Installer from $Url failed with exit code $LASTEXITCODE." }
    }
    finally {
        if ($addedWmiShim) { Remove-Item Function:\global:Get-WmiObject -ErrorAction SilentlyContinue }
    }
}

function Install-CodexCli {
    $previousNonInteractive = [Environment]::GetEnvironmentVariable('CODEX_NON_INTERACTIVE', 'Process')
    try {
        $env:CODEX_NON_INTERACTIVE = '1'
        Invoke-OfficialPowerShellInstaller 'https://chatgpt.com/codex/install.ps1'
    }
    finally {
        if ($null -eq $previousNonInteractive) { Remove-Item Env:CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue }
        else { $env:CODEX_NON_INTERACTIVE = $previousNonInteractive }
    }
}

function Install-GoStable {
    $releases = Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json'
    $release = $releases | Where-Object { $_.stable } | Select-Object -First 1
    if (-not $release) { Stop-Install 'Could not resolve the latest stable Go release.' }
    $currentGo = Join-Path $script:OptDirectory 'go\bin\go.exe'
    if (Test-Path -LiteralPath $currentGo) {
        $currentVersion = & $currentGo version 2>$null
        if ($currentVersion -like "*$($release.version)*") { Write-Notice "Go $($release.version) is already current."; return }
    }
    $arch = if ($script:NativeArchitecture -eq 'arm64') { 'arm64' } else { 'amd64' }
    $asset = $release.files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq $arch -and $_.kind -eq 'archive' } | Select-Object -First 1
    if (-not $asset) { Stop-Install "Go does not publish a stable Windows $arch archive." }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $archive = Join-Path $temp $asset.filename
        Get-OfficialDownload "https://go.dev/dl/$($asset.filename)" $archive
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $asset.sha256) { Stop-Install 'Go archive checksum verification failed.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force
        $target = Join-Path $script:OptDirectory 'go'
        if (Test-Path -LiteralPath $target) { Backup-Path $target }
        Move-Item -LiteralPath (Join-Path $temp 'go') -Destination $target
        Write-Notice "Installed $($release.version) to $target"
    }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Install-NodeLts {
    $releases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
    $release = $releases | Where-Object { $_.lts } | Select-Object -First 1
    if (-not $release) { Stop-Install 'Could not resolve the latest Node.js LTS release.' }
    $currentNode = Join-Path $script:OptDirectory 'node\node.exe'
    if (Test-Path -LiteralPath $currentNode) {
        $currentVersion = & $currentNode --version 2>$null
        if ($currentVersion.Trim() -eq $release.version) { Write-Notice "Node.js $($release.version) LTS is already current."; return }
    }
    $arch = if ($script:NativeArchitecture -eq 'arm64') { 'arm64' } else { 'x64' }
    $assetKind = "win-$arch-zip"
    if ($release.files -notcontains $assetKind) { Stop-Install "Node.js has no stable LTS Windows $arch archive." }
    $filename = "node-$($release.version)-win-$arch.zip"
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $sums = (Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/$($release.version)/SHASUMS256.txt").Content
        $sumLine = $sums -split "`n" | Where-Object { $_ -match "^([0-9a-fA-F]{64})\s+$([regex]::Escape($filename))\s*$" } | Select-Object -First 1
        if (-not $sumLine) { Stop-Install 'Could not read the Node.js archive checksum.' }
        $expected = [regex]::Match($sumLine, '^([0-9a-fA-F]{64})').Groups[1].Value.ToLowerInvariant()
        $archive = Join-Path $temp $filename
        Get-OfficialDownload "https://nodejs.org/dist/$($release.version)/$filename" $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
            Stop-Install 'Node.js archive checksum verification failed.'
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force
        $source = Join-Path $temp "node-$($release.version)-win-$arch"
        $target = Join-Path $script:OptDirectory 'node'
        if (Test-Path -LiteralPath $target) { Backup-Path $target }
        Move-Item -LiteralPath $source -Destination $target
        Write-Notice "Installed Node.js $($release.version) (LTS) to $target"
    }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Install-SelectedTool {
    param([string]$Tool)
    switch ($Tool) {
        'rust' {
            if (Test-Command 'rustup.exe') {
                & rustup.exe toolchain install stable --profile minimal
                if ($LASTEXITCODE -ne 0) { Stop-Install 'rustup could not install the stable toolchain.' }
                & rustup.exe update stable
                if ($LASTEXITCODE -ne 0) { Stop-Install 'rustup could not update the stable toolchain.' }
                break
            }
            $rustArch = if ($script:NativeArchitecture -eq 'arm64') { 'aarch64' } else { 'x86_64' }
            $installer = Join-Path ([IO.Path]::GetTempPath()) ("rustup-init-{0}.exe" -f [Guid]::NewGuid().ToString('N'))
            try {
                Get-OfficialDownload "https://static.rust-lang.org/rustup/dist/$rustArch-pc-windows-msvc/rustup-init.exe" $installer
                & $installer -y --default-toolchain stable --profile minimal --no-modify-path
                if ($LASTEXITCODE -ne 0) { Stop-Install 'rustup installer failed.' }
            }
            finally { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
        }
        'go' { Install-GoStable }
        'bun' { Invoke-OfficialPowerShellInstaller 'https://bun.com/install.ps1' }
        'nodejs' { Install-NodeLts }
        'uv' {
            $env:UV_INSTALL_DIR = $script:BinaryDirectory
            $env:UV_NO_MODIFY_PATH = '1'
            Invoke-OfficialPowerShellInstaller 'https://astral.sh/uv/install.ps1'
        }
        'python' {
            $uvPath = Join-Path $script:BinaryDirectory 'uv.exe'
            if (-not (Test-Path -LiteralPath $uvPath)) { Install-SelectedTool 'uv' }
            & $uvPath python install --default
            if ($LASTEXITCODE -ne 0) { Stop-Install 'uv could not install the latest stable Python.' }
            & $uvPath python upgrade
            if ($LASTEXITCODE -ne 0) { Stop-Install 'uv could not update Python.' }
        }
        'composer' {
            $php = Get-Command php.exe -ErrorAction SilentlyContinue
            if (-not $php) { Stop-Install 'Composer requires PHP; php.exe is not available on PATH.' }
            $setup = Join-Path ([IO.Path]::GetTempPath()) ("composer-setup-{0}.php" -f [Guid]::NewGuid().ToString('N'))
            try {
                Get-OfficialDownload 'https://getcomposer.org/installer' $setup
                & $php.Source $setup "--install-dir=$script:BinaryDirectory" '--filename=composer.phar'
                if ($LASTEXITCODE -ne 0) { Stop-Install 'Composer installer failed.' }
                Write-TextFile (Join-Path $script:BinaryDirectory 'composer.cmd') ('@echo off' + "`r`n" + 'php "%~dp0composer.phar" %*' + "`r`n")
                & $php.Source (Join-Path $script:BinaryDirectory 'composer.phar') self-update --stable --no-interaction
                if ($LASTEXITCODE -ne 0) { Stop-Install 'Composer could not update to the stable channel.' }
            }
            finally { Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue }
        }
        'php' { }
        'clang' { }
        'gcc' { }
        'codex' {
            Install-CodexCli
            Install-CodexTheme
        }
        'opencode' {
            $pattern = Get-OpenCodeAssetPattern
            Install-ReleaseExecutable 'opencode' 'anomalyco/opencode' $pattern
            Install-OpenCodeTheme
        }
        'claude' {
            Invoke-OfficialPowerShellInstaller 'https://claude.ai/install.ps1' @('stable')
            Install-ClaudeTheme
        }
        'cursor' {
            $cursorRoot = Join-Path $env:LOCALAPPDATA 'cursor-agent'
            if (Test-Command 'agent.exe') {
                Write-Notice 'Cursor CLI is already available; its installer manages updates automatically.'
                break
            }
            if (Test-Path -LiteralPath $cursorRoot) { Backup-Path $cursorRoot }
            Invoke-OfficialPowerShellInstaller 'https://cursor.com/install?win32=true'
            Write-Notice 'Cursor CLI will use the generated PowerShell profile Charm dark-mode hint.'
        }
        default { Stop-Install "Unknown selected tool: $Tool" }
    }
}

function Get-UnsupportedToolReason {
    param([string]$Tool)
    switch ($Tool) {
        'rust' { return '' }
        'go' { return '' }
        'bun' { return '' }
        'nodejs' { return '' }
        'uv' { return '' }
        'python' { return '' }
        'codex' { return '' }
        'opencode' { return '' }
        'claude' { return '' }
        'cursor' {
            if ($script:NativeArchitecture -in @('amd64', 'arm64')) { return '' }
            return "Cursor CLI does not support Windows $script:NativeArchitecture"
        }
        'php' {
            if (Test-Command 'php.exe') { return '' }
            return 'requires an existing PHP installation; automatic Windows PHP installation is not configured'
        }
        'composer' {
            if (Test-Command 'php.exe') { return '' }
            return 'requires PHP; install PHP first or add php.exe to PATH'
        }
        'clang' {
            if (Test-Command 'clang.exe') { return '' }
            return 'requires an existing LLVM/Clang installation on Windows'
        }
        'gcc' {
            if (Test-Command 'gcc.exe') { return '' }
            return 'requires an existing GCC/MinGW installation on Windows'
        }
        default { return 'not supported on Windows' }
    }
}

function Assert-SelectedToolsSupported {
    foreach ($tool in $script:SelectedTools) {
        $reason = Get-UnsupportedToolReason $tool
        if ($reason) { Stop-Install "Selected tool '$tool' is unavailable: $reason" }
    }
}

function Update-SelectedTools {
    $selectionFile = Join-Path $script:ConfigDirectory 'terminal\selected-tools'
    if (-not (Test-Path -LiteralPath $selectionFile)) { Write-Notice 'No selected tools are recorded; nothing to update.'; return }
    $tools = @(Get-Content -LiteralPath $selectionFile | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    if ($tools.Count -eq 0) { Write-Notice 'No optional tools were selected; nothing to update.'; return }
    foreach ($tool in $tools) {
        Write-Notice "Checking stable updates for $tool…"
        switch ($tool) {
            'rust' { & rustup.exe update stable; if ($LASTEXITCODE -ne 0) { Stop-Install 'rustup update failed.' } }
            'go' { Install-GoStable }
            'bun' { & (Join-Path $script:HomeDirectory '.bun\bin\bun.exe') upgrade --stable; if ($LASTEXITCODE -ne 0) { Stop-Install 'Bun update failed.' } }
            'nodejs' { Install-NodeLts }
            'uv' { & (Join-Path $script:BinaryDirectory 'uv.exe') self update; if ($LASTEXITCODE -ne 0) { Stop-Install 'uv update failed.' } }
            'python' {
                & (Join-Path $script:BinaryDirectory 'uv.exe') python install --default
                if ($LASTEXITCODE -ne 0) { Stop-Install 'Python update failed.' }
                & (Join-Path $script:BinaryDirectory 'uv.exe') python upgrade
                if ($LASTEXITCODE -ne 0) { Stop-Install 'Python update failed.' }
            }
            'composer' {
                $php = Get-Command php.exe -ErrorAction SilentlyContinue
                if ($php -and (Test-Path (Join-Path $script:BinaryDirectory 'composer.phar'))) {
                    & $php.Source (Join-Path $script:BinaryDirectory 'composer.phar') self-update --stable --no-interaction
                    if ($LASTEXITCODE -ne 0) { Stop-Install 'Composer update failed.' }
                }
            }
            { $_ -in 'php', 'clang', 'gcc' } { Write-WarningMessage "$tool is managed outside this installer on Windows; no automatic update was run." }
            'codex' { Install-CodexCli }
            'opencode' {
                $pattern = Get-OpenCodeAssetPattern
                Install-ReleaseExecutable 'opencode' 'anomalyco/opencode' $pattern -ForceUpdate
            }
            'claude' { & (Get-Command claude.exe -ErrorAction Stop).Source update; if ($LASTEXITCODE -ne 0) { Stop-Install 'Claude Code update failed.' } }
            'cursor' { Write-Notice 'Cursor CLI updates itself automatically.' }
            default { Write-WarningMessage "Ignoring unknown selected tool '$tool'." }
        }
    }
    Write-Notice 'Selected tool updates are complete.'
}

function Install-WeeklyTask {
    $taskName = 'Terminal Weekly Stable Updates'
    $powershell = Get-PowerShellExecutable
    if (-not $powershell) { Write-WarningMessage 'Could not find PowerShell to register the weekly updater.'; return }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:ScriptPath`" -WeeklyUpdate"
    $taskCommand = "`"$powershell`" $arguments"
    & schtasks.exe /Create /SC WEEKLY /D SUN /TN $taskName /TR $taskCommand /ST 09:00 /F /RL LIMITED 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $script:SchedulerConfigured = $true
        Write-Notice 'Registered the weekly user-level Windows update task.'
    }
    else { Write-WarningMessage "Could not register the weekly task; run '$script:ScriptPath -WeeklyUpdate' manually." }
}

function Set-PowerShellProfile {
    param([string]$ProfilePath = $PROFILE)
    $profilePath = $ProfilePath
    $marker = '# >>> Terminal dotfiles >>>'
    $endMarker = '# <<< Terminal dotfiles <<<'
    $existing = if (Test-Path -LiteralPath $profilePath) { [System.IO.File]::ReadAllText($profilePath) } else { '' }
    $pattern = '(?ms)^' + [regex]::Escape($marker) + '.*?^' + [regex]::Escape($endMarker) + '\s*'
    $preserved = [regex]::Replace($existing, $pattern, '').TrimEnd()
    $block = @"
$marker
`$env:PATH = "`$HOME\.local\opt\go\bin;`$HOME\.local\opt\node;`$HOME\.bun\bin;`$HOME\.cargo\bin;`$HOME\.opencode\bin;`$HOME\.local\bin;`$HOME\.local\opt\neovim\bin;`$env:PATH"
if (-not `$env:XDG_CONFIG_HOME) { `$env:XDG_CONFIG_HOME = "`$HOME\.config" }
`$env:STARSHIP_CONFIG = Join-Path `$env:XDG_CONFIG_HOME 'starship.toml'
`$env:COLORFGBG = '15;0'
if (Get-Command lsd.exe -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -ErrorAction SilentlyContinue
    function global:ls { & lsd.exe -AFL --group-dirs=first @args }
}
if (Get-Command bat.exe -ErrorAction SilentlyContinue) {
    Remove-Item Alias:cat -ErrorAction SilentlyContinue
    function global:cat { & bat.exe @args }
}
if (Get-Command starship.exe -ErrorAction SilentlyContinue) { Invoke-Expression (& starship.exe init powershell) }
$endMarker
"@
    $content = if ($preserved) { $preserved + "`r`n`r`n" + $block.Trim() + "`r`n" } else { $block.Trim() + "`r`n" }
    if ($existing -ne $content) {
        if (Test-Path -LiteralPath $profilePath) { Backup-Path $profilePath }
        Write-TextFile $profilePath $content
        Write-Notice "Updated PowerShell profile $profilePath"
    }
    else { Write-Notice 'PowerShell profile is already configured.' }
}

function Install-Configuration {
    $nvimConfig = Join-Path $script:ConfigDirectory 'nvim'
    Set-ManagedJunction (Join-Path $script:Repository 'nvim') $nvimConfig
    Set-ManagedCopy (Join-Path $script:Repository 'starship.toml') (Join-Path $script:ConfigDirectory 'starship.toml')
    if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = $script:ConfigDirectory }
    $env:STARSHIP_CONFIG = Join-Path $script:ConfigDirectory 'starship.toml'
    $env:COLORFGBG = '15;0'
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(
        $PROFILE,
        (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    ) | Select-Object -Unique
    foreach ($profilePath in $profiles) { Set-PowerShellProfile $profilePath }
    $paths = @(
        $script:BinaryDirectory,
        (Join-Path $script:OptDirectory 'go\bin'),
        (Join-Path $script:OptDirectory 'node'),
        (Join-Path $script:HomeDirectory '.bun\bin'),
        (Join-Path $script:HomeDirectory '.cargo\bin'),
        (Join-Path $script:HomeDirectory '.opencode\bin'),
        (Join-Path $script:OptDirectory 'neovim\bin')
    )
    Add-UserPath $paths
}

function Invoke-Installation {
    if ($Help) {
        @'
Usage: install.ps1 [-ConfigOnly] [-NoUi] [-Help]
  -ConfigOnly  Link the included configs and configure the PowerShell profile only.
  -NoUi        Install the core setup without selecting optional tools.
'@ | Write-Host
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $script:Repository 'starship.toml')) -or
        -not (Test-Path -LiteralPath (Join-Path $script:Repository 'nvim') -PathType Container)) {
        Stop-Install 'Run this script from a complete Terminal repository checkout.'
    }
    if ($env:OS -ne 'Windows_NT') { Stop-Install 'install.ps1 supports native Windows only. Use install.sh on Linux, macOS, WSL, or Termux.' }
    $script:NativeArchitecture = Get-NativeArchitecture
    if (-not $script:NativeArchitecture -and -not $ConfigOnly) { Stop-Install "Native Windows architecture '$env:PROCESSOR_ARCHITECTURE' is not supported." }
    if ($WeeklyUpdate) { Update-SelectedTools; return }

    New-Item -ItemType Directory -Path $script:BinaryDirectory, $script:OptDirectory, $script:ConfigDirectory -Force | Out-Null
    Add-UserPath @($script:BinaryDirectory, (Join-Path $script:OptDirectory 'neovim\bin'))

    if (-not $ConfigOnly -and -not $RunSelection -and -not $NoUi -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        $tuiPath = Join-Path ([IO.Path]::GetTempPath()) ("terminal-tui-{0}.exe" -f [Guid]::NewGuid().ToString('N'))
        $assetName = "terminal-tui-windows-$script:NativeArchitecture.exe"
        $checksumsPath = "$tuiPath.SHA256SUMS"
        try {
            Get-OfficialDownload 'https://github.com/Mezuran/Terminal/releases/latest/download/SHA256SUMS' $checksumsPath
            Get-OfficialDownload "https://github.com/Mezuran/Terminal/releases/latest/download/$assetName" $tuiPath
            $line = Get-Content -LiteralPath $checksumsPath | Where-Object { $_ -match "\s\*?$([regex]::Escape($assetName))$" } | Select-Object -First 1
            if (-not $line) { Stop-Install 'The published Windows selector checksum is missing.' }
            $expected = [regex]::Match($line, '^([a-fA-F0-9]{64})').Groups[1].Value
            $actual = (Get-FileHash -LiteralPath $tuiPath -Algorithm SHA256).Hash
            if (-not $expected -or $actual -ne $expected) { Stop-Install 'The installer UI checksum verification failed.' }
            & $tuiPath $script:ScriptPath
            if ($LASTEXITCODE -ne 0) { Stop-Install 'The installer UI did not complete successfully.' }
            return
        }
        catch { Stop-Install "Could not start the Windows selector: $($_.Exception.Message). Use -NoUi to install the compatible core only." }
        finally {
            Remove-Item -LiteralPath $tuiPath, $checksumsPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($RunSelection) {
        $script:SelectedTools = @($RunSelected -split ',' | Where-Object { $_ })
        $script:ProgressTotal = 11 + $script:SelectedTools.Count
        Assert-SelectedToolsSupported
    }
    elseif (-not $ConfigOnly -and -not $NoUi) {
        Write-WarningMessage 'No interactive console detected; installing the core only. Run install.ps1 from PowerShell to select optional tools.'
    }

    if (-not $ConfigOnly) {
        Install-CoreTools
        foreach ($tool in $script:SelectedTools) {
            Write-Notice "Installing stable $tool…"
            Install-SelectedTool $tool
            Write-ProgressStep "Installed $tool"
        }
        $selectionFile = Join-Path $script:ConfigDirectory 'terminal\selected-tools'
        New-Item -ItemType Directory -Path (Split-Path -Parent $selectionFile) -Force | Out-Null
        Write-TextFile $selectionFile (($script:SelectedTools -join "`n") + "`n")
    }

    Install-Configuration
    if (-not $ConfigOnly) {
        Write-ProgressStep 'Neovim config linked'
        Write-ProgressStep 'Starship config linked'
        Write-ProgressStep 'Shell startup configured'
        Install-WeeklyTask
        if ($script:SchedulerConfigured) { Write-ProgressStep 'Weekly updater configured' }
        else { Write-ProgressStep 'Manual updater available' }
        $nvim = Get-Command 'nvim.exe' -ErrorAction SilentlyContinue
        if ($nvim) {
            Write-Notice 'Bootstrapping NvChad and locked plugins; the first run may take a while…'
            & $nvim.Source --headless +qa
            if ($LASTEXITCODE -ne 0) { Stop-Install 'Neovim setup failed. Re-run install.ps1 after resolving the error.' }
        }
        Write-ProgressStep 'NvChad ready'
    }

    Write-Host "`nTerminal setup is ready."
    Write-Host "  Config directory: $script:ConfigDirectory"
    Write-Host "  User-local binaries: $script:BinaryDirectory"
    Write-Host 'Open a new PowerShell window to load aliases and the Charm Starship prompt.'
    if (-not $ConfigOnly) {
        if ($script:SchedulerConfigured) { Write-Notice 'Selected tools are recorded in the terminal config directory and update weekly.' }
        else { Write-Notice 'Selected tools are recorded; run install.ps1 -WeeklyUpdate to check for updates.' }
    }
}

if ($WeeklyUpdate) {
    New-Item -ItemType Directory -Path $script:StateDirectory -Force | Out-Null
    try { Start-Transcript -Path (Join-Path $script:StateDirectory 'updates.log') -Append | Out-Null } catch { }
}
try {
    Invoke-Installation
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($WeeklyUpdate) { try { Stop-Transcript | Out-Null } catch { } }
}
