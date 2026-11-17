#!/usr/bin/env bash
# Despliega (actualiza y publica) un workflow de n8n desde su JSON versionado
# usando la API pública de n8n, con n8n en marcha.
#
# Sustituye al despliegue anterior por CLI (import:workflow + publish:workflow
# con n8n parado), que dejaba a n8n sirviendo la versión ANTERIOR del workflow
# durante ~19 s tras arrancar (AGNOSTIC-12): publish:workflow no actualizaba
# workflow_published_version. Vía API, n8n publica la versión en caliente.
#
# Requisitos: n8n levantado, N8N_API_KEY en .env (Settings > n8n API), jq.
#
# Uso (desde agnosticflow/):
#   ./n8n/scripts/desplegar_workflow.sh [ruta_json]
# Por defecto: n8n/workflows/ingesta_webhook.json

set -euo pipefail

cd "$(dirname "$0")/../.."

WF="${1:-n8n/workflows/ingesta_webhook.json}"

set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${N8N_API_KEY:?ERROR: falta N8N_API_KEY en .env}"
BASE="http://127.0.0.1:${N8N_PORT:-5678}"
API="$BASE/api/v1"

if ! jq -e . "$WF" >/dev/null; then
    echo "ERROR: $WF no es un JSON válido" >&2
    exit 1
fi

ID=$(jq -r '.id // empty' "$WF")
if [ -z "$ID" ]; then
    echo "ERROR: $WF no tiene campo id" >&2
    exit 1
fi

# api MÉTODO RUTA [cuerpo] -> imprime el cuerpo de la respuesta; deja el
# código HTTP en $HTTP_CODE
RESP=$(mktemp)
trap 'rm -f "$RESP"' EXIT
api() {
    local args=(-s -o "$RESP" -w '%{http_code}' -m 15 -X "$1"
        -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Accept: application/json')
    if [ $# -ge 3 ]; then
        args+=(-H 'Content-Type: application/json' --data-binary "$3")
    fi
    HTTP_CODE=$(curl "${args[@]}" "$API$2" || echo 000)
}

api GET "/workflows/$ID"
case "$HTTP_CODE" in
    200) ;;
    404)
        # La API no permite elegir el id al crear, así que la primera vez se
        # importa por CLI (conserva el id del JSON) y luego se sigue por API.
        echo "El workflow $ID no existe en n8n: importándolo por CLI..."
        docker compose exec -T n8n sh -c \
            "cat > /tmp/wf.json && n8n import:workflow --input=/tmp/wf.json" \
            < "$WF" 2>&1 | grep -vE 'license SDK|^\s*$' || true
        ;;
    401|403)
        echo "ERROR: N8N_API_KEY rechazada por n8n (HTTP $HTTP_CODE)" >&2
        exit 1 ;;
    000)
        echo "ERROR: n8n no responde en $BASE (¿está levantado?)" >&2
        exit 1 ;;
    *)
        echo "ERROR: GET /workflows/$ID -> HTTP $HTTP_CODE" >&2
        cat "$RESP" >&2; exit 1 ;;
esac

echo "Actualizando $WF (id $ID)..."
BODY=$(jq -c '{name, nodes, connections, settings: (.settings // {})}' "$WF")
api PUT "/workflows/$ID" "$BODY"
if [ "$HTTP_CODE" != 200 ]; then
    echo "ERROR: PUT /workflows/$ID -> HTTP $HTTP_CODE" >&2
    cat "$RESP" >&2; echo >&2; exit 1
fi

echo "Publicando..."
api POST "/workflows/$ID/activate"
if [ "$HTTP_CODE" != 200 ]; then
    echo "ERROR: POST /workflows/$ID/activate -> HTTP $HTTP_CODE" >&2
    cat "$RESP" >&2; echo >&2; exit 1
fi

echo "Workflow publicado (versión $(jq -r '.versionId // "?"' "$RESP"))"
