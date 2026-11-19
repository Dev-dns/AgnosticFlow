# AgnosticFlow

Middleware de automatización B2B multi-tenant con n8n y PostgreSQL en Docker.
Recibe por webhook los datos de cualquier formulario web, los valida y los
guarda en un esquema relacional aislado por tenant.

## Estado por entregable

| Entregable | Contenido | Estado |
|---|---|---|
| E2 | Esquema relacional multi-tenant + quality checks SQL | ✅ |
| E3 | Ingesta por webhook (autenticación, validación, 202/400, INSERT, logs) | En revisión |

## Estructura

```
agnosticflow/
├── docker-compose.yml        # n8n + PostgreSQL 18 en una red interna
├── .env.example              # variables necesarias (copiar a .env)
├── database/
│   ├── init/                 # migraciones; se ejecutan al crear el volumen
│   ├── seeds/                # datos de prueba (tenant demo)
│   └── tests/                # quality checks SQL (tests 1–15)
├── docs/
│   └── payload.md            # contrato del payload de ingesta
└── n8n/
    ├── workflows/            # workflows exportados (JSON versionado)
    ├── sql/                  # consultas que usan los nodos Postgres
    ├── payloads/             # payloads de ejemplo (válido e inválidos)
    ├── tests/                # pruebas de la consulta de inserción (16–19)
    └── scripts/              # credenciales, despliegue y pruebas
```

## Puesta en marcha

Requisitos: Docker con Compose, `jq` y `curl`. Todos los comandos se lanzan
desde `agnosticflow/`.

1. **Variables de entorno.** Copia `.env.example` a `.env` y rellena los secretos:

   ```bash
   cp .env.example .env
   openssl rand -hex 32   # para N8N_ENCRYPTION_KEY y para INGESTA_WEBHOOK_TOKEN
   ```

   Si el puerto 5678 ya está ocupado (por ejemplo, por otra instancia de n8n),
   cambia `N8N_PORT` en `.env`. Los scripts usan ese mismo valor.

2. **Levantar el stack.** La primera vez, PostgreSQL ejecuta las migraciones de
   `database/init/` (crea la base `agnosticflow`, separada de la interna de n8n):

   ```bash
   docker compose up -d
   ```

   Las migraciones solo se ejecutan con el volumen vacío. Para aplicar una
   migración nueva sobre una base ya creada, consulta su cabecera.

3. **Tenant de prueba.**

   ```bash
   docker compose exec -T postgres psql -U agnosticflow -d agnosticflow \
       < database/seeds/001_tenant_demo.sql
   ```

4. **Credenciales de n8n.** Crea en n8n la credencial de Postgres y la del token
   del webhook a partir de `.env` (ningún secreto queda en el repo ni en el workflow):

   ```bash
   ./n8n/scripts/importar_credenciales.sh
   ```

5. **Clave de la API de n8n.** Entra en `http://localhost:<N8N_PORT>`, crea la
   cuenta de propietario y genera una clave en *Settings → n8n API*. Guárdala
   en `.env` como `N8N_API_KEY`.

6. **Desplegar el workflow de ingesta.** Lo crea o actualiza y lo publica en
   caliente. Antes comprueba que la consulta del nodo *Insertar ingesta*
   coincide con `n8n/sql/insertar_ingesta.sql`:

   ```bash
   ./n8n/scripts/desplegar_workflow.sh
   ```

## Flujo de ingesta (E3)

`POST /webhook/ingesta` con la cabecera `X-AgnosticFlow-Token`. El contrato
completo está en [`docs/payload.md`](docs/payload.md).

```
Webhook (Header Auth) → Validar payload → Comprobar tenant → Resultado validación → ¿Payload válido?
    ├─ sí → Responder 202 → Insertar ingesta  (cliente + transacción PENDIENTE + log INFO)
    └─ no → Responder 400 → Registrar rechazo (log WARN, sin datos personales)
```

- El webhook recibe el cuerpo en bruto, así que un JSON mal formado también
  devuelve 400 y queda en `logs` (si n8n lo interpretase, respondería 422 sin
  ejecutar el flujo).
- Con un payload válido se responde 202 antes del INSERT, así que el cliente
  no espera a la base de datos.
- Un 400 devuelve todos los errores a la vez y no inserta nada en `clientes`
  ni en `transacciones`.

## Pruebas

```bash
# Quality checks del esquema (tests 1–15). Terminan en ROLLBACK.
for f in database/tests/*.sql; do
    docker compose exec -T postgres psql -U agnosticflow -d agnosticflow -q < "$f"
done

# Consulta de inserción de la ingesta (tests 16–19). Termina en ROLLBACK.
./n8n/scripts/probar_insertar_ingesta.sh

# Webhook de extremo a extremo (P0–P4 de AGNOSTIC-16). Deja datos del tenant demo.
./n8n/scripts/probar_webhook.sh
```
