#!/usr/bin/env bash
# Importa y publica un workflow de n8n desde su JSON versionado.
#
# ⚠️ PROBLEMA CONOCIDO (AGNOSTIC-12, pendiente de resolver):
# después de cada despliegue, n8n 2.45 sigue sirviendo la versión ANTERIOR
# del workflow durante unos 19 s tras arrancar. Pasa aunque n8n esté parado
# durante la importación. Motivo: publish:workflow no actualiza la tabla
# interna workflow_published_version, y n8n no la sincroniza hasta pasados
# unos segundos desde el arranque. En el E3 se comprobó que el webhook
# aceptaba peticiones sin token justo después de activar la autenticación.
# Solución prevista: desplegar con la API pública de n8n (N8N_API_KEY).
#
# Uso (desde agnosticflow/ con postgres levantado):
#   ./n8n/scripts/desplegar_workflow.sh [ruta_json]
# Por defecto: n8n/workflows/ingesta_webhook.json

set -euo pipefail

cd "$(dirname "$0")/../.."

WF="${1:-n8n/workflows/ingesta_webhook.json}"

if ! jq -e . "$WF" >/dev/null; then
    echo "ERROR: $WF no es un JSON válido" >&2
    exit 1
fi

ID=$(jq -r '.id // empty' "$WF")
if [ -z "$ID" ]; then
    echo "ERROR: $WF no tiene campo id" >&2
    exit 1
fi

echo "Parando n8n..."
docker compose stop n8n >/dev/null 2>&1

echo "Importando y publicando $WF (id $ID)..."
docker compose run --rm -T --no-deps --entrypoint sh n8n -c \
    "cat > /tmp/wf.json \
     && n8n import:workflow --input=/tmp/wf.json \
     && n8n publish:workflow --id=$ID" \
    < "$WF" 2>&1 | grep -vE 'license SDK|^\s*$'

echo "Arrancando n8n..."
docker compose up -d n8n >/dev/null 2>&1

# Esperar a que el webhook quede registrado (deja de responder 404)
for _ in $(seq 1 60); do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 2 -X POST \
        "http://127.0.0.1:${N8N_PORT:-$(grep -oP '^N8N_PORT=\K.*' .env 2>/dev/null || echo 5678)}/webhook/ingesta" || true)
    if [ "$CODE" != "000" ] && [ "$CODE" != "404" ]; then
        echo "Workflow activo (respuesta de prueba: HTTP $CODE)"
        exit 0
    fi
    sleep 1
done

echo "ERROR: el webhook no se ha registrado tras 60 s" >&2
exit 1
