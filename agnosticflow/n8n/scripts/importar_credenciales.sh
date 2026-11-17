#!/usr/bin/env bash
# Crea (o actualiza) en n8n las credenciales que usa AgnosticFlow,
# leyendo los secretos del .env. Ningún secreto queda en el repo
# ni en el workflow: n8n las guarda cifradas con N8N_ENCRYPTION_KEY.
#
# Uso (desde agnosticflow/ con el stack levantado):
#   ./n8n/scripts/importar_credenciales.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

if [ ! -f .env ]; then
    echo "ERROR: no existe .env (copia .env.example y rellénalo)" >&2
    exit 1
fi

set -a
. ./.env
set +a

: "${POSTGRES_USER:?Falta POSTGRES_USER en .env}"
: "${POSTGRES_PASSWORD:?Falta POSTGRES_PASSWORD en .env}"
: "${INGESTA_WEBHOOK_TOKEN:?Falta INGESTA_WEBHOOK_TOKEN en .env}"

if [ "$INGESTA_WEBHOOK_TOKEN" = "replace_with_a_random_token" ]; then
    echo "ERROR: cambia INGESTA_WEBHOOK_TOKEN en .env (openssl rand -hex 32)" >&2
    exit 1
fi

TMP=/tmp/agnosticflow_credenciales.json
trap 'docker compose exec -T n8n rm -f "$TMP" >/dev/null 2>&1 || true' EXIT

# El JSON pasa por stdin directamente al contenedor: no se escribe en el host.
jq -n \
    --arg pg_user "$POSTGRES_USER" \
    --arg pg_pass "$POSTGRES_PASSWORD" \
    --arg token "$INGESTA_WEBHOOK_TOKEN" \
    '[
        {
            id: "agnosticflowPg01",
            name: "Postgres AgnosticFlow",
            type: "postgres",
            data: {
                host: "postgres",
                port: 5432,
                database: "agnosticflow",
                user: $pg_user,
                password: $pg_pass,
                ssl: "disable"
            }
        },
        {
            id: "afIngestaHdrAuth",
            name: "Token webhook ingesta",
            type: "httpHeaderAuth",
            data: {
                name: "X-AgnosticFlow-Token",
                value: $token
            }
        }
    ]' \
    | docker compose exec -T n8n sh -c "umask 077; cat > $TMP"

docker compose exec -T n8n n8n import:credentials --input="$TMP" 2>&1 \
    | grep -v 'license SDK'
