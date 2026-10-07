"""Quality Gate sobre un reporte JSON de Trivy.

Bloquea cuando el numero de vulnerabilidades CRITICAL en librerias
(resultados de clase lang-pkgs) alcanza el umbral indicado.

Uso: python quality_gate_trivy.py trivy-report.json --umbral 3
"""

import argparse
import json
import os
import sys
from collections import Counter

SEVERIDADES = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reporte")
    parser.add_argument("--umbral", type=int, default=3,
                        help="Cantidad de CRITICAL en librerias que bloquea el gate")
    args = parser.parse_args()

    try:
        with open(args.reporte, encoding="utf-8") as file:
            report = json.load(file)
    except (OSError, json.JSONDecodeError) as error:
        print(f"No se pudo leer el reporte de Trivy: {error}")
        sys.exit(2)

    conteo = {"os-pkgs": Counter(), "lang-pkgs": Counter()}
    criticas_librerias = {}

    for result in report.get("Results") or []:
        clase = result.get("Class", "otro")
        for vuln in result.get("Vulnerabilities") or []:
            severidad = vuln.get("Severity", "UNKNOWN")
            conteo.setdefault(clase, Counter())[severidad] += 1

            if clase == "lang-pkgs" and severidad == "CRITICAL":
                # Una misma CVE de la misma libreria cuenta una sola vez
                clave = (vuln.get("VulnerabilityID"), vuln.get("PkgName"),
                         vuln.get("InstalledVersion"))
                criticas_librerias[clave] = vuln.get("FixedVersion") or "sin correccion"

    total = len(criticas_librerias)
    bloqueado = total >= args.umbral

    lineas = [
        "## Quality Gate - Trivy",
        "",
        f"Imagen: `{report.get('ArtifactName', 'desconocida')}`",
        "",
        "| Clase | " + " | ".join(SEVERIDADES) + " |",
        "|---|" + "---|" * len(SEVERIDADES),
    ]
    for clase, contador in conteo.items():
        lineas.append(f"| {clase} | " + " | ".join(str(contador[s]) for s in SEVERIDADES) + " |")

    lineas += ["", f"CRITICAL en librerias: **{total}** (umbral de bloqueo: {args.umbral})", ""]
    if criticas_librerias:
        lineas += ["| CVE | Libreria | Instalada | Corregida en |", "|---|---|---|---|"]
        for (cve, pkg, version), fixed in sorted(criticas_librerias.items()):
            lineas.append(f"| {cve} | {pkg} | {version} | {fixed} |")
        lineas.append("")

    lineas.append("El Quality Gate ha sido **bloqueado**." if bloqueado
                  else "El Quality Gate ha sido **superado**.")

    resumen = "\n".join(lineas)
    print(resumen)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as file:
            file.write(resumen + "\n")

    sys.exit(1 if bloqueado else 0)


if __name__ == "__main__":
    main()
