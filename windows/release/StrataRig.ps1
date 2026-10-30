<#
StrataRig - installs and runs the Strata Windows Rig DeepSeek engine (https://github.com/hap911/Strata-Windows-Rig).

  .\StrataRig.ps1 setup     first-time setup: installs official Strata if missing, checks the DeepSeek engine version,
                            installs the patched engine, downloads the abliteration adapter, writes StrataRig.config.json
  .\StrataRig.ps1 start     switches the patched engine in (only if Strata's engine version matches) and starts DeepSeek
  .\StrataRig.ps1 start -Stock    the same without abliteration
  .\StrataRig.ps1 status    what is installed and whether it matches
  .\StrataRig.ps1 restore   puts Strata's official engine back

The patched engine is built for ONE Strata engine version (see manifest.json). When Strata updates its engine, `start`
refuses to swap in the old build and runs the official engine instead (no abliteration, no speed-ups) until a matching
StrataRig release is installed. That is deliberate: a mismatched engine can break Strata.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet("setup", "start", "status", "restore")][string]$Command = "status",
    [switch]$Stock,
    [switch]$NoAdapter,
    [switch]$Yes
)
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Manifest = Get-Content (Join-Path $Here "manifest.json") -Raw | ConvertFrom-Json
$RigHome = Join-Path $env:LOCALAPPDATA "StrataRig"
$StrataCmd = Join-Path $env:LOCALAPPDATA "Strata\terminal\current\bin\strata.cmd"
$EngineRoot = Join-Path $env:LOCALAPPDATA "Strata\install\engine-dsv41"
$ConfigPath = Join-Path $RigHome "StrataRig.config.json"
$AdapterUrl = "https://huggingface.co/BoldingBuilds/DeepSeek-V4.1-Flash-1017-Abliteration-LoRA-GGUF/resolve/main/DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf"
$AdapterSha = "6E2B14EEBC572CBC078D0DB654F25A00801CB8AD3A7DC4893EF40CFB3BDAE18A"
$AdapterPath = Join-Path $RigHome "adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf"

function Say($m) { Write-Host "StrataRig: $m" }
function Ask($q) {
    if ($Yes) { return $true }
    return (Read-Host "$q [y/N]") -match '^(y|yes)$'
}

# Strata's current DeepSeek engine folder and its version (from its signed engine-component.json)
function Get-Engine {
    if (-not (Test-Path $EngineRoot)) { return $null }
    $dirs = Get-ChildItem $EngineRoot -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+-windows-x86_64-cuda' }
    foreach ($d in ($dirs | Sort-Object { [version]($_.Name -split '-')[0] } -Descending)) {
        $c = Join-Path $d.FullName "engine-component.json"
        if (Test-Path $c) {
            $j = Get-Content $c -Raw | ConvertFrom-Json
            $official = ($j.files | Where-Object { $_.path -eq "strata-dsv41.exe" }).sha256
            return [pscustomobject]@{ Dir = $d.FullName; Version = $j.version; OfficialSha = $official }
        }
    }
    return $null
}

function Get-GpuInfo {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { return @() }
    $rows = & nvidia-smi --query-gpu=index,name,compute_cap,memory.total,driver_version --format=csv,noheader,nounits 2>$null
    foreach ($r in $rows) {
        $f = $r -split ',\s*'
        [pscustomobject]@{ Index = [int]$f[0]; Name = $f[1]; Cap = $f[2]; MemGB = [math]::Round([double]$f[3] / 1024, 1); Driver = $f[4] }
    }
}

function Install-Engine($eng) {
    $dst = Join-Path $RigHome ("engine\" + $Manifest.engine_version)
    New-Item -ItemType Directory -Force $dst | Out-Null
    foreach ($f in "strata-dsv41.exe", "strata_kq.dll") { Copy-Item (Join-Path $Here "engine\$f") $dst -Force }
    $exe = Join-Path $eng.Dir "strata-dsv41.exe"
    $bak = Join-Path $eng.Dir "strata-dsv41.exe.official"
    if (-not (Test-Path $bak)) {
        if ((Get-FileHash $exe -Algorithm SHA256).Hash -ieq $eng.OfficialSha) { Copy-Item $exe $bak }
        else { Say "WARNING: the engine exe in $($eng.Dir) is not Strata's official one and no backup exists; restore will need a Strata reinstall." }
    }
    Say "patched engine $($Manifest.engine_version) stored in $dst"
}

# switches the patched engine in; returns $true when it is active
function Use-Patched {
    $eng = Get-Engine
    if (-not $eng) { Say "no DeepSeek engine installed by Strata yet - run setup."; return $false }
    if ($eng.Version -ne $Manifest.engine_version) {
        Say "Strata's DeepSeek engine is $($eng.Version), this StrataRig build is for $($Manifest.engine_version)."
        Say "Running Strata's OFFICIAL engine (no abliteration, no speed-ups). Get a matching release: https://github.com/hap911/Strata-Windows-Rig/releases"
        return $false
    }
    $src = Join-Path $RigHome ("engine\" + $Manifest.engine_version)
    if (-not (Test-Path (Join-Path $src "strata-dsv41.exe"))) { Install-Engine $eng }
    $bak = Join-Path $eng.Dir "strata-dsv41.exe.official"
    if (-not (Test-Path $bak)) {
        $exe = Join-Path $eng.Dir "strata-dsv41.exe"
        if ((Get-FileHash $exe -Algorithm SHA256).Hash -ieq $eng.OfficialSha) { Copy-Item $exe $bak }
    }
    Copy-Item (Join-Path $src "strata-dsv41.exe") (Join-Path $eng.Dir "strata-dsv41.exe") -Force
    Copy-Item (Join-Path $src "strata_kq.dll") (Join-Path $eng.Dir "strata_kq.dll") -Force
    return $true
}

function New-Config {
    $gpus = @(Get-GpuInfo)
    $ramGB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $threads = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    # RAM expert cache: what the measured rig used (135 of 192 GB), scaled - leave ~56 GB for Windows and the rest
    $cache = [int][math]::Max(0, [math]::Min(135, $ramGB - 56))
    $cfg = [ordered]@{
        model           = "IST-DAS-2.00bpw"
        context         = "256k"
        ssd_cache_gb    = $cache
        cpu_threads     = $threads
        prefill_chunk   = 4096
        reserve_mib     = ""          # e.g. "900,100" - per GPU, in Strata's GPU order; empty = Strata's default
        ds4_split       = ""          # e.g. "14,26" for a 12 GB + 32 GB pair; empty = the engine's own split
        large_pages     = $false      # needs "Lock pages in memory"; measured no speed gain
        cuda_graphs     = $true       # DS4_ATTN_GRAPH=1, the main speed-up
        settle_ms       = 0
        vision          = "on"
        extra_set       = @()         # more "KEY=VALUE" pairs passed as --set
    }
    New-Item -ItemType Directory -Force $RigHome | Out-Null
    $cfg | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8
    Say "wrote $ConfigPath (RAM $ramGB GB -> ssd_cache_gb $cache, $threads CPU threads). Edit it to tune."
}

switch ($Command) {
    "setup" {
        Say "StrataRig $($Manifest.release) - patched DeepSeek engine for Strata engine $($Manifest.engine_version) ($($Manifest.archs -join ', '))"
        $gpus = @(Get-GpuInfo)
        if ($gpus.Count -eq 0) { throw "No NVIDIA GPU found (nvidia-smi missing). This engine needs an RTX 30, 40 or 50 series card." }
        foreach ($g in $gpus) {
            $ok = @("8.6", "8.9", "12.0") -contains $g.Cap -or [double]$g.Cap -gt 12.0
            Say ("GPU {0}: {1}, {2} GB, compute {3}, driver {4}{5}" -f $g.Index, $g.Name, $g.MemGB, $g.Cap, $g.Driver, $(if ($ok) { "" } else { "  <- NOT supported by this build" }))
        }
        if ([version]($gpus[0].Driver) -lt [version]$Manifest.min_driver) { Say "WARNING: NVIDIA driver $($gpus[0].Driver) is older than $($Manifest.min_driver) - update it first." }

        if (-not (Test-Path $StrataCmd)) {
            Say "Strata is not installed. The official installer (no admin rights) is: irm https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | iex"
            if (-not (Ask "Run the official Strata installer now?")) { throw "Strata is needed - install it, then run setup again." }
            Invoke-RestMethod https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | Invoke-Expression
            if (-not (Test-Path $StrataCmd)) { throw "Strata did not install to $StrataCmd - open a new terminal and run setup again." }
        }
        $eng = Get-Engine
        if (-not $eng) {
            Say "Strata has not set up DeepSeek yet. The first start downloads the engine and the model (~250 GB) and serves it."
            if (-not (Ask "Start the stock DeepSeek-V4.1-Flash $($Manifest.model) now (stop it afterwards with: strata launch --stop)?")) {
                throw "Run: strata launch --family deepseek41 --model IST-DAS-2.00bpw  - then run setup again."
            }
            & $StrataCmd launch --family deepseek41 --model IST-DAS-2.00bpw --yes --no-tui
            & $StrataCmd launch --stop
            $eng = Get-Engine
            if (-not $eng) { throw "Strata's DeepSeek engine is still missing - check strata's output." }
        }
        Say "Strata's DeepSeek engine: $($eng.Version) in $($eng.Dir)"
        if ($eng.Version -ne $Manifest.engine_version) {
            throw "This StrataRig build is for engine $($Manifest.engine_version), Strata has $($eng.Version). Get the matching release: https://github.com/hap911/Strata-Windows-Rig/releases (nothing was changed)."
        }
        Install-Engine $eng
        if (-not $NoAdapter) {
            if ((Test-Path $AdapterPath) -and (Get-FileHash $AdapterPath).Hash -ieq $AdapterSha) { Say "abliteration adapter already present" }
            else {
                Say "downloading the abliteration adapter (459 MB, MIT, BoldingBuilds) ..."
                New-Item -ItemType Directory -Force (Split-Path $AdapterPath) | Out-Null
                Invoke-WebRequest -UseBasicParsing $AdapterUrl -OutFile "$AdapterPath.part"
                if ((Get-FileHash "$AdapterPath.part").Hash -ine $AdapterSha) { Remove-Item "$AdapterPath.part"; throw "adapter checksum mismatch - download removed" }
                Move-Item "$AdapterPath.part" $AdapterPath -Force
            }
        }
        if (-not (Test-Path $ConfigPath)) { New-Config }
        foreach ($f in "Start-DeepSeek-Rig.bat", "Start-DeepSeek-Rig-Stock.bat", "Restore-Official-Engine.bat", "StrataRig.ps1", "manifest.json") {
            Copy-Item (Join-Path $Here $f) $RigHome -Force
        }
        Say "done. Start it with $RigHome\Start-DeepSeek-Rig.bat (or Start-DeepSeek-Rig-Stock.bat without abliteration)."
    }
    "start" {
        if (-not (Test-Path $StrataCmd)) { throw "Strata is not installed - run setup." }
        if (-not (Test-Path $ConfigPath)) { New-Config }
        $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $patched = Use-Patched
        $la = @("launch", "--family", "deepseek41", "--model", $cfg.model, "--context", $cfg.context)
        $set = @("prefill-chunk=$($cfg.prefill_chunk)", "cpu-threads=$($cfg.cpu_threads)")
        if ($cfg.ssd_cache_gb -gt 0) { $set += "ssd-cache=$($cfg.ssd_cache_gb)" }
        if ($cfg.reserve_mib) { $set += "reserve-mib=$($cfg.reserve_mib)" }
        foreach ($x in $cfg.extra_set) { $set += $x }
        if ($patched) {
            if ($cfg.cuda_graphs) { $env:DS4_ATTN_GRAPH = "1" }
            $env:DS4_SETTLE_MS = "$($cfg.settle_ms)"
            if ($cfg.ds4_split) { $env:DS4_SPLIT = $cfg.ds4_split }
            if ($cfg.large_pages) { $env:DS4_STORE_LARGE = "1" }
            if (-not $Stock) {
                if (-not (Test-Path $AdapterPath)) { throw "abliteration adapter missing - run setup, or use the Stock launcher." }
                $set += "ablate=$AdapterPath"
            }
            Say ("patched engine {0}: CUDA graphs {1}, {2}" -f $Manifest.engine_version, $(if ($cfg.cuda_graphs) { "on" } else { "off" }), $(if ($Stock) { "stock model" } else { "abliterated" }))
        }
        foreach ($s in $set) { $la += @("--set", $s) }
        $la += @("--vision", $cfg.vision, "--yes")
        & $StrataCmd @la
    }
    "status" {
        $eng = Get-Engine
        Say "StrataRig release $($Manifest.release), built for engine $($Manifest.engine_version) ($($Manifest.archs -join ', '))"
        Say ("Strata installed: {0}" -f (Test-Path $StrataCmd))
        if ($eng) {
            $cur = (Get-FileHash (Join-Path $eng.Dir "strata-dsv41.exe")).Hash
            $mine = Join-Path $RigHome ("engine\" + $Manifest.engine_version + "\strata-dsv41.exe")
            $which = if ($cur -ieq $eng.OfficialSha) { "official" } elseif ((Test-Path $mine) -and $cur -ieq (Get-FileHash $mine).Hash) { "StrataRig patched" } else { "unknown build" }
            Say "Strata's DeepSeek engine: $($eng.Version) ($which) in $($eng.Dir)"
            Say ("version match: {0}" -f ($eng.Version -eq $Manifest.engine_version))
        } else { Say "no DeepSeek engine installed by Strata yet" }
        Say ("adapter: {0}" -f (Test-Path $AdapterPath))
    }
    "restore" {
        $eng = Get-Engine
        if (-not $eng) { Say "no DeepSeek engine installed"; break }
        $bak = Join-Path $eng.Dir "strata-dsv41.exe.official"
        if (-not (Test-Path $bak)) { Say "no saved official engine in $($eng.Dir)"; break }
        Copy-Item $bak (Join-Path $eng.Dir "strata-dsv41.exe") -Force
        Say "official engine $($eng.Version) restored"
    }
}
