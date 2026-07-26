# Genera windows/runner/resources/app_icon.ico con TODAS las resoluciones que
# Windows usa, cada una escalada de antemano con buena calidad.
#
# Por qué existe este script en vez de usar flutter_launcher_icons: ese paquete
# genera un .ico con UNA sola imagen (la de icon_size, 256px). La barra de
# tareas dibuja el icono a 24/32px, así que Windows tiene que achicar los 256px
# al vuelo con un escalador de baja calidad — de ahí que se viera pixelado.
# Las apps reales (Discord, Spotify, etc.) embeben todos los tamaños.
#
# Se usa WPF (no System.Drawing) porque compone en alfa premultiplicado: al
# achicar un logo con fondo transparente, GDI+ mezcla el negro de los píxeles
# transparentes y deja un halo oscuro en los bordes. WPF no.
#
# Uso:  powershell -ExecutionPolicy Bypass -File tool\generate_windows_icon.ps1

[CmdletBinding()]
param(
  [string]$Source = "assets/icon/icon_square.png",
  [string]$Output = "windows/runner/resources/app_icon.ico",
  # Los tamaños que Windows pide según contexto y DPI: 16/20/24 barra de
  # tareas y listas, 32/40/48 escritorio y Alt+Tab, 64/96/128/256 vistas
  # grandes y ficha de propiedades.
  [int[]]$Sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationCore, WindowsBase

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $repoRoot $Source
$outPath = Join-Path $repoRoot $Output

if (-not (Test-Path $srcPath)) { throw "No existe la imagen fuente: $srcPath" }

# Cargar la fuente completa en memoria (OnLoad) para no dejar el archivo tomado.
$stream = [System.IO.File]::OpenRead($srcPath)
try {
  # Ojo: no llamar a esta variable $source — PowerShell no distingue
  # mayúsculas y pisaría el parámetro $Source (que es [string]).
  $srcImage = [System.Windows.Media.Imaging.BitmapFrame]::Create(
    $stream,
    [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
    [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
} finally { $stream.Dispose() }

Write-Output ("Fuente: {0}  ({1}x{2})" -f $Source, $srcImage.PixelWidth, $srcImage.PixelHeight)

# Genera una versión de la fuente pre-difuminada A RESOLUCIÓN GRANDE (el blur
# se aplica ACÁ, en espacio de la imagen grande — aplicarlo directo al dibujar
# ya achicado no sirve, ahí el radio queda en unidades del destino chiquito y
# volaría la imagen entera en vez de solo fusionar el detalle fino). El
# resultado se usa como fuente para los tamaños chicos: fusiona líneas de
# brillo/bordes de faceta que a 16-32px ya no entran en un píxel entero y se
# rompen en "confeti" de colores sueltos — el .ico puede estar perfectamente
# armado (10 resoluciones, sin halo) y el logo igual se ve ruidoso ahí si el
# arte tiene detalle más fino que el tamaño de destino.
function New-BlurredSource {
  param($Image, [double]$BlurRadius)

  $size = [Math]::Max($Image.PixelWidth, $Image.PixelHeight)
  $visual = New-Object System.Windows.Media.DrawingVisual
  [System.Windows.Media.RenderOptions]::SetBitmapScalingMode(
    $visual, [System.Windows.Media.BitmapScalingMode]::HighQuality)
  $blur = New-Object System.Windows.Media.Effects.BlurEffect
  $blur.Radius = $BlurRadius
  $blur.KernelType = [System.Windows.Media.Effects.KernelType]::Gaussian
  $visual.Effect = $blur

  $ctx = $visual.RenderOpen()
  $rect = New-Object System.Windows.Rect -ArgumentList 0, 0, $size, $size
  $ctx.DrawImage($Image, $rect)
  $ctx.Close()

  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap -ArgumentList `
    $size, $size, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($visual)
  return $rtb
}

# Escala la fuente (ya sea la nítida o la pre-difuminada) a $size x $size
# devolviendo píxeles Bgra32 (sin premultiplicar).
function Get-ScaledPixels {
  param($Image, [int]$Size)

  $visual = New-Object System.Windows.Media.DrawingVisual
  # HighQuality = Fant, el resampler bueno de WPF (no vecino más cercano).
  [System.Windows.Media.RenderOptions]::SetBitmapScalingMode(
    $visual, [System.Windows.Media.BitmapScalingMode]::HighQuality)

  $ctx = $visual.RenderOpen()
  $rect = New-Object System.Windows.Rect -ArgumentList 0, 0, $Size, $Size
  $ctx.DrawImage($Image, $rect)
  $ctx.Close()

  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap -ArgumentList `
    $Size, $Size, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($visual)

  # El .ico guarda alfa NO premultiplicado — convertir antes de leer píxeles.
  $converted = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap
  $converted.BeginInit()
  $converted.Source = $rtb
  $converted.DestinationFormat = [System.Windows.Media.PixelFormats]::Bgra32
  $converted.EndInit()

  $stride = $Size * 4
  $buffer = New-Object byte[] ($stride * $Size)
  $converted.CopyPixels($buffer, $stride, 0)
  return $buffer
}

# Empaqueta píxeles Bgra32 como DIB de icono: BITMAPINFOHEADER + XOR (abajo
# hacia arriba) + máscara AND. Es el formato que esperan los tamaños chicos.
function ConvertTo-IconDib {
  param([byte[]]$Pixels, [int]$Size)

  $stride = $Size * 4
  $maskStride = [math]::Floor(($Size + 31) / 32) * 4
  $ms = New-Object System.IO.MemoryStream
  $w = New-Object System.IO.BinaryWriter $ms

  $w.Write([uint32]40)            # biSize
  $w.Write([int32]$Size)          # biWidth
  $w.Write([int32]($Size * 2))    # biHeight = alto XOR + alto AND
  $w.Write([uint16]1)             # biPlanes
  $w.Write([uint16]32)            # biBitCount
  $w.Write([uint32]0)             # biCompression = BI_RGB
  $w.Write([uint32]($stride * $Size + $maskStride * $Size)) # biSizeImage
  $w.Write([int32]0)              # biXPelsPerMeter
  $w.Write([int32]0)              # biYPelsPerMeter
  $w.Write([uint32]0)             # biClrUsed
  $w.Write([uint32]0)             # biClrImportant

  # XOR: filas invertidas (el DIB va de abajo hacia arriba).
  for ($y = $Size - 1; $y -ge 0; $y--) {
    $w.Write($Pixels, $y * $stride, $stride)
  }

  # AND: todo en cero. La transparencia real la da el canal alfa de 32bpp,
  # pero la máscara tiene que existir igual o el icono se corrompe.
  $maskRow = New-Object byte[] $maskStride
  for ($y = 0; $y -lt $Size; $y++) { $w.Write($maskRow, 0, $maskStride) }

  $w.Flush()
  $bytes = $ms.ToArray()
  $w.Dispose()
  return $bytes
}

function ConvertTo-IconPng {
  param([byte[]]$Pixels, [int]$Size)

  $bmp = [System.Windows.Media.Imaging.BitmapSource]::Create(
    $Size, $Size, 96, 96,
    [System.Windows.Media.PixelFormats]::Bgra32, $null, $Pixels, $Size * 4)

  $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
  $ms = New-Object System.IO.MemoryStream
  $encoder.Save($ms)
  $bytes = $ms.ToArray()
  $ms.Dispose()
  return $bytes
}

# Umbral: por debajo de este tamaño se usa la fuente pre-difuminada. A partir
# de acá el detalle del logo (líneas de brillo, bordes de faceta) todavía
# entra en pantalla sin romperse.
$smallSizeThreshold = 64
# El radio está en píxeles de la imagen fuente (1168px acá) — proporcional al
# ancho de las líneas finas del logo, no al tamaño final del ícono.
$blurRadius = 26

Write-Output "Generando version pre-difuminada para tamanos chicos (blur=$blurRadius)..."
$blurredImage = New-BlurredSource -Image $srcImage -BlurRadius $blurRadius

# Construir la imagen de cada tamaño.
$images = @()
foreach ($size in ($Sizes | Sort-Object)) {
  $sourceForSize = if ($size -lt $smallSizeThreshold) { $blurredImage } else { $srcImage }
  $pixels = Get-ScaledPixels -Image $sourceForSize -Size $size
  # 256 va como PNG (así lo hacen las apps reales: pesa mucho menos que un DIB
  # de 256KB). Los chicos van como DIB, que es lo más compatible.
  if ($size -ge 256) {
    $data = ConvertTo-IconPng -Pixels $pixels -Size $size
    $kind = "PNG"
  } else {
    $data = ConvertTo-IconDib -Pixels $pixels -Size $size
    $kind = "DIB"
  }
  $images += [pscustomobject]@{ Size = $size; Data = $data; Kind = $kind }
  Write-Output ("  {0,3}x{1,-3} {2}  {3,7:N0} bytes" -f $size, $size, $kind, $data.Length)
}

# Ensamblar el .ico: cabecera + directorio + datos.
$ms = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter $ms

$w.Write([uint16]0)                  # reservado
$w.Write([uint16]1)                  # tipo 1 = icono
$w.Write([uint16]$images.Count)

# Los datos arrancan después de la cabecera (6) + una entrada de 16 por imagen.
$offset = 6 + (16 * $images.Count)
foreach ($img in $images) {
  # 0 significa 256 en el campo de un byte.
  $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
  $w.Write([byte]$dim)               # ancho
  $w.Write([byte]$dim)               # alto
  $w.Write([byte]0)                  # colores de paleta (0 = sin paleta)
  $w.Write([byte]0)                  # reservado
  $w.Write([uint16]1)                # planos
  $w.Write([uint16]32)               # bits por píxel
  $w.Write([uint32]$img.Data.Length)
  $w.Write([uint32]$offset)
  $offset += $img.Data.Length
}
foreach ($img in $images) { $w.Write($img.Data, 0, $img.Data.Length) }

$w.Flush()
$bytes = $ms.ToArray()
$w.Dispose()

$outDir = Split-Path -Parent $outPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
[System.IO.File]::WriteAllBytes($outPath, $bytes)

Write-Output ""
Write-Output ("Listo: {0}" -f $Output)
Write-Output ("{0} resoluciones, {1:N0} bytes" -f $images.Count, $bytes.Length)
