<#
.SYNOPSIS
  Generate an empty HD-2D (Octopath Traveler style) side-view battle background with libtv
  image2image, using a STYLE reference (clean battle plate) + a LAYOUT guide (make_layout.py),
  then download it.
.EXAMPLE
  & generate.ps1 -StyleRef refs/forest_plate.png -LayoutRef out/layout.png -Name bg_desert `
    -Scene "desert canyon at sunset with broken sandstone temple pillars" -OutDir out
#>
param(
  [Parameter(Mandatory)] [string]$StyleRef,     # local image, or existing node key / name
  [Parameter(Mandatory)] [string]$LayoutRef,    # local image (make_layout.py), or node key / name; "" to skip
  [Parameter(Mandatory)] [string]$Name,         # canvas node name (unique) and output file stem
  [Parameter(Mandatory)] [string]$Scene,        # -> {SCENE}
  [string]$ExtraRules = "",                     # -> {EXTRA_RULES}
  [string]$PromptFile = "",                     # default: templates/scene_prompt.txt
  [double]$Horizon = 0.40,                      # keep equal to make_layout.py values
  [double]$Ground = 0.52,
  [double]$Fg = 0.94,
  [string]$Model = "General image Pro",
  [string]$Ratio = "16:9",
  [string]$Quality = "2K",                      # General image Pro: 1K/2K/4K
  [int]$Count = 1,
  [string]$OutDir = ".",
  [int]$X = 1400,
  [int]$Y = 30000,
  [string[]]$ExtraSet = @()                     # extra "key=value" generator params
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$skill = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path ".libtv/project.json")) { throw "No .libtv/project.json in $(Get-Location). Run 'libtv project use <canvas-uuid>' first." }

function Invoke-Libtv([string[]]$argv, [string]$errFile) {
  $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"  # libtv logs progress to stderr
  try { if ($errFile) { (& libtv @argv 2>$errFile) | Out-String } else { (& libtv @argv 2>$null) | Out-String } }
  finally { $ErrorActionPreference = $old }
}

# upload local file once; cached by sha1 in .libtv/ref_cache.json
function Resolve-Ref([string]$ref, [int]$yPos) {
  if (($ref -match '\.(png|jpe?g|webp)$') -and -not (Test-Path $ref -PathType Leaf)) { throw "Reference file not found: $ref" }
  if (-not (Test-Path $ref -PathType Leaf)) { return $ref }
  $cacheFile = ".libtv/ref_cache.json"; $cache = @{}
  if (Test-Path $cacheFile) { (Get-Content -Raw $cacheFile | ConvertFrom-Json).PSObject.Properties | % { $cache[$_.Name] = $_.Value } }
  $sha = (Get-FileHash -Algorithm SHA1 $ref).Hash
  if ($cache.ContainsKey($sha)) { return $cache[$sha] }
  $refName = "ref_" + [IO.Path]::GetFileNameWithoutExtension($ref) + "_" + $sha.Substring(0, 6)
  $up = Invoke-Libtv @("upload", $refName, "-t", "image", "-f", $ref, "--x", "0", "--y", "$yPos") $null
  $key = ($up | ConvertFrom-Json).nodeKey
  if (-not $key) { throw "Upload failed: $up" }
  $cache[$sha] = $key; $cache | ConvertTo-Json | Set-Content -Encoding UTF8 $cacheFile
  Write-Host "[ref] uploaded $ref -> $key"
  return $key
}

$styleKey = Resolve-Ref $StyleRef $Y
$layoutKey = if ($LayoutRef) { Resolve-Ref $LayoutRef ($Y + 500) } else { "" }

# --- prompt ---
if (-not $PromptFile) { $PromptFile = Join-Path $skill "templates/scene_prompt.txt" }
$prompt = (Get-Content -Raw -Encoding UTF8 $PromptFile).Trim()
$pct = { param($f) [string][int][math]::Round($f * 100) }
$extra = if ($ExtraRules) { $ExtraRules.Trim() + "`n`n" } else { "" }
$layoutTok = if ($layoutKey) { "{{Node $layoutKey}}" } else { "(no layout image)" }
$prompt = $prompt.Replace("{STYLE_REF}", "{{Node $styleKey}}").Replace("{LAYOUT_REF}", $layoutTok)
$prompt = $prompt.Replace("{SCENE}", $Scene.Trim()).Replace("{EXTRA_RULES}", $extra)
$prompt = $prompt.Replace("{HORIZON_PCT}", (& $pct $Horizon)).Replace("{GROUND_PCT}", (& $pct $Ground))
$prompt = $prompt.Replace("{FG_PCT}", (& $pct $Fg)).Replace("{FG_STRIP_PCT}", (& $pct (1 - $Fg)))
$prompt = $prompt -replace '"', "'"   # PS 5.1 breaks embedded double quotes in native args

# --- create + run (blocks until finished) ---
$a = @("node", "--x", "$X", "--y", "$Y", "create", $Name, "-t", "image", "--left", $styleKey)
if ($layoutKey) { $a += @("--left", $layoutKey) }
$a += @("-s", "model=$Model", "-s", "modeType=image2image", "-s", "ratio=$Ratio", "-s", "count=$Count")
if ($Quality) { $a += @("-s", "quality=$Quality") }
foreach ($kv in $ExtraSet) { $a += @("-s", $kv) }
$a += @("--prompt", $prompt, "--run")
New-Item -ItemType Directory -Force $OutDir | Out-Null
$errLog = Join-Path $OutDir "$Name.stderr.log"
$out = Invoke-Libtv $a $errLog
Set-Content -Encoding UTF8 (Join-Path $OutDir "$Name.log") $out

# --- download (last "url": [...] = run result) ---
$ms = [regex]::Matches($out, '"url":\s*\[([^\]]*)\]')
$urls = @()
if ($ms.Count) { $urls = @([regex]::Matches($ms[$ms.Count - 1].Groups[1].Value, 'https?://[^"\s]+') | % { $_.Value }) }
if (-not $urls) { throw "Generation failed / no image. See $errLog and $(Join-Path $OutDir "$Name.log")" }
$i = 0
foreach ($u in $urls) {
  $i++
  $ext = [IO.Path]::GetExtension(($u -split '\?')[0]); if (-not $ext) { $ext = ".png" }
  $file = if ($urls.Count -eq 1) { "$Name$ext" } else { "${Name}_$i$ext" }
  $path = Join-Path $OutDir $file
  Invoke-WebRequest $u -OutFile $path
  Write-Output (Resolve-Path $path).Path
}
