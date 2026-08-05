# Publica una nueva versión de la app de punta a punta, sin pasos manuales:
#   1) Lee la versión actual de pubspec.yaml (la subes ahí como siempre).
#   2) Compila el APK de producción.
#   3) Lo copia a pagina-web/public/downloads/CorporacionRonceros-latest.apk
#      (nombre fijo: el enlace de descarga nunca cambia, solo el archivo).
#   4) Sube esos cambios a GitHub (dispara el redeploy de la landing en Vercel).
#   5) Marca esa versión como mínima requerida en el backend — cualquiera
#      con una versión menor ve el bloqueo de actualización obligatoria en
#      su próximo intento de abrir la app.
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

Write-Host "=== Publicando version $version ===" -ForegroundColor Cyan

Write-Host "`n[1/4] Compilando APK de produccion..." -ForegroundColor Yellow
flutter build apk --release --dart-define=API_BASE_URL=https://panaderia-backend-2xvd.onrender.com/api
if ($LASTEXITCODE -ne 0) { Write-Error "Fallo la compilacion del APK"; exit 1 }

Write-Host "`n[2/4] Copiando APK a la landing..." -ForegroundColor Yellow
$origen = 'build\app\outputs\flutter-apk\app-release.apk'
$destino = 'pagina-web\public\downloads\CorporacionRonceros-latest.apk'
Copy-Item -Path $origen -Destination $destino -Force
Write-Host "Copiado a $destino"

Write-Host "`n[3/4] Subiendo a GitHub..." -ForegroundColor Yellow
git add $destino
git commit -m "Publicar version $version del APK"
git push origin main
if ($LASTEXITCODE -ne 0) { Write-Error "Fallo el push a GitHub"; exit 1 }

Write-Host "`n[4/4] Marcando $version como version minima requerida..." -ForegroundColor Yellow
Push-Location backend_server
node scripts/actualizar_version_minima.js $version
$codigoNode = $LASTEXITCODE
Pop-Location
if ($codigoNode -ne 0) { Write-Error "Fallo al actualizar la version minima en el backend"; exit 1 }

Write-Host "`n=== Listo: version $version publicada y forzada ===" -ForegroundColor Green
