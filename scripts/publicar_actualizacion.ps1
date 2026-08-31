# Prepara una nueva versión para publicar en Play Store:
#   1) Lee la versión actual de pubspec.yaml (la subes ahí como siempre).
#   2) Compila el App Bundle (.aab) de producción, firmado con la llave real
#      (ver android/key.properties) — Play Store solo acepta .aab, no .apk.
#   3) Marca esa versión como mínima requerida en el backend — cualquiera
#      con una versión menor ve el bloqueo de actualización obligatoria
#      (que ahora manda a Play Store) en su próximo intento de abrir la app.
#
# La subida del .aab a Play Console (Producción / Prueba cerrada / etc.)
# sigue siendo manual — Google exige revisar cada release ahí, no se puede
# saltar arrastrando el archivo por script.
#
# Uso: sube el numero de "version:" en pubspec.yaml a mano (como cualquier
# release normal) y despues corre:  .\scripts\publicar_actualizacion.ps1

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

$lineaVersion = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $lineaVersion) {
    Write-Error "No se encontro la linea 'version:' en pubspec.yaml"
    exit 1
}
$versionCompleta = $lineaVersion.Matches[0].Groups[1].Value  # ej. 1.1.0+2
$version = $versionCompleta.Split('+')[0]                    # ej. 1.1.0

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "La version '$version' no tiene el formato esperado (X.Y.Z)"
    exit 1
}

if (-not (Test-Path 'android\key.properties')) {
    Write-Error "No existe android\key.properties — el build quedaria firmado con la llave de debug, Play Console lo va a rechazar."
    exit 1
}

Write-Host "=== Preparando version $version para Play Store ===" -ForegroundColor Cyan

Write-Host "`n[1/2] Compilando App Bundle (.aab) de produccion..." -ForegroundColor Yellow
flutter build appbundle --release --dart-define=API_BASE_URL=https://panaderia-backend-vtdy.onrender.com/api
if ($LASTEXITCODE -ne 0) { Write-Error "Fallo la compilacion del .aab"; exit 1 }

$aab = 'build\app\outputs\bundle\release\app-release.aab'
Write-Host "Listo: $aab"

Write-Host "`n[2/2] Marcando $version como version minima requerida..." -ForegroundColor Yellow
Push-Location backend_server
node scripts/actualizar_version_minima.js $version
$codigoNode = $LASTEXITCODE
Pop-Location
if ($codigoNode -ne 0) { Write-Error "Fallo al actualizar la version minima en el backend"; exit 1 }

Write-Host "`n=== Version $version lista ===" -ForegroundColor Green
Write-Host "Sube manualmente $aab en Play Console (Produccion o Prueba cerrada segun corresponda)." -ForegroundColor Green
