<#
.SYNOPSIS
  Generate a rotation-consistent variant of a building sprite sheet with libtv and download it.
.EXAMPLE
  & generate.ps1 -Ref assets/buildings/spacious_house/sheet.png -Name house_var_brick `
    -Style "a red BRICK house with a terracotta TILE roof" -OutDir out
#>
param(
  [Parameter(Mandatory)] [string]$Ref,          # local image path, or existing node key / node name
  [Parameter(Mandatory)] [string]$Name,         # canvas node name (must be unique); also output file stem
  [string]$Style = "",                          # fills {STYLE}
  [string]$ExtraRules = "",                     # fills {EXTRA_RULES} (per-frame rules for asymmetric parts)
  [string]$PromptFile = "",                     # custom template; default templates/rotation_prompt.txt
  [string]$Model = "Lib Image 2.6 Pro",
  [string]$Ratio = "21:9",
  [string]$Quality = "high",
  [string]$Resolution = "2K",
  [string]$Background = "transparent",
  [int]$Count = 1,
  [string]$OutDir = ".",
  [int]$X = 1200,
  [int]$Y = 8000,
  [string[]]$ExtraSet = @()                     # extra "key=value" generator params
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$skill = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path ".libtv/project.json")) { throw "No .libtv/project.json in $(Get-Location). Run 'libtv project use <canvas-uuid>' first." }

# --- resolve reference node (upload local file once, cache by sha1) ---
$refKey = $Ref
if (Test-Path $Ref -PathType Leaf) {
  $cacheFile = ".libtv/ref_cache.json"
  $cache = @{}
  if (Test-Path $cacheFile) { (Get-Content -Raw $cacheFile | ConvertFrom-Json).PSObject.Properties | % { $cache[$_.Name] = $_.Value } }
  $sha = (Get-FileHash -Algorithm SHA1 $Ref).Hash
  if ($cache.ContainsKey($sha)) {
    $refKey = $cache[$sha]
  } else {
    $refName = "ref_" + [IO.Path]::GetFileNameWithoutExtension((Split-Path (Split-Path $Ref -Parent) -Leaf)) + "_" + $sha.Substring(0, 6)
    $ErrorActionPreference = "Continue"
    $up = (& libtv upload $refName -t image -f $Ref --x 0 --y $Y 2>$null) | Out-String
    $ErrorActionPreference = "Stop"
    $refKey = ($up | ConvertFrom-Json).nodeKey
    if (-not $refKey) { throw "Upload failed: $up" }
    $cache[$sha] = $refKey
    $cache | ConvertTo-Json | Set-Content -Encoding UTF8 $cacheFile
    Write-Host "[ref] uploaded $Ref -> $refKey"
  }
}

# --- build prompt ---
if (-not $PromptFile) { $PromptFile = Join-Path $skill "templates/rotation_prompt.txt" }
$prompt = (Get-Content -Raw -Encoding UTF8 $PromptFile).Trim()
$extra = if ($ExtraRules) { $ExtraRules.Trim() + "`n`n" } else { "" }
$prompt = $prompt.Replace("{REF}", "{{Node $refKey}}").Replace("{STYLE}", $Style.Trim()).Replace("{EXTRA_RULES}", $extra)
$prompt = $prompt -replace '"', "'"   # PS 5.1 breaks embedded double quotes in native args

# --- create node + run (blocks until done) ---
$a = @("node", "--x", "$X", "--y", "$Y", "create", $Name, "-t", "image", "--left", $refKey,
  "-s", "model=$Model", "-s", "modeType=image2image", "-s", "ratio=$Ratio", "-s", "quality=$Quality",
  "-s", "resolution=$Resolution", "-s", "background=$Background", "-s", "count=$Count", "--prompt", $prompt)
foreach ($kv in $ExtraSet) { $a += @("-s", $kv) }
$a += "--run"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$errLog = Join-Path $OutDir "$Name.stderr.log"
$ErrorActionPreference = "Continue"   # libtv writes progress to stderr; PS 5.1 + Stop would abort on it
$out = (& libtv @a 2>$errLog) | Out-String
$ErrorActionPreference = "Stop"
Set-Content -Encoding UTF8 (Join-Path $OutDir "$Name.log") $out

# --- download result urls (from the last "url": [...] array = run result) ---
$ms = [regex]::Matches($out, '"url":\s*\[([^\]]*)\]')
$urls = @()
if ($ms.Count) { $urls = [regex]::Matches($ms[$ms.Count - 1].Groups[1].Value, 'https?://[^"\s]+') | % { $_.Value } }
if (-not $urls) { throw "Generation failed or produced no image. See $errLog and $(Join-Path $OutDir "$Name.log")" }
$i = 0
foreach ($u in $urls) {
  $i++
  $file = if ($urls.Count -eq 1) { "$Name.png" } else { "${Name}_$i.png" }
  $path = Join-Path $OutDir $file
  Invoke-WebRequest $u -OutFile $path
  Write-Output (Resolve-Path $path).Path
}
