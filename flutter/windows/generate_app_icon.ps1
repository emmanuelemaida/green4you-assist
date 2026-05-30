# Genera un'icona Windows multi-risoluzione (.ico) Green4You Assist da un PNG sorgente.
# Le voci sono PNG-compressed (formato ICO Vista+), preserva la trasparenza.
# Uso (dal tool PowerShell):  & .\generate_app_icon.ps1
#       (opz.) -Source <png> -Out <ico>
param(
  [string]$Source = "$PSScriptRoot\..\assets\logo.png",
  [string]$Out    = "$PSScriptRoot\runner\resources\app_icon.ico"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $Source)) { throw "Sorgente non trovata: $Source" }
$srcPath = (Resolve-Path $Source).Path
$src = [System.Drawing.Image]::FromFile($srcPath)
Write-Host ("Sorgente: {0} ({1}x{2})" -f $srcPath, $src.Width, $src.Height)

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()
foreach ($s in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap -ArgumentList $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, 0, 0, $s, $s)
  $g.Dispose()
  $msPng = New-Object System.IO.MemoryStream
  $bmp.Save($msPng, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $pngs += ,($msPng.ToArray())
  $msPng.Dispose()
}
$src.Dispose()

# Assembla il contenitore ICO (ICONDIR + ICONDIRENTRY[] + dati PNG) byte per byte.
$ms = New-Object System.IO.MemoryStream
function Write-Bytes([byte[]]$b) { $ms.Write($b, 0, $b.Length) }
Write-Bytes ([BitConverter]::GetBytes([uint16]0))            # reserved
Write-Bytes ([BitConverter]::GetBytes([uint16]1))            # type = icon
Write-Bytes ([BitConverter]::GetBytes([uint16]$sizes.Count)) # count

$offset = 6 + (16 * $sizes.Count)
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $data = $pngs[$i]
  $dim = [byte]($(if ($s -ge 256) { 0 } else { $s }))
  Write-Bytes ([byte[]]@($dim, $dim, 0, 0))                  # w, h, palette, reserved
  Write-Bytes ([BitConverter]::GetBytes([uint16]1))          # color planes
  Write-Bytes ([BitConverter]::GetBytes([uint16]32))         # bpp
  Write-Bytes ([BitConverter]::GetBytes([uint32]$data.Length))
  Write-Bytes ([BitConverter]::GetBytes([uint32]$offset))
  $offset += $data.Length
}
foreach ($data in $pngs) { Write-Bytes $data }

$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
[System.IO.File]::WriteAllBytes($Out, $ms.ToArray())
$ms.Dispose()
Write-Host ("Scritto: {0} ({1} byte, {2} risoluzioni)" -f $Out, (Get-Item $Out).Length, $sizes.Count)
