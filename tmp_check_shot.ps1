Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile("E:\pixel_world\tmp_sidepanel_check.png")
Write-Output ("size: {0} x {1}" -f $bmp.Width, $bmp.Height)
$cols = 5, 90, 320, 460, 640, 820, 1000, 1270, 1290, 1400, 1500, 1620, 1635
foreach ($x in $cols) {
    if ($x -ge $bmp.Width) { continue }
    $vals = @()
    for ($y = 60; $y -lt 740; $y += 8) {
        $c = $bmp.GetPixel($x, $y)
        $lum = 0.299*$c.R + 0.587*$c.G + 0.114*$c.B
        $vals += $lum
    }
    $mean = ($vals | Measure-Object -Average).Average
    $var = [Math]::Pow(($vals | ForEach-Object { $_*$_.ToString() } | Measure-Object -Sum).Sum, 0) # placeholder
    $sum2 = 0; foreach ($v in $vals) { $sum2 += $v*$v }
    $std = [Math]::Sqrt([Math]::Max(0, $sum2/$vals.Count - $mean*$mean))
    Write-Output ("x={0,5}  mean_lum={1,7:N1}  std={2,6:N1}  rows={3}" -f $x, $mean, $std, $vals.Count)
}
$bmp.Dispose()
