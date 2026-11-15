param(
    [string]$WebDirectory,
    [string]$FirmwareDirectory,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+(\.\d+)?$')]
    [string]$Version,
    [string]$Branch = '9io7adc_uart_web'
)
$ErrorActionPreference = 'Stop'
if (!$FirmwareDirectory) {
    $FirmwareDirectory = Split-Path $PSScriptRoot -Parent
    if (!(Test-Path (Join-Path $FirmwareDirectory 'CMakeLists.txt'))) {
        $FirmwareDirectory = Join-Path $FirmwareDirectory 'modulo_control_ditel_TV_ESP32S3'
    }
}
if (!$WebDirectory) { $WebDirectory = Join-Path (Split-Path $FirmwareDirectory -Parent) 'Leonardo-Benavides.github.io' }
$buildDirectory = Join-Path $firmwareDirectory 'build'
$WebDirectory = (Resolve-Path -LiteralPath $WebDirectory).Path
$config = Get-Content -Raw (Join-Path $buildDirectory 'flasher_args.json') | ConvertFrom-Json
if ($config.extra_esptool_args.chip -ne 'esp32s3') { throw 'Se requiere un build para ESP32-S3.' }
foreach ($part in $config.flash_files.PSObject.Properties) {
    if (!(Test-Path -LiteralPath (Join-Path $buildDirectory $part.Value))) { throw "Falta el binario $($part.Value). Ejecutar idf.py build." }
}
if (@(& git -C $WebDirectory status --porcelain).Count -gt 0) { throw 'El repositorio web tiene cambios pendientes.' }
& git -C $WebDirectory switch $Branch
if ($LASTEXITCODE -ne 0) { throw 'No se pudo seleccionar la rama web.' }
$mergeArguments = @('-m', 'esptool', '--chip', 'esp32s3', 'merge-bin', '--output', (Join-Path $buildDirectory 'merged-binary-esp32s3.bin'), '--flash-mode', $config.flash_settings.flash_mode, '--flash-size', $config.flash_settings.flash_size, '--flash-freq', $config.flash_settings.flash_freq)
foreach ($part in $config.flash_files.PSObject.Properties) {
    $mergeArguments += @($part.Name, (Join-Path $buildDirectory $part.Value))
}
& python @mergeArguments
if ($LASTEXITCODE -ne 0) { throw 'No se pudo generar el binario unificado.' }
$projectName = 'Modulo control Ditel TV'
$manifest = [ordered]@{
    name = "$projectName (ESP32-S3)"
    version = $Version
    builds = @(@{ chipFamily = 'ESP32-S3'; parts = @(@{ path = 'merged-binary-esp32s3.bin'; offset = 0 }) })
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$htmlPath = Join-Path $WebDirectory 'index.html'
$html = [System.IO.File]::ReadAllText($htmlPath)
$html = [regex]::Replace($html, '(<title id="page-title">)[^<]*(</title>)', "`${1}Instalador Web - $projectName`${2}")
$html = [regex]::Replace($html, '(<h2 id="project-heading">)[^<]*(</h2>)', "`${1}Flasheo Web: $projectName`${2}")
$html = [regex]::Replace($html, '(<span class="badge" id="version-badge">)[^<]*(</span>)', "`${1}ESP32-S3 &#8226; v$Version`${2}")
Copy-Item -LiteralPath (Join-Path $buildDirectory 'merged-binary-esp32s3.bin') -Destination (Join-Path $WebDirectory 'merged-binary-esp32s3.bin')
[System.IO.File]::WriteAllText((Join-Path $WebDirectory 'manifest.json'), ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8)
[System.IO.File]::WriteAllText($htmlPath, $html, $utf8)
if ([System.IO.Path]::GetFullPath($PSCommandPath) -ne (Join-Path $WebDirectory 'update-web.ps1')) {
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $WebDirectory 'update-web.ps1')
}
Write-Host "Preparada version $Version en $WebDirectory ($Branch). Revisar, hacer commit y push para publicar."
