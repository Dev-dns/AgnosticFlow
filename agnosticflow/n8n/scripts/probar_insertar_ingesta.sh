#!/usr/bin/env bash
# Prueba la consulta de inserción de la ingesta (n8n/sql/insertar_ingesta.sql)
# contra la BBDD agnosticflow, sin dejar datos (todo acaba en ROLLBACK).
#
# Uso (desde agnosticflow/ con el stack levantado):
#   ./n8n/scripts/probar_insertar_ingesta.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

{
    echo "BEGIN;"
    echo "PREPARE insertar_ingesta(uuid, text, text, text, text, text, text) AS"
    grep -v '^\s*--' n8n/sql/insertar_ingesta.sql
    echo ";"
    cat n8n/tests/insertar_ingesta_test.sql
    echo "ROLLBACK;"
} | docker compose exec -T postgres \
    psql -v ON_ERROR_STOP=1 -q -U agnosticflow -d agnosticflow
