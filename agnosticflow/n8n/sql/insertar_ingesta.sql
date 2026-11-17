-- =====================================================
-- AGNOSTICFLOW
-- Entregable 3 (AGNOSTIC-14): INSERT de la ingesta por webhook
-- =====================================================
-- Consulta que ejecuta el nodo Postgres del workflow de ingesta.
-- Parámetros (en este orden, nunca concatenados):
--   $1 tenant_id   $2 nombre_completo   $3 dni_nie   $4 telefono
--   $5 email       $6 servicio          $7 canal_preferido
--
-- Es una única sentencia, así que es atómica: se guarda todo o nada.
--   1. Si el cliente ya existe (tenant_id + dni), se actualizan su teléfono
--      y su email.
--   2. Si no existe, se inserta. El trigger de la migración 003 le asigna
--      el Número de Socio.
--   3. Se crea una transacción PENDIENTE y un log INFO.
--
-- Por qué no se usa INSERT ... ON CONFLICT DO UPDATE: el trigger
-- BEFORE INSERT del Número de Socio se ejecuta antes de que se detecte el
-- conflicto, así que cada reenvío de un cliente existente gastaría un
-- número y dejaría huecos en la numeración.
--
-- Si llegan a la vez dos altas nuevas con el mismo DNI, una de ellas falla
-- por la restricción UNIQUE (tenant_id, dni). Al deshacerse, el contador
-- vuelve atrás y no queda hueco. Los reintentos se tratan en el E8.

WITH datos AS (
    SELECT
        $1::uuid AS tenant_id,
        $2::text AS nombre,
        $3::text AS dni,
        $4::text AS telefono,
        $5::text AS email,
        $6::text AS servicio,
        $7::text AS canal_preferido
),
actualizado AS (
    UPDATE clientes c
    SET telefono = d.telefono,
        email = d.email
    FROM datos d
    WHERE c.tenant_id = d.tenant_id
      AND c.dni = d.dni
    RETURNING c.id, c.tenant_id, c.numero_socio
),
insertado AS (
    INSERT INTO clientes (tenant_id, nombre, dni, telefono, email)
    SELECT tenant_id, nombre, dni, telefono, email
    FROM datos
    WHERE NOT EXISTS (SELECT 1 FROM actualizado)
    RETURNING id, tenant_id, numero_socio
),
cliente AS (
    SELECT id, tenant_id, numero_socio, TRUE AS existente FROM actualizado
    UNION ALL
    SELECT id, tenant_id, numero_socio, FALSE AS existente FROM insertado
),
transaccion AS (
    INSERT INTO transacciones (tenant_id, cliente_id, servicio, canal_preferido)
    SELECT c.tenant_id, c.id, d.servicio, d.canal_preferido
    FROM cliente c
    CROSS JOIN datos d
    RETURNING id, tenant_id, cliente_id, estado
),
log AS (
    INSERT INTO logs (tenant_id, transaccion_id, nivel, mensaje)
    SELECT tenant_id, id, 'INFO', 'Recibido vía webhook'
    FROM transaccion
)
SELECT
    t.id AS transaccion_id,
    t.cliente_id,
    c.numero_socio,
    c.existente AS cliente_existente,
    t.estado
FROM transaccion t
JOIN cliente c ON c.id = t.cliente_id
