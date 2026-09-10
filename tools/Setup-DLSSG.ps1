#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Check', 'Uninstall')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [string]$GameExe,
    [ValidateSet('version.dll', 'winmm.dll', 'dinput8.dll', 'winhttp.dll', 'dxgi.dll')]
    [string]$Proxy = 'version.dll',
    [ValidateSet('SM86', 'SM75')]
    [string]$Router = 'SM86',
    [ValidateRange(2, 4)]
    [int]$Multiplier = 4,
    [switch]$Approximate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$proxyNames = @('version.dll', 'winmm.dll', 'dinput8.dll', 'winhttp.dll', 'dxgi.dll')

function Assert-NoLink([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing linked path: $current"
        }
        $current = Split-Path -Parent $current
    }
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-GameExe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ine '.exe') {
        throw 'GameExe must be an existing game rendering .exe, not a directory or launcher shortcut.'
    }
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if ($reader.BaseStream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw 'GameExe is not a Windows PE executable.'
        }
        $reader.BaseStream.Position = 60
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($reader.BaseStream.Length - 26)) {
            throw 'GameExe has an invalid PE header.'
        }
        $reader.BaseStream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'This mod requires a Windows x64 game executable.'
        }
        $reader.BaseStream.Position = $peOffset + 24
        if ($reader.ReadUInt16() -ne 0x20B) { throw 'GameExe must use the PE32+ executable format.' }
    }
    finally { $reader.Dispose() }
}

function Read-Ini([string]$Path) {
    $values = @{}
    $sections = @{}
    $section = ''
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([^\]]+)\]$') {
            $section = $Matches[1].Trim()
            if ($sections.ContainsKey($section)) { throw "Duplicate INI section: $section" }
            $sections[$section] = $true
        }
        elseif ($line -match '^([^=]+)=(.*)$' -and $section) {
            $key = "$section.$($Matches[1].Trim())"
            if ($values.ContainsKey($key)) { throw "Duplicate INI key: $key" }
            $values[$key] = $Matches[2].Trim()
        }
        else { throw "Invalid INI line: $line" }
    }
    $allowed = @{
        'Compatibility.Router' = @('SM75', 'SM86')
        'Compatibility.KernelImage' = @('PTX', 'Auto', 'Cubin')
        'Compatibility.HardwareBilinear' = @('0', '1')
        'FrameGeneration.MaxGeneratedFrames' = @('1', '2', '3')
        'Logging.Level' = @('0', '1', '2', '3')
    }
    foreach ($key in $allowed.Keys) {
        if (-not $values.ContainsKey($key) -or $values[$key] -notin $allowed[$key]) {
            throw "Missing or invalid INI setting: $key. See docs/SETUP.md."
        }
    }
    return $values
}

$GameExe = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($GameExe)
Assert-NoLink $GameExe
Assert-GameExe $GameExe
$gameDir = Split-Path -Parent $GameExe
if ($gameDir -ieq $packageRoot) { throw 'Extract this package separately from the game directory.' }
$iniPath = Join-Path $gameDir 'dlssg_sm86.ini'
$stateDir = Join-Path $gameDir '.dlssg-setup'
$statePath = Join-Path $stateDir 'state.json'
$backupPath = Join-Path $stateDir 'original.ini'
foreach ($path in @($iniPath, $stateDir, $statePath, $backupPath)) { Assert-NoLink $path }
foreach ($name in $proxyNames) { Assert-NoLink (Join-Path $gameDir $name) }

if ($Action -ne 'Check') {
    $processName = [IO.Path]::GetFileNameWithoutExtension($GameExe)
    if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ieq $processName }) {
        throw "Exit the game first. A process named $processName is running."
    }
}

if ($Action -eq 'Uninstall') {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw 'No managed installation found. Nothing was removed; uninstall manual installs manually.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.Version -ne 1 -or $state.GameExe -ine $GameExe -or $state.Proxy -notin $proxyNames -or
        $state.ProxyHash -notmatch '^[a-f0-9]{64}$' -or $state.IniHash -notmatch '^[a-f0-9]{64}$' -or
        $state.HadIni -isnot [bool]) {
        throw 'Invalid installation record. Nothing was removed.'
    }
    $target = Join-Path $gameDir $state.Proxy
    $originalRestored = $state.HadIni -and (Test-Path -LiteralPath $iniPath -PathType Leaf) -and
        (Get-Hash $iniPath) -eq $state.OriginalIniHash
    foreach ($entry in @(@($target, $state.ProxyHash), @($iniPath, $state.IniHash))) {
        if ($entry[0] -eq $iniPath -and $originalRestored) { continue }
        if ((Test-Path -LiteralPath $entry[0]) -and
            (-not (Test-Path -LiteralPath $entry[0] -PathType Leaf) -or (Get-Hash $entry[0]) -ne $entry[1])) {
            throw "File changed since installation: $($entry[0]). Move it to a safe backup location, then retry."
        }
    }
    if ($state.HadIni -and -not $originalRestored -and
        (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-Hash $backupPath) -ne $state.OriginalIniHash)) {
        throw 'Original INI backup is missing or changed. Nothing was removed.'
    }
    if ((Test-Path -LiteralPath $backupPath) -and
        (-not $state.HadIni -or (Get-Hash $backupPath) -ne $state.OriginalIniHash)) {
        throw 'Unexpected or changed original.ini backup. Nothing was removed.'
    }
    $unexpected = @(Get-ChildItem -LiteralPath $stateDir -Force | Where-Object { $_.Name -notin @('state.json', 'original.ini') })
    if ($unexpected.Count) { throw 'Unexpected files in .dlssg-setup. Move them to safety before uninstalling.' }
    if (-not $PSCmdlet.ShouldProcess($gameDir, 'Remove managed proxy and restore the previous INI')) { return }
    # Keep the backup until restoration succeeds; retries also accept an already-restored INI.
    if (Test-Path -LiteralPath $target) { [IO.File]::Delete($target) }
    if (-not $originalRestored) {
        if (Test-Path -LiteralPath $iniPath) { [IO.File]::Delete($iniPath) }
        if ($state.HadIni) { [IO.File]::Copy($backupPath, $iniPath, $false) }
    }
    if (Test-Path -LiteralPath $backupPath) { [IO.File]::Delete($backupPath) }
    [IO.File]::Delete($statePath)
    [IO.Directory]::Delete($stateDir)
    Write-Output 'Uninstalled. Previous INI restored if one existed. Other DLLs and game logs were left alone.'
    return
}

$hashes = Get-Content -LiteralPath (Join-Path $packageRoot 'config/binary-hashes.json') -Raw | ConvertFrom-Json
$knownHashes = @($hashes.proxies.PSObject.Properties.Value) + @($hashes.legacyProxyHashes)
$installed = @()
foreach ($name in $proxyNames) {
    $path = Join-Path $gameDir $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $hash = Get-Hash $path
        if ($hash -in $knownHashes) { $installed += $name }
        else { Write-Warning "Unrecognized proxy-name file: $name. It may belong to another mod; it will not be overwritten." }
    }
}

if ($Action -eq 'Check') {
    if ($installed.Count -ne 1) {
        throw "Found $($installed.Count) recognized project proxies; expected exactly one. Old/unrecognized versions require manual review."
    }
    $installedName = $installed[0]
    if ((Get-Hash (Join-Path $gameDir $installedName)) -ne $hashes.proxies.$installedName) {
        throw 'The installed proxy is archived or renamed. Use one current proxy with its original filename.'
    }
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { throw 'Missing dlssg_sm86.ini beside the game executable.' }
    $ini = Read-Ini $iniPath
    if ($ini['Compatibility.Router'] -eq 'SM75' -and $ini['Compatibility.HardwareBilinear'] -eq '1') {
        Write-Warning 'Approximate sampling has no effect on SM75. Use HardwareBilinear=0.'
    }
    if ($ini['Compatibility.KernelImage'] -ne 'PTX') {
        Write-Warning 'PTX is the portable default. Cubin requires an exact physical GPU/router match; Auto may choose Cubin.'
    }
    if ([int]$ini['Logging.Level'] -ge 2 -or $ini['Diagnostics.PipelineSteps'] -eq '1') {
        Write-Warning 'Diagnostic logging/timing is enabled. Restore Level=1 and remove Diagnostics after troubleshooting.'
    }
    if ($ini['General.Enabled'] -eq '0') { Write-Warning 'The mod is disabled by General.Enabled=0.' }
    $obsolete = @('Runtime.Mode', 'Compatibility.OptimizedKernels', 'Compatibility.DisableFusions',
        'Compatibility.ImagePatches', 'Compatibility.CudaBufferClear', 'Compatibility.ChainBlock0',
        'Compatibility.PlainVariant', 'Compatibility.DependencyBarriers')
    foreach ($key in $obsolete) {
        if ($ini.ContainsKey($key)) { Write-Warning "Obsolete setting ignored by Native: $key" }
    }
    $cap = [int]$ini['FrameGeneration.MaxGeneratedFrames'] + 1
    Write-Output "Files and five core INI settings checked: $installedName, $($ini['Compatibility.Router']), up to ${cap}X."
    Write-Output "Log directory: $(Join-Path $gameDir 'dlssg_sm86/logs')"
    Write-Output 'This does not verify GPU/driver support, D3D12, game loading, anti-cheat compatibility, or in-game performance.'
    return
}

if ($Approximate -and $Router -eq 'SM75') { throw 'Approximate sampling is supported only on SM86.' }
if (Test-Path -LiteralPath $stateDir) { throw 'An installation record already exists. Uninstall it first; keep its backup intact.' }
if ($installed.Count) { throw 'A project proxy is already installed. Back up and remove the manual install, or use Uninstall first.' }
$target = Join-Path $gameDir $Proxy
if (Test-Path -LiteralPath $target) { throw "$Proxy already exists. Preserve it and choose a different proxy the game loads." }
if ((Test-Path -LiteralPath $iniPath) -and -not (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
    throw 'dlssg_sm86.ini is not a regular file.'
}
$source = if ($Proxy -eq 'version.dll') { Join-Path $packageRoot $Proxy } else { Join-Path (Join-Path $packageRoot 'altnative') $Proxy }
Assert-NoLink $source
if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Hash $source) -ne $hashes.proxies.$Proxy) {
    throw 'Packaged DLL is missing or its SHA256 does not match config/binary-hashes.json. Download a clean copy; do not disable antivirus.'
}
$approximateValue = [int]$Approximate.IsPresent
$config = @"
; Native 0.2.4. Restart the game after changes.
[Compatibility]
Router=$Router
KernelImage=PTX
HardwareBilinear=$approximateValue

[FrameGeneration]
; Capability limit only; the game selects the actual multiplier.
MaxGeneratedFrames=$($Multiplier - 1)

[Logging]
Level=1
"@ -replace "`r?`n", "`r`n"
$config += "`r`n"
$configBytes = [Text.Encoding]::ASCII.GetBytes($config)
$sha = [Security.Cryptography.SHA256]::Create()
try { $iniHash = ([BitConverter]::ToString($sha.ComputeHash($configBytes))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }
$hadIni = Test-Path -LiteralPath $iniPath -PathType Leaf
$originalHash = if ($hadIni) { Get-Hash $iniPath } else { $null }
$state = [ordered]@{
    Version = 1; GameExe = $GameExe; Proxy = $Proxy; ProxyHash = $hashes.proxies.$Proxy
    IniHash = $iniHash; HadIni = [bool]$hadIni; OriginalIniHash = $originalHash
}
if ($Approximate) { Write-Warning 'Approximate sampling changes generated pixels and is not guaranteed to be faster.' }
if (-not $PSCmdlet.ShouldProcess($gameDir, "Back up existing INI and install $Proxy, $Router, up to ${Multiplier}X")) { return }
$stateCreated = $false
$proxyCopied = $false
$iniWritten = $false
$stagedProxy = Join-Path $stateDir 'proxy.pending'
try {
    $null = New-Item -Path $stateDir -ItemType Directory -ErrorAction Stop
    $stateCreated = $true
    if ($hadIni) { [IO.File]::Copy($iniPath, $backupPath, $false) }
    [IO.File]::Copy($source, $stagedProxy, $false)
    if ((Get-Hash $stagedProxy) -ne $state.ProxyHash) { throw 'Staged DLL verification failed.' }
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [Text.Encoding]::UTF8)
    $iniWritten = $true
    [IO.File]::WriteAllBytes($iniPath, $configBytes)
    # Same-volume rename avoids leaving a partially copied DLL in the game's load path.
    # File.Move without overwrite also preserves any proxy created after preflight.
    [IO.File]::Move($stagedProxy, $target)
    $proxyCopied = $true
    if ((Get-Hash $target) -ne $state.ProxyHash -or (Get-Hash $iniPath) -ne $iniHash) {
        throw 'Installed file verification failed.'
    }
}
catch {
    $installError = $_
    if (-not $stateCreated) { throw $installError }
    try {
        if ($proxyCopied) {
            if ((Get-Hash $target) -ne $state.ProxyHash) { throw 'Installed proxy changed during rollback.' }
            [IO.File]::Delete($target)
        }
        if ($iniWritten) {
            if ($hadIni) { [IO.File]::Copy($backupPath, $iniPath, $true) }
            else { [IO.File]::Delete($iniPath) }
        }
        if (Test-Path -LiteralPath $stagedProxy) { [IO.File]::Delete($stagedProxy) }
        if (Test-Path -LiteralPath $backupPath) { [IO.File]::Delete($backupPath) }
        if (Test-Path -LiteralPath $statePath) { [IO.File]::Delete($statePath) }
        [IO.Directory]::Delete($stateDir)
    }
    catch { Write-Warning "Automatic rollback could not finish. Preserve $stateDir and use the recovery instructions in docs/SETUP.md." }
    throw $installError
}
Write-Output "Installed $Proxy with $Router, PTX, exact=$(-not $Approximate.IsPresent), up to ${Multiplier}X."
Write-Output "Backup/installation record: $stateDir. Keep it until uninstalling."
Write-Output 'Restart the game, enable DLSS frame generation, then run Check. The game must load the selected proxy.'
