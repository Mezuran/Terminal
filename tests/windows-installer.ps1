$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\install.ps1') -Help

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ("terminal-installer-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null

try {
    $jsoncPath = Join-Path $testDirectory 'tui.jsonc'
    [IO.File]::WriteAllText($jsoncPath, @'
// Preserve comments and unrelated values semantically when applying the theme.
{
  "existing": "keep", // an inline comment
  "url": "https://example.test/a//b",
}
'@)
    Set-JsonProperties $jsoncPath @{ theme = 'charm' } -Jsonc
    $json = ConvertFrom-Json ([IO.File]::ReadAllText($jsoncPath))
    Assert-Condition ($json.theme -eq 'charm' -and $json.existing -eq 'keep' -and $json.url -eq 'https://example.test/a//b') 'OpenCode JSONC merge lost an existing value.'
    $jsonBackups = @(Get-ChildItem -LiteralPath $testDirectory -Filter 'tui.jsonc.backup-*')
    Set-JsonProperties $jsoncPath @{ theme = 'charm' } -Jsonc
    Assert-Condition (@(Get-ChildItem -LiteralPath $testDirectory -Filter 'tui.jsonc.backup-*').Count -eq $jsonBackups.Count) 'OpenCode theme merge was not idempotent.'

    $cliJsonPath = Join-Path $testDirectory 'cli.json'
    [IO.File]::WriteAllText($cliJsonPath, '{"existing":"keep","theme":{"name":"other","mode":"light"}}')
    Set-JsonProperties $cliJsonPath @{ theme = @{ name = 'charm-v2'; mode = 'dark' } }
    $cliJson = ConvertFrom-Json ([IO.File]::ReadAllText($cliJsonPath))
    Assert-Condition ($cliJson.theme.name -eq 'charm-v2' -and $cliJson.theme.mode -eq 'dark' -and $cliJson.existing -eq 'keep') 'OpenCode CLI theme merge did not preserve existing settings or set the v2 theme.'
    $cliBackups = @(Get-ChildItem -LiteralPath $testDirectory -Filter 'cli.json.backup-*')
    Set-JsonProperties $cliJsonPath @{ theme = @{ name = 'charm-v2'; mode = 'dark' } }
    Assert-Condition (@(Get-ChildItem -LiteralPath $testDirectory -Filter 'cli.json.backup-*').Count -eq $cliBackups.Count) 'OpenCode CLI theme merge was not idempotent.'

    $previousXdgConfig = $env:XDG_CONFIG_HOME
    $env:XDG_CONFIG_HOME = Join-Path $testDirectory 'opencode-config'
    try {
        Install-OpenCodeTheme
        $openCodeDirectory = Join-Path $env:XDG_CONFIG_HOME 'opencode'
        $legacySettings = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $openCodeDirectory 'tui.json')))
        Assert-Condition ($legacySettings.theme -eq 'charm' -and (Test-Path -LiteralPath (Join-Path $openCodeDirectory 'themes\charm.json'))) 'OpenCode legacy theme setup did not install and select Charm.'
        [IO.File]::WriteAllText((Join-Path $openCodeDirectory 'cli.json'), '{"existing":"keep"}')
        Install-OpenCodeTheme
        $currentSettings = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $openCodeDirectory 'cli.json')))
        Assert-Condition ($currentSettings.theme.name -eq 'charm-v2' -and $currentSettings.theme.mode -eq 'dark' -and $currentSettings.existing -eq 'keep') 'OpenCode CLI theme setup did not select Charm or preserve existing settings.'
        Assert-Condition (Test-Path -LiteralPath (Join-Path $openCodeDirectory 'themes\charm-v2.json')) 'OpenCode CLI theme setup did not install the v2 theme asset.'
    }
    finally {
        if ($null -eq $previousXdgConfig) { Remove-Item Env:XDG_CONFIG_HOME -ErrorAction SilentlyContinue }
        else { $env:XDG_CONFIG_HOME = $previousXdgConfig }
    }

    $tomlPath = Join-Path $testDirectory 'config.toml'
    [IO.File]::WriteAllText($tomlPath, "[model]`nmodel = `"preserve`"`n[tui]`ntheme = `"system`"`n[other]`nvalue = 1`n")
    Set-CodexThemeConfig $tomlPath
    $toml = [IO.File]::ReadAllText($tomlPath)
    Assert-Condition ($toml.Contains('[model]') -and $toml.Contains('theme = "charm-dark"') -and $toml.Contains('[other]')) 'Codex TOML merge did not preserve other sections.'
    $tomlBackups = @(Get-ChildItem -LiteralPath $testDirectory -Filter 'config.toml.backup-*')
    Set-CodexThemeConfig $tomlPath
    Assert-Condition (@(Get-ChildItem -LiteralPath $testDirectory -Filter 'config.toml.backup-*').Count -eq $tomlBackups.Count) 'Codex theme merge was not idempotent.'

    $profilePath = Join-Path $testDirectory 'Microsoft.PowerShell_profile.ps1'
    [IO.File]::WriteAllText($profilePath, "# existing profile content`n")
    Set-PowerShellProfile $profilePath
    $profile = [IO.File]::ReadAllText($profilePath)
    Assert-Condition ($profile.Contains('# existing profile content') -and $profile.Contains('COLORFGBG') -and $profile.Contains('starship.exe init powershell')) 'PowerShell profile setup did not preserve existing content or add the terminal environment.'
    $profileBackups = @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Microsoft.PowerShell_profile.ps1.backup-*')
    Set-PowerShellProfile $profilePath
    Assert-Condition (@(Get-ChildItem -LiteralPath $testDirectory -Filter 'Microsoft.PowerShell_profile.ps1.backup-*').Count -eq $profileBackups.Count) 'PowerShell profile setup was not idempotent.'

    $script:NativeArchitecture = 'arm64'
    Assert-Condition ((Get-UnsupportedToolReason 'cursor') -eq '') 'Cursor CLI should be available on native Windows ARM64.'
    $script:NativeArchitecture = 'amd64'
    Assert-Condition ((Get-UnsupportedToolReason 'cursor') -eq '') 'Cursor CLI should be available on native Windows x64.'

    if ($env:OS -eq 'Windows_NT') {
        $sourceDirectory = Join-Path $testDirectory 'nvim-source'
        $targetDirectory = Join-Path $testDirectory 'nvim-link'
        New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
        Set-ManagedJunction $sourceDirectory $targetDirectory
        Set-ManagedJunction $sourceDirectory $targetDirectory
        Assert-Condition (@(Get-ChildItem -LiteralPath $testDirectory -Filter 'nvim-link.backup-*').Count -eq 0) 'Managed Neovim junction was not idempotent.'
    }

    Write-Output 'Windows installer config tests passed.'
}
finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
