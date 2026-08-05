# tools/make-icon.ps1 -- build launcher/easyanalysis.ico from favicon.png
#
# WHY
# ---
# The Desktop shortcut created by install.ps1 had no icon of its own, so Windows
# fell back to the PowerShell icon: functional, but it does not look like an app.
# We already have artwork (favicon.png), so the shortcut should use it.
#
# HOW
# ---
# Uses System.Drawing (ships with Windows) rather than an R image package or
# ImageMagick, so regenerating the icon needs nothing installed.
#
# The .ico embeds PNG payloads, which Windows Vista+ reads at every size. Several
# sizes are included because Windows picks per context -- 16px in the taskbar's
# small mode, 32px on the Desktop, 256px in large-icon view. Shipping only 256
# makes Windows downscale badly at 16px.
#
# Usage:  pwsh -File tools/make-icon.ps1        (run from the repo root)
# The OUTPUT IS COMMITTED, so this only needs re-running if the artwork changes.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$src = "favicon.png"
$out = "launcher/easyanalysis.ico"
if (-not (Test-Path $src)) { throw "$src not found - run from the repo root" }
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$img = [System.Drawing.Image]::FromFile((Resolve-Path $src).Path)
Write-Host "source: $src  ($($img.Width)x$($img.Height))"

$pngs = @()
foreach ($s in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap($s, $s)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  # High quality matters most at 16-32px, where a naive resize turns the mark to mush.
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $s, $s)))
  $g.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngs += , @{ size = $s; bytes = $ms.ToArray() }
  $bmp.Dispose(); $ms.Dispose()
}
$img.Dispose()

# --- Assemble the ICO container -------------------------------------------
# Layout: 6-byte header, then one 16-byte directory entry per image, then the
# image data. Offsets are absolute from the start of the file, so they can only
# be computed once every entry size is known.
$fs = [System.IO.File]::Create((Join-Path (Get-Location) $out))
$bw = New-Object System.IO.BinaryWriter($fs)

$bw.Write([UInt16]0)                 # reserved
$bw.Write([UInt16]1)                 # type 1 = icon
$bw.Write([UInt16]$pngs.Count)

$offset = 6 + (16 * $pngs.Count)
foreach ($p in $pngs) {
  # 256 is stored as 0 -- the field is a single byte, so 256 does not fit.
  $dim = if ($p.size -ge 256) { 0 } else { $p.size }
  $bw.Write([Byte]$dim)              # width
  $bw.Write([Byte]$dim)              # height
  $bw.Write([Byte]0)                 # palette count (0 = truecolour)
  $bw.Write([Byte]0)                 # reserved
  $bw.Write([UInt16]1)               # colour planes
  $bw.Write([UInt16]32)              # bits per pixel
  $bw.Write([UInt32]$p.bytes.Length)
  $bw.Write([UInt32]$offset)
  $offset += $p.bytes.Length
}
foreach ($p in $pngs) { $bw.Write($p.bytes) }
$bw.Flush(); $bw.Close(); $fs.Close()

$len = (Get-Item $out).Length
Write-Host "wrote $out  ($len bytes, $($pngs.Count) sizes: $($sizes -join ', '))"

# --- Prove Windows can actually read it back ------------------------------
# Writing a malformed ICO is easy and silent; the shortcut would just show a
# blank square. Load it the way Windows will.
$icon = New-Object System.Drawing.Icon((Resolve-Path $out).Path)
Write-Host "loaded back OK, default size $($icon.Width)x$($icon.Height)"
foreach ($s in 16, 32, 256) {
  $i2 = New-Object System.Drawing.Icon((Resolve-Path $out).Path), (New-Object System.Drawing.Size($s, $s))
  Write-Host ("  requested {0,3}px -> got {1}x{2}" -f $s, $i2.Width, $i2.Height)
  $i2.Dispose()
}
$icon.Dispose()
