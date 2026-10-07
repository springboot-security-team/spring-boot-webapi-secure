# Despliegue local (CD) de la imagen construida en CI

El workflow **CI - Imagen y escaneo con Trivy** (`.github/workflows/ci-container-trivy.yml`)
construye la imagen del proyecto, la escanea con Trivy y la publica como artifact. El
despliegue local se inicia manualmente a partir de ese artifact: se despliega exactamente
la imagen que fue escaneada.

## Qué publica el pipeline

| Artifact | Contenido |
|---|---|
| `imagen-contenedor` | `springboot-devsecops-lab-<sha>.tar.gz` (salida de `docker save`) y `imagen-version.txt` |
| `trivy-reports` | `trivy-report.json`, `trivy-version.txt` e `imagen-version.txt` |

`imagen-version.txt` identifica la versión sin depender de una etiqueta mutable como `latest`:

```text
commit=<sha del commit>
imagen=springboot-devsecops-lab:<sha del commit>
image_config_digest=sha256:<digest de configuración de la imagen>
archivo=springboot-devsecops-lab-<sha>.tar.gz
archivo_sha256=<sha256 del archivo exportado>
run=<enlace a la ejecución de GitHub Actions>
```

La imagen lleva además la etiqueta OCI `org.opencontainers.image.revision=<sha del commit>`.

## Requisitos

- Docker Desktop (o Docker Engine) con Docker Compose v2.
- macOS / Linux: Bash. Windows: Git Bash o WSL para el script, o PowerShell para los pasos manuales.
- Opcional: GitHub CLI (`gh`) autenticado, para descargar el artifact desde la terminal.

## Opción A: script (macOS, Linux, Git Bash o WSL)

Obtener el identificador de la ejecución en la URL de GitHub Actions
(`.../actions/runs/<run-id>`) o con:

```bash
gh run list --workflow "CI - Imagen y escaneo con Trivy" --limit 5
```

Desplegar:

```bash
# Descarga el artifact de esa ejecución y despliega
./scripts/deploy-local.sh <run-id>

# O bien, con el artifact descargado y descomprimido manualmente desde la web
./scripts/deploy-local.sh --dir <carpeta-del-artifact>

# Detener
./scripts/deploy-local.sh --down
```

El script:

1. Descarga el artifact `imagen-contenedor` en `dist/run-<run-id>/` (ignorado por git).
2. Comprueba el `sha256` del archivo y que el digest de configuración del `.tar.gz` coincida con el registrado en CI.
3. Carga la imagen con `docker load` y verifica que su etiqueta `revision` sea el commit indicado.
4. La ejecuta con `docker compose` usando `IMAGE_TAG=<sha del commit>`.
5. Comprueba `/actuator/health` y `GET /api/products/search?name=Laptop`.

## Opción B: pasos manuales (cualquier sistema, incluido PowerShell)

1. En GitHub, abrir la ejecución, sección **Artifacts**, descargar `imagen-contenedor` y descomprimirlo.
2. Verificar el archivo (comparar con `archivo_sha256` de `imagen-version.txt`):

   ```powershell
   Get-FileHash .\springboot-devsecops-lab-<sha>.tar.gz -Algorithm SHA256   # PowerShell
   ```
   ```bash
   shasum -a 256 springboot-devsecops-lab-<sha>.tar.gz                       # macOS / Linux
   ```

3. Cargar la imagen y comprobar el commit:

   ```bash
   docker load --input springboot-devsecops-lab-<sha>.tar.gz
   docker image inspect --format "{{ index .Config.Labels \"org.opencontainers.image.revision\" }}" springboot-devsecops-lab:<sha>
   ```

4. Ejecutar desde la raíz del repositorio:

   ```powershell
   $env:IMAGE_TAG = "<sha>"; docker compose up -d       # PowerShell
   ```
   ```bash
   IMAGE_TAG=<sha> docker compose up -d                 # macOS / Linux
   ```

5. Comprobar:

   ```bash
   curl http://127.0.0.1:8080/actuator/health
   curl "http://127.0.0.1:8080/api/products/search?name=Laptop"
   ```

6. Detener con `docker compose down` (con `IMAGE_TAG` definido como en el paso 4).

## Configuración del contenedor

`docker-compose.yml` publica el puerto solo en `127.0.0.1` porque la aplicación es
deliberadamente vulnerable. El contenedor se ejecuta con el usuario sin privilegios `spring`,
sistema de archivos de solo lectura (con `/tmp` en memoria), sin capacidades de Linux y con
`no-new-privileges`. No requiere variables ni secretos.
