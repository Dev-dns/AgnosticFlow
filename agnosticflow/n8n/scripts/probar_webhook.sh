#!/usr/bin/env bash
# Pruebas de extremo a extremo del webhook de ingesta (AGNOSTIC-16): lanza
# peticiones reales contra n8n y comprueba las respuestas y la BBDD.
#
#   P0 Autenticación: sin token -> 403
#   P1 Timeout:       10 payloads válidos -> todos 202 en < 300 ms
#   P2 Anti-basura:   sin email y sin teléfono -> 400 y 0 transacciones nuevas
#   P3 Inserción:     payload válido -> cliente y transacción del mismo tenant
#   P4 Malformado:    JSON mal formado -> 400 y log WARN
#
# Deja datos en la BBDD (las transacciones de P1/P3 y los logs): se usa el
# tenant demo de database/seeds/001_tenant_demo.sql.
#
# Uso (desde agnosticflow/ con el stack levantado y el workflow publicado):
#   ./n8n/scripts/probar_webhook.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${INGESTA_WEBHOOK_TOKEN:?Falta INGESTA_WEBHOOK_TOKEN en .env}"
URL="http://127.0.0.1:${N8N_PORT:-5678}/webhook/ingesta"
PAYLOADS=n8n/payloads
TENANT=$(jq -r .tenant_id "$PAYLOADS/valido.json")
DNI=$(jq -r .dni_nie "$PAYLOADS/valido.json")
LIMITE_MS=300

FALLOS=0
ok()    { echo "  PASS $*"; }
falla() { echo "  FAIL $*"; FALLOS=$((FALLOS + 1)); }

sql() {
    docker compose exec -T postgres \
        psql -U "$POSTGRES_USER" -d agnosticflow -Atc "$1"
}

# enviar FICHERO [con_token] -> deja $CODIGO, $MS y $CUERPO
CUERPO_TMP=$(mktemp)
trap 'rm -f "$CUERPO_TMP"' EXIT
enviar() {
    local args=(-s -o "$CUERPO_TMP" -w '%{http_code} %{time_total}' -m 10
        -X POST -H 'Content-Type: application/json'
        --data-binary "@$1")
    if [ "${2:-si}" = si ]; then
        args+=(-H "X-AgnosticFlow-Token: $INGESTA_WEBHOOK_TOKEN")
    fi
    local salida
    salida=$(curl "${args[@]}" "$URL" || echo "000 0")
    CODIGO=${salida%% *}
    MS=$(awk -v t="${salida##* }" 'BEGIN { printf "%d", t * 1000 }')
    CUERPO=$(cat "$CUERPO_TMP")
}

# El INSERT se hace después de responder 202: espera a que aparezca.
esperar_transacciones() {
    local esperadas=$1
    for _ in $(seq 1 50); do
        [ "$(sql 'SELECT count(*) FROM transacciones')" -ge "$esperadas" ] && return 0
        sleep 0.1
    done
    return 1
}

if ! curl -s -o /dev/null -m 5 "http://127.0.0.1:${N8N_PORT:-5678}/healthz"; then
    echo "ERROR: n8n no responde en el puerto ${N8N_PORT:-5678}" >&2
    exit 1
fi

echo "Webhook: $URL"

echo "P0 Autenticación"
enviar "$PAYLOADS/valido.json" no
[ "$CODIGO" = 403 ] && ok "sin token -> 403" || falla "sin token -> $CODIGO (esperado 403)"

echo "P1 Timeout (< ${LIMITE_MS} ms)"
TX_ANTES=$(sql 'SELECT count(*) FROM transacciones')
MAX=0
FALLOS_P1=$FALLOS
for i in $(seq 1 10); do
    enviar "$PAYLOADS/valido.json"
    printf '    petición %2d: HTTP %s en %3d ms\n' "$i" "$CODIGO" "$MS"
    if [ "$CODIGO" != 202 ] || [ "$MS" -ge "$LIMITE_MS" ]; then
        falla "petición $i: HTTP $CODIGO en $MS ms"
    fi
    [ "$MS" -gt "$MAX" ] && MAX=$MS
done
[ "$FALLOS" -eq "$FALLOS_P1" ] && ok "10 peticiones con 202 en < ${LIMITE_MS} ms (máximo $MAX ms)"
if esperar_transacciones $((TX_ANTES + 10)); then
    ok "10 transacciones nuevas"
else
    falla "transacciones: $TX_ANTES -> $(sql 'SELECT count(*) FROM transacciones') (esperadas +10)"
fi

echo "P2 Anti-basura"
for caso in invalido_sin_email invalido_sin_telefono; do
    TX_ANTES=$(sql 'SELECT count(*) FROM transacciones')
    enviar "$PAYLOADS/$caso.json"
    sleep 1
    TX_DESPUES=$(sql 'SELECT count(*) FROM transacciones')
    if [ "$CODIGO" = 400 ] && [ "$TX_ANTES" = "$TX_DESPUES" ]; then
        ok "$caso -> 400, transacciones $TX_ANTES -> $TX_DESPUES ($CUERPO)"
    else
        falla "$caso -> HTTP $CODIGO, transacciones $TX_ANTES -> $TX_DESPUES"
    fi
done

echo "P3 Inserción válida"
TX_ANTES=$(sql 'SELECT count(*) FROM transacciones')
enviar "$PAYLOADS/valido.json"
if [ "$CODIGO" = 202 ] && esperar_transacciones $((TX_ANTES + 1)); then
    FILA=$(sql "SELECT c.tenant_id, c.numero_socio, t.tenant_id, t.estado
                FROM transacciones t
                JOIN clientes c ON c.id = t.cliente_id
                WHERE c.dni = '$DNI'
                ORDER BY t.created_at DESC LIMIT 1")
    IFS='|' read -r TENANT_CLI SOCIO TENANT_TX ESTADO <<<"$FILA"
    if [ "$TENANT_CLI" = "$TENANT" ] && [ "$TENANT_TX" = "$TENANT" ] && [ "$ESTADO" = PENDIENTE ]; then
        ok "cliente (Nº socio $SOCIO) y transacción $ESTADO con tenant $TENANT"
    else
        falla "fila inesperada: $FILA"
    fi
else
    falla "valido -> HTTP $CODIGO o sin transacción nueva"
fi

echo "P4 Payload malformado"
LOGS_ANTES=$(sql "SELECT count(*) FROM logs WHERE nivel = 'WARN'")
enviar "$PAYLOADS/invalido_malformado.json"
sleep 1
LOGS_DESPUES=$(sql "SELECT count(*) FROM logs WHERE nivel = 'WARN'")
if [ "$CODIGO" = 400 ] && [ "$LOGS_DESPUES" -gt "$LOGS_ANTES" ]; then
    ok "malformado -> 400 y log WARN: $(sql "SELECT mensaje FROM logs WHERE nivel = 'WARN' ORDER BY created_at DESC LIMIT 1")"
else
    falla "malformado -> HTTP $CODIGO, logs WARN $LOGS_ANTES -> $LOGS_DESPUES"
fi

echo
if [ "$FALLOS" -eq 0 ]; then
    echo "Todas las pruebas pasan"
else
    echo "$FALLOS prueba(s) fallan"
    exit 1
fi
