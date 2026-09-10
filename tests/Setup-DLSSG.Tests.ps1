#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$setup = Join-Path $root 'tools/Setup-DLSSG.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dlssg-tests-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$passed = 0

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Run, [string]$Pattern) {
    try { & $Run | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw "Wrong error: $($_.Exception.Message); expected $Pattern" }
        return
    }
    throw "Expected failure: $Pattern"
}
function Snapshot([string]$Directory) {
    return (@(Get-ChildItem -LiteralPath $Directory -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.PSIsContainer) { $_.FullName }
        else { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash }
    }) -join "`n")
}
function Test-Case([string]$Name, [scriptblock]$Run) {
    $dir = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + ' game [test]')
    $null = New-Item -ItemType Directory -Path $dir
    $exe = Join-Path $dir 'game [test].exe'
    $bytes = New-Object byte[] 128
    $bytes[0] = 0x4D; $bytes[1] = 0x5A; $bytes[60] = 64
    $bytes[64] = 0x50; $bytes[65] = 0x45; $bytes[68] = 0x64; $bytes[69] = 0x86
    $bytes[88] = 0x0B; $bytes[89] = 0x02
    [IO.File]::WriteAllBytes($exe, $bytes)
    $ini = Join-Path $dir 'dlssg_sm86.ini'
    $dll = Join-Path $dir 'version.dll'
    $record = Join-Path $dir '.dlssg-setup'
    & $Run
    $script:passed++
    Write-Output "PASS: $Name"
}

try {
    Test-Case 'Bundled and archived DLL hashes match the manifest' {
        $manifest = Get-Content -LiteralPath (Join-Path $root 'config/binary-hashes.json') -Raw | ConvertFrom-Json
        foreach ($entry in $manifest.proxies.PSObject.Properties) {
            $relative = if ($entry.Name -eq 'version.dll') { $entry.Name } else { 'altnative/' + $entry.Name }
            Assert ((Get-FileHash -LiteralPath (Join-Path $root $relative)).Hash -eq $entry.Value) "Hash mismatch: $relative"
        }
        Assert ((Get-FileHash -LiteralPath (Join-Path $root 'archive/version.dll')).Hash -in $manifest.legacyProxyHashes) 'Missing archive hash'
    }
    Test-Case 'Install/Check/Uninstall round trip with literal spaces and brackets' {
        & $setup -Action Install -GameExe $exe | Out-Null
        Assert (Test-Path -LiteralPath $dll) 'DLL not installed'
        $text = [IO.File]::ReadAllText($ini)
        Assert ($text -match 'Router=SM86' -and $text -match 'HardwareBilinear=0' -and $text -match 'MaxGeneratedFrames=3') 'Wrong defaults'
        $before = Snapshot $dir
        & $setup -Action Check -GameExe $exe | Out-Null
        Assert ((Snapshot $dir) -eq $before) 'Check modified files'
        & $setup -Action Uninstall -GameExe $exe | Out-Null
        Assert (-not (Test-Path -LiteralPath $dll)) 'DLL left behind'
        Assert (-not (Test-Path -LiteralPath $ini)) 'New INI left behind'
        Assert (-not (Test-Path -LiteralPath $record)) 'Installation record left behind'
    }
    Test-Case 'Existing INI restored byte for byte, including UTF-16 encoding' {
        [IO.File]::WriteAllText($ini, "[Custom]`r`nValue=" + [char]0x6E38, [Text.Encoding]::Unicode)
        $old = (Get-FileHash -LiteralPath $ini).Hash
        & $setup -Action Install -GameExe $exe | Out-Null
        Assert ((Get-FileHash -LiteralPath (Join-Path $record 'original.ini')).Hash -eq $old) 'Backup differs'
        & $setup -Action Uninstall -GameExe $exe | Out-Null
        Assert ((Get-FileHash -LiteralPath $ini).Hash -eq $old) 'Original INI not restored'
    }
    foreach ($proxy in @('version.dll', 'winmm.dll', 'dinput8.dll', 'winhttp.dll', 'dxgi.dll')) {
        Test-Case "Proxy round trip: $proxy" {
            & $setup -Action Install -GameExe $exe -Proxy $proxy -Router SM75 -Multiplier 2 | Out-Null
            $text = [IO.File]::ReadAllText($ini)
            Assert ($text -match 'Router=SM75' -and $text -match 'MaxGeneratedFrames=1' -and $text -match 'KernelImage=PTX') 'Wrong SM75 settings'
            & $setup -Action Check -GameExe $exe | Out-Null
            & $setup -Action Uninstall -GameExe $exe | Out-Null
            Assert (-not (Test-Path -LiteralPath (Join-Path $dir $proxy))) 'Alternative proxy not removed'
        }
    }
    Test-Case 'SM86 approximate and 3X are explicit opt-ins' {
        & $setup -Action Install -GameExe $exe -Approximate -Multiplier 3 -WarningAction SilentlyContinue | Out-Null
        $text = [IO.File]::ReadAllText($ini)
        Assert ($text -match 'HardwareBilinear=1' -and $text -match 'MaxGeneratedFrames=2') 'Wrong opt-in settings'
    }
    Test-Case 'SM75 rejects ineffective approximate mode without writes' {
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Install -GameExe $exe -Router SM75 -Approximate } 'only on SM86'
        Assert ((Snapshot $dir) -eq $before) 'Rejected install modified files'
    }
    Test-Case 'WhatIf creates no files and preserves existing INI' {
        [IO.File]::WriteAllText($ini, 'original')
        $before = Snapshot $dir
        & $setup -Action Install -GameExe $exe -WhatIf | Out-Null
        Assert ((Snapshot $dir) -eq $before) 'Install WhatIf modified files'
        & $setup -Action Install -GameExe $exe | Out-Null
        $before = Snapshot $dir
        & $setup -Action Uninstall -GameExe $exe -WhatIf | Out-Null
        Assert ((Snapshot $dir) -eq $before) 'Uninstall WhatIf modified files'
    }
    Test-Case 'Conflicting mod DLL is never overwritten' {
        [IO.File]::WriteAllText($dll, 'another mod')
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Install -GameExe $exe -WarningAction SilentlyContinue } 'already exists'
        Assert ((Snapshot $dir) -eq $before) 'Conflict modified files'
        & $setup -Action Install -GameExe $exe -Proxy winmm.dll -WarningAction SilentlyContinue | Out-Null
        & $setup -Action Uninstall -GameExe $exe | Out-Null
        Assert ((Snapshot $dir) -eq $before) 'Alternative installation touched another mod'
    }
    Test-Case 'Recognizes an archived proxy under an alternative name' {
        [IO.File]::Copy((Join-Path $root 'archive/version.dll'), (Join-Path $dir 'winmm.dll'))
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'already installed'
        Assert-Throws { & $setup -Action Check -GameExe $exe } 'archived or renamed'
        Assert ((Snapshot $dir) -eq $before) 'Archive check modified files'
    }
    Test-Case 'Duplicate project proxies fail Check' {
        & $setup -Action Install -GameExe $exe | Out-Null
        [IO.File]::Copy((Join-Path $root 'altnative/winmm.dll'), (Join-Path $dir 'winmm.dll'))
        Assert-Throws { & $setup -Action Check -GameExe $exe } 'Found 2'
    }
    Test-Case 'A renamed current DLL fails Check' {
        & $setup -Action Install -GameExe $exe | Out-Null
        [IO.File]::Move($dll, (Join-Path $dir 'winmm.dll'))
        Assert-Throws { & $setup -Action Check -GameExe $exe } 'archived or renamed'
    }
    Test-Case 'Reinstallation is refused without changing backup' {
        & $setup -Action Install -GameExe $exe | Out-Null
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'record already exists'
        Assert ((Snapshot $dir) -eq $before) 'Reinstall changed files'
    }
    Test-Case 'Unmanaged uninstall removes nothing' {
        [IO.File]::Copy((Join-Path $root 'version.dll'), $dll)
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Uninstall -GameExe $exe } 'No managed installation'
        Assert ((Snapshot $dir) -eq $before) 'Unmanaged files changed'
    }
    foreach ($modified in @('version.dll', 'dlssg_sm86.ini', '.dlssg-setup/original.ini')) {
        Test-Case "Uninstall protects changed file: $modified" {
            [IO.File]::WriteAllText($ini, 'original')
            & $setup -Action Install -GameExe $exe | Out-Null
            [IO.File]::WriteAllText((Join-Path $dir $modified), 'user edit')
            $before = Snapshot $dir
            Assert-Throws { & $setup -Action Uninstall -GameExe $exe } 'changed'
            Assert ((Snapshot $dir) -eq $before) 'Uninstall removed modified files'
        }
    }
    Test-Case 'Uninstall tolerates already missing managed files' {
        [IO.File]::WriteAllText($ini, 'original')
        & $setup -Action Install -GameExe $exe | Out-Null
        [IO.File]::Delete($dll); [IO.File]::Delete($ini)
        & $setup -Action Uninstall -GameExe $exe | Out-Null
        Assert ([IO.File]::ReadAllText($ini) -eq 'original') 'Original not recovered'
    }
    Test-Case 'Uninstall resumes after original INI was already restored' {
        [IO.File]::WriteAllText($ini, 'original')
        & $setup -Action Install -GameExe $exe | Out-Null
        [IO.File]::Delete($dll)
        [IO.File]::Copy((Join-Path $record 'original.ini'), $ini, $true)
        [IO.File]::Delete((Join-Path $record 'original.ini'))
        & $setup -Action Uninstall -GameExe $exe | Out-Null
        Assert ([IO.File]::ReadAllText($ini) -eq 'original') 'Restored INI was removed'
        Assert (-not (Test-Path -LiteralPath $record)) 'Resume failed'
    }
    Test-Case 'Uninstall protects unexpected state directory files' {
        & $setup -Action Install -GameExe $exe | Out-Null
        [IO.File]::WriteAllText((Join-Path $record 'keep.txt'), 'keep')
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Uninstall -GameExe $exe } 'Unexpected files'
        Assert ((Snapshot $dir) -eq $before) 'Unexpected file was removed'
    }
    Test-Case 'Malformed installation record is non-destructive' {
        & $setup -Action Install -GameExe $exe | Out-Null
        $path = Join-Path $record 'state.json'
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $state.Proxy = '../outside.dll'
        [IO.File]::WriteAllText($path, ($state | ConvertTo-Json))
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Uninstall -GameExe $exe } 'Invalid installation record'
        Assert ((Snapshot $dir) -eq $before) 'Malformed state modified files'
    }
    foreach ($invalid in @('duplicate-section', 'duplicate-key', 'bad-value', 'missing-key', 'bad-line')) {
        Test-Case "Check rejects invalid INI: $invalid" {
            & $setup -Action Install -GameExe $exe | Out-Null
            $text = [IO.File]::ReadAllText($ini)
            switch ($invalid) {
                'duplicate-section' { $text += "`n[Logging]`nLevel=1`n" }
                'duplicate-key' { $text += "Level=2`n" }
                'bad-value' { $text = $text.Replace('MaxGeneratedFrames=3', 'MaxGeneratedFrames=0') }
                'missing-key' { $text = $text.Replace('Router=SM86', ';Router=SM86') }
                'bad-line' { $text += "invalid text`n" }
            }
            [IO.File]::WriteAllText($ini, $text)
            $before = Snapshot $dir
            Assert-Throws { & $setup -Action Check -GameExe $exe } 'Duplicate|invalid|Invalid'
            Assert ((Snapshot $dir) -eq $before) 'INI check modified files'
        }
    }
    Test-Case 'Check warns about diagnostics, SM75 approximation and disabled mod' {
        & $setup -Action Install -GameExe $exe -Router SM75 | Out-Null
        $text = [IO.File]::ReadAllText($ini).Replace('HardwareBilinear=0', 'HardwareBilinear=1').Replace('Level=1', 'Level=2')
        [IO.File]::WriteAllText($ini, $text + "`n[General]`nEnabled=0`n[Diagnostics]`nPipelineSteps=1`n")
        $warnings = @()
        & $setup -Action Check -GameExe $exe -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        Assert ($warnings.Count -eq 3) "Expected 3 warnings, got $($warnings.Count)"
    }
    Test-Case 'Rejects 32-bit and malformed executables' {
        $bytes[68] = 0x4C; $bytes[69] = 0x01
        [IO.File]::WriteAllBytes($exe, $bytes)
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'Windows x64'
        [IO.File]::WriteAllText($exe, 'not a PE')
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'not a Windows PE'
    }
    Test-Case 'Running game blocks installation before any writes' {
        function Get-Process { param($Name) return [pscustomobject]@{ ProcessName = 'game [test]' } }
        $before = Snapshot $dir
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'Exit the game first'
        Assert ((Snapshot $dir) -eq $before) 'Running game was modified'
    }
    Test-Case 'Damaged source DLL is rejected before any writes' {
        function Get-FileHash {
            param($LiteralPath, $Algorithm)
            if ($LiteralPath -eq (Join-Path $root 'version.dll')) { return [pscustomobject]@{ Hash = ('0' * 64) } }
            Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256
        }
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'SHA256 does not match'
        Assert (-not (Test-Path -LiteralPath $record)) 'Created state for damaged payload'
    }
    Test-Case 'Late proxy conflict rolls INI back and preserves competing file' {
        [IO.File]::WriteAllText($ini, 'original')
        function Get-FileHash {
            param($LiteralPath, $Algorithm)
            if ([IO.Path]::GetFileName($LiteralPath) -eq 'proxy.pending') { [IO.File]::WriteAllText($dll, 'another mod') }
            Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256
        }
        Assert-Throws { & $setup -Action Install -GameExe $exe } 'already exists'
        Assert ([IO.File]::ReadAllText($ini) -eq 'original') 'Rollback failed to restore INI'
        Assert ([IO.File]::ReadAllText($dll) -eq 'another mod') 'Rollback deleted competing DLL'
        Assert (-not (Test-Path -LiteralPath $record)) 'Rollback left state'
    }
    Test-Case 'Relative executable paths follow the PowerShell location' {
        Push-Location -LiteralPath $dir
        try {
            & $setup -Action Install -GameExe './game [test].exe' | Out-Null
            Assert (Test-Path -LiteralPath $dll) 'Relative path selected the wrong directory'
        }
        finally { Pop-Location }
    }
    Test-Case 'Directory links are rejected without touching their targets' {
        $link = Join-Path $testRoot ('link-' + [Guid]::NewGuid().ToString('N'))
        # Windows PowerShell 5.1 expands wildcards in New-Item's junction target.
        # Literal bracket handling is exercised by the other installation tests.
        $target = Join-Path $testRoot ('target-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::Move($dir, $target)
        $kind = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $kind -Path $link -Target $target
        try {
            $before = Snapshot $target
            Assert-Throws { & $setup -Action Install -GameExe (Join-Path $link 'game [test].exe') } 'linked path'
            Assert ((Snapshot $target) -eq $before) 'Linked target was modified'
        }
        finally { [IO.Directory]::Delete($link) }
    }
    if ($env:OS -ne 'Windows_NT') {
        Test-Case 'Dangling INI symlinks are rejected' {
            $outside = Join-Path $testRoot 'must-not-be-created.ini'
            $null = New-Item -ItemType SymbolicLink -Path $ini -Target $outside
            Assert-Throws { & $setup -Action Install -GameExe $exe } 'linked path'
            Assert (-not (Test-Path -LiteralPath $outside)) 'Wrote through dangling link'
        }
    }
    if ($env:OS -eq 'Windows_NT') {
        Test-Case 'Uninstall resumes after a sharing lock blocked journal deletion' {
            [IO.File]::WriteAllText($ini, 'original')
            & $setup -Action Install -GameExe $exe | Out-Null
            $lock = [IO.File]::Open((Join-Path $record 'state.json'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { Assert-Throws { & $setup -Action Uninstall -GameExe $exe } 'being used|access|process' }
            finally { $lock.Dispose() }
            & $setup -Action Uninstall -GameExe $exe | Out-Null
            Assert ([IO.File]::ReadAllText($ini) -eq 'original') 'Locked-journal retry lost original INI'
            Assert (-not (Test-Path -LiteralPath $record)) 'Locked-journal retry failed to clean up'
        }
    }
    Test-Case 'Manual presets pass the same INI validation as managed installs' {
        [IO.File]::Copy((Join-Path $root 'version.dll'), $dll)
        foreach ($preset in Get-ChildItem -LiteralPath (Join-Path $root 'config/presets') -Filter '*.ini') {
            [IO.File]::Copy($preset.FullName, $ini, $true)
            & $setup -Action Check -GameExe $exe | Out-Null
        }
    }
    Write-Output "$passed tests passed. No game or GPU was exercised."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
