# Contrato del payload de ingesta

Estructura estándar que recibe AgnosticFlow desde cualquier formulario web,
sea cual sea el sector del cliente (AGNOSTIC-11).

- **Endpoint:** `POST /webhook/ingesta`
- **Cabecera:** `Content-Type: application/json`
- **Autenticación:** cabecera `X-AgnosticFlow-Token` con el valor de `INGESTA_WEBHOOK_TOKEN` (AGNOSTIC-12).
  Sin token o con un token incorrecto, n8n responde `403` y no se ejecuta el flujo.

## Campos

Todos los campos son **obligatorios**. Los campos de texto se limpian antes de
validarlos: se quitan los espacios del principio y del final.

| Campo | Tipo | Regla | Ejemplo |
|---|---|---|---|
| `tenant_id` | string (UUID) | UUID de un tenant que exista y esté activo | `"11111111-1111-4111-8111-111111111111"` |
| `nombre_completo` | string | 1–150 caracteres | `"Ana García López"` |
| `dni_nie` | string | 1–20 caracteres. Se guarda en mayúsculas. No se comprueba la letra, para admitir DNI, NIE o pasaporte. | `"12345678Z"` |
| `telefono` | string | Se quitan espacios, guiones y paréntesis. Después debe cumplir `^\+?[0-9]{9,15}$` | `"+34600123456"` |
| `email` | string | Formato `usuario@dominio.tld`, hasta 255 caracteres. Se guarda en minúsculas. | `"ana.garcia@example.com"` |
| `servicio` | string | 1–150 caracteres. Es el servicio o producto solicitado. | `"Inscripción anual"` |
| `canal_preferido` | string | `"whatsapp"` o `"email"`. No distingue mayúsculas de minúsculas. | `"whatsapp"` |

El cuerpo debe ser un **objeto** JSON. Un array, un texto plano o un cuerpo vacío
se rechazan.

## Dónde se guarda cada campo

| Campo del payload | Tabla y columna |
|---|---|
| `tenant_id` | `clientes.tenant_id`, `transacciones.tenant_id`, `logs.tenant_id` |
| `nombre_completo` | `clientes.nombre` |
| `dni_nie` | `clientes.dni` |
| `telefono` | `clientes.telefono` |
| `email` | `clientes.email` |
| `servicio` | `transacciones.servicio` |
| `canal_preferido` | `transacciones.canal_preferido` |

El sistema genera además:

- `clientes.numero_socio`: Número de Socio secuencial por tenant. Lo asigna la base
  de datos con un trigger (migración `003_numero_socio.sql`, AGNOSTIC-15). Si el
  payload lo envía, se ignora.
- `transacciones.estado = 'PENDIENTE'`
- un registro en `logs` con nivel `INFO` y el mensaje "Recibido vía webhook"
- los `id` (UUID) y las fechas `created_at`

**Cliente repetido:** el cliente se identifica por `(tenant_id, dni_nie)`.
- Si ya existe, se actualizan sus datos de contacto (`telefono` y `email`).
- Cada envío crea una **transacción nueva**.

## Respuestas

| Caso | HTTP | Cuerpo |
|---|---|---|
| Payload válido | `202 Accepted` (en menos de 300 ms) | `{ "estado": "ACEPTADO", "mensaje": "Solicitud recibida y en procesamiento" }` |
| Payload inválido, JSON mal formado o tenant inexistente | `400 Bad Request` | `{ "estado": "RECHAZADO", "errores": [ { "campo": "email", "mensaje": "..." } ] }` |

- Con el 202, los datos se guardan después de responder, sin que el cliente tenga que esperar.
- Con el 400, se devuelven **todos** los errores a la vez y **no se inserta nada**
  en `clientes` ni en `transacciones`. El rechazo queda registrado en `logs` con nivel `WARN`.

## Ejemplos

Están en `n8n/payloads/`:

| Archivo | Caso | Resultado esperado |
|---|---|---|
| `valido.json` | Payload correcto | 202 y se insertan los datos |
| `invalido_sin_email.json` | Falta `email` | 400, sin INSERT |
| `invalido_sin_telefono.json` | Falta `telefono` | 400, sin INSERT |
| `invalido_malformado.json` | JSON mal formado (falta la llave de cierre) | 400, sin INSERT |

```bash
curl -i -X POST "http://localhost:${N8N_PORT:-5678}/webhook/ingesta" \
  -H 'Content-Type: application/json' \
  -H "X-AgnosticFlow-Token: $INGESTA_WEBHOOK_TOKEN" \
  --data-binary @n8n/payloads/valido.json
```

Las pruebas automáticas de extremo a extremo (P0–P4 de AGNOSTIC-16) están en
`n8n/scripts/probar_webhook.sh`.
