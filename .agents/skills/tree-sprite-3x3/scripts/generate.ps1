<#
.SYNOPSIS
  Generate a new pixel-art tree sprite sheet (default 1x4, 21:9, 2K, high) from a reference sheet
  with libtv (image2image) and download it.
.EXAMPLE
  & generate.ps1 -Ref ref_1x4.png -Name trees_gen_v3 -OutDir out `
    -Items "big round oak","orange tree","ginkgo","baobab"
.EXAMPLE
  # old 3x3 square layout
  & generate.ps1 -Ref ref_3x3.png -Name t33 -Rows 3 -Cols 3 -Ratio 1:1 -Items a,b,c,d,e,f,g,h,i
#>
param(
  [Parameter(Mandatory)] [string]$Ref,          # local reference image, or existing node key / node name
  [Parameter(Mandatory)] [string]$Name,         # canvas node name (unique) and output file stem
  [string[]]$Items = @(),                       # one description per cell (reading order) -> {STYLE}
  [string]$ExtraRules = "",                     # -> {EXTRA_RULES}
  [string]$PromptFile = "",                     # default: templates/tree_prompt.txt
  [int]$Rows = 1,                               # grid -> {LAYOUT} / {COUNT}; must match the reference sheet
  [int]$Cols = 4,
  [string]$Model = "Lib Image 2.6 Pro",
  [string]$Ratio = "21:9",                      # 21:9 @ 2K = 2016x864 -> 1x4 cells of 504x864
  [string]$Quality = "high",                    # model specific, e.g. high (Lib Image) / 2K (Seedream)
  [string]$Resolution = "2K",                   # Lib Image only: 1K/2K/4K; pass "" for other models
  [string]$Background = "transparent",
  [int]$Count = 1,
  [string]$OutDir = ".",
  [int]$X = 1200,
  [int]$Y = 18000,
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

# --- reference node (upload local file once; cached by sha1 in .libtv/ref_cache.json) ---
$refKey = $Ref
if (($Ref -match '\.(png|jpe?g|webp)$') -and -not (Test-Path $Ref -PathType Leaf)) { throw "Reference file not found: $Ref" }
if (Test-Path $Ref -PathType Leaf) {
  $cacheFile = ".libtv/ref_cache.json"; $cache = @{}
  if (Test-Path $cacheFile) { (Get-Content -Raw $cacheFile | ConvertFrom-Json).PSObject.Properties | % { $cache[$_.Name] = $_.Value } }
  $sha = (Get-FileHash -Algorithm SHA1 $Ref).Hash
  if ($cache.ContainsKey($sha)) { $refKey = $cache[$sha] }
  else {
    $refName = "ref_" + [IO.Path]::GetFileNameWithoutExtension($Ref) + "_" + $sha.Substring(0, 6)
    $up = Invoke-Libtv @("upload", $refName, "-t", "image", "-f", $Ref, "--x", "0", "--y", "$Y") $null
    $refKey = ($up | ConvertFrom-Json).nodeKey
    if (-not $refKey) { throw "Upload failed: $up" }
    $cache[$sha] = $refKey; $cache | ConvertTo-Json | Set-Content -Encoding UTF8 $cacheFile
    Write-Host "[ref] uploaded $Ref -> $refKey"
  }
}

# --- prompt ---
if (-not $PromptFile) { $PromptFile = Join-Path $skill "templates/tree_prompt.txt" }
$prompt = (Get-Content -Raw -Encoding UTF8 $PromptFile).Trim()
$list = ""; $n = 0
foreach ($it in $Items) { $n++; $list += "$n. $($it.Trim())`n" }
$extra = if ($ExtraRules) { $ExtraRules.Trim() + "`n`n" } else { "" }
$cells = $Rows * $Cols
if ($Items.Count -and $Items.Count -ne $cells) { Write-Warning "$($Items.Count) items for a ${Rows}x${Cols} grid ($cells cells)" }
$layout = if ($Rows -eq 1) { "a single horizontal row of $Cols trees side by side, 1 row by $Cols columns" } else { "$Rows rows by $Cols columns" }
$prompt = $prompt.Replace("{REF}", "{{Node $refKey}}").Replace("{STYLE}", $list.TrimEnd()).Replace("{EXTRA_RULES}", $extra)
$prompt = $prompt.Replace("{COUNT}", "$cells").Replace("{LAYOUT}", $layout)
$prompt = $prompt -replace '"', "'"   # PS 5.1 breaks embedded double quotes in native args

# --- create + run (blocks until finished) ---
$a = @("node", "--x", "$X", "--y", "$Y", "create", $Name, "-t", "image", "--left", $refKey,
  "-s", "model=$Model", "-s", "modeType=image2image", "-s", "ratio=$Ratio", "-s", "count=$Count")
if ($Quality) { $a += @("-s", "quality=$Quality") }
if ($Resolution) { $a += @("-s", "resolution=$Resolution") }
if ($Background) { $a += @("-s", "background=$Background") }
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
  $file = if ($urls.Count -eq 1) { "$Name.png" } else { "${Name}_$i.png" }
  $path = Join-Path $OutDir $file
  Invoke-WebRequest $u -OutFile $path
  Write-Output (Resolve-Path $path).Path
}


