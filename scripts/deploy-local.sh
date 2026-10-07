#!/usr/bin/env bash
# Despliegue local (CD) de la imagen construida por el workflow "CI - Imagen y escaneo con Trivy".
#
# Uso:
#   scripts/deploy-local.sh <run-id>          Descarga el artifact con gh y despliega
#   scripts/deploy-local.sh --dir <carpeta>   Usa un artifact descargado manualmente desde GitHub
#   scripts/deploy-local.sh --down            Detiene el despliegue
set -euo pipefail

cd "$(dirname "$0")/.."

ARTIFACT=imagen-contenedor
URL=http://127.0.0.1:8080

# Compatibilidad macOS / Linux / Windows (Git Bash o WSL)
if command -v sha256sum >/dev/null 2>&1; then SHA256="sha256sum"; else SHA256="shasum -a 256"; fi
if command -v python3 >/dev/null 2>&1; then PYTHON=python3; else PYTHON=python; fi

if [[ "${1:-}" == "--down" ]]; then
  IMAGE_TAG="${IMAGE_TAG:-sin-uso}" docker compose down
  exit 0
fi

# 1. Obtener el artifact de la ejecucion de GitHub Actions
if [[ "${1:-}" == "--dir" && -n "${2:-}" ]]; then
  DIR="$2"
elif [[ -n "${1:-}" ]]; then
  DIR="dist/run-$1"
  rm -rf "$DIR"
  echo ">> Descargando artifact '$ARTIFACT' de la ejecucion $1"
  gh run download "$1" --name "$ARTIFACT" --dir "$DIR"
else
  sed -n '3,7p' "$0"
  exit 1
fi

VERSION_FILE=$(find "$DIR" -name imagen-version.txt | head -1)
[[ -f "$VERSION_FILE" ]] || { echo "No se encontro imagen-version.txt en $DIR"; exit 1; }

valor() { grep "^$1=" "$VERSION_FILE" | cut -d= -f2- | tr -d '\r'; }
COMMIT=$(valor commit)
IMAGEN=$(valor imagen)
DIGEST_ESPERADO=$(valor image_config_digest)
ARCHIVO="$DIR/$(valor archivo)"
SHA_ESPERADO=$(valor archivo_sha256)

echo ">> Version a desplegar"
cat "$VERSION_FILE"

# 2. Verificar la integridad del archivo y la identidad de la imagen antes de cargarla
SHA_LOCAL=$($SHA256 "$ARCHIVO" | cut -d' ' -f1)
[[ "$SHA_LOCAL" == "$SHA_ESPERADO" ]] || { echo "ERROR: el sha256 del archivo no coincide"; exit 1; }

DIGEST_LOCAL=$(gzip -dc "$ARCHIVO" | tar -xO manifest.json \
  | $PYTHON -c 'import json,sys; c=json.load(sys.stdin)[0]["Config"].split("/")[-1]; print("sha256:" + (c[:-5] if c.endswith(".json") else c))')
[[ "$DIGEST_LOCAL" == "$DIGEST_ESPERADO" ]] || { echo "ERROR: el digest de la imagen no coincide"; exit 1; }
echo ">> Archivo e imagen verificados ($DIGEST_LOCAL)"

# 3. Cargar la imagen y comprobar que corresponde al commit
docker load --input "$ARCHIVO"
REVISION=$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$IMAGEN")
[[ "$REVISION" == "$COMMIT" ]] || { echo "ERROR: la imagen no corresponde al commit $COMMIT"; exit 1; }

# 4. Desplegar
export IMAGE_TAG="$COMMIT"
docker compose up -d --force-recreate

# 5. Comprobacion funcional
echo ">> Esperando a que la aplicacion responda"
for _ in $(seq 1 30); do
  curl -fs "$URL/actuator/health" >/dev/null 2>&1 && break
  sleep 2
done

echo ">> GET /actuator/health"
curl -fsS "$URL/actuator/health"; echo
echo ">> GET /api/products/search?name=Laptop"
curl -fsS "$URL/api/products/search?name=Laptop"; echo

echo ">> Desplegado $IMAGEN (commit $COMMIT, digest $DIGEST_LOCAL) en $URL"
