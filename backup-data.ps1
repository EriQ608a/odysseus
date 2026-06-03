# Backup de los datos de Odysseus (memoria, skills, sesiones, auth, DB, RAG).
# data/ esta gitignored: este zip es la unica copia recuperable.
# RIESGO: "docker compose down -v" borra los volumenes. Correr esto ANTES.
#
# Estrategia: copia con robocopy (tolera archivos abiertos por el contenedor)
# a un staging temporal, EXCLUYE cachES regenerables (se re-descargan solos y
# ademas contienen symlinks de HuggingFace que Windows no sabe comprimir), y
# comprime esa copia. Para un snapshot 100% consistente de la DB, parar antes
# el stack: "docker compose stop".
$src     = "E:\Proyectos\jarvis-odysseus\data"
$dest    = "D:\Backups\jarvis-odysseus-data"
$stamp   = Get-Date -Format "yyyy-MM-dd_HHmm"
$staging = Join-Path $env:TEMP "odysseus-backup-$stamp"

# Cachs regenerables que NO se respaldan (modelos/binarios re-descargables).
$excludeDirs = @(
    (Join-Path $src "fastembed_cache"),
    (Join-Path $src "huggingface"),
    (Join-Path $src "local"),
    (Join-Path $src "tts_cache")
)

if (-not (Test-Path $src)) {
    Write-Host "No existe $src - nada que respaldar."
    exit 1
}

New-Item -ItemType Directory -Force $dest    | Out-Null
New-Item -ItemType Directory -Force $staging | Out-Null

# /MIR espeja, /XD excluye cachs, /R:1 /W:1 no se cuelga en bloqueados, /XJ
# salta junctions. robocopy devuelve 0-7 en exito; >=8 es error real.
robocopy $src $staging /MIR /XD $excludeDirs /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Host "robocopy fallo (codigo $LASTEXITCODE) - abortando."
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Red de seguridad: eliminar cualquier reparse point (symlink) que sobreviva,
# Compress-Archive no los sabe leer y abortaria todo el zip.
Get-ChildItem $staging -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Attributes -match "ReparsePoint" } |
    ForEach-Object { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }

$zip = "$dest\data-$stamp.zip"
Compress-Archive -Path "$staging\*" -DestinationPath $zip -Force
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
$sizeMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Backup -> $zip ($sizeMB MB)"

# Retencion: conservar los 14 zips mas recientes, borrar el resto.
Get-ChildItem $dest -Filter "data-*.zip" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 14 |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "Purga antiguo: $($_.Name)"
    }

# robocopy deja $LASTEXITCODE en 1 (copio archivos = exito); forzar exito real.
exit 0
