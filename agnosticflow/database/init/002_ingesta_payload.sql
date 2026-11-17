
-- =====================================================
-- AGNOSTICFLOW
-- Entregable 3: Migración para la ingesta por webhook
-- Base de datos: agnosticflow
-- =====================================================
-- 1. transacciones: guardar `servicio` y `canal_preferido` del payload
--    (AGNOSTIC-11), para no perder información (HU-01).
-- 2. logs: permitir logs sin transacción y sin tenant, para registrar
--    los payloads rechazados (AGNOSTIC-10, AGNOSTIC-13, AGNOSTIC-16 P4).
--
-- Idempotente: se puede ejecutar a mano en una base ya creada.
-- Requiere que transacciones esté vacía (o que se rellenen las columnas
-- antes de aplicar NOT NULL).

\connect agnosticflow

BEGIN;

-- 1. TRANSACCIONES: datos de la solicitud

ALTER TABLE transacciones
    ADD COLUMN IF NOT EXISTS servicio VARCHAR(150),
    ADD COLUMN IF NOT EXISTS canal_preferido VARCHAR(10);

ALTER TABLE transacciones
    ALTER COLUMN servicio SET NOT NULL,
    ALTER COLUMN canal_preferido SET NOT NULL;

ALTER TABLE transacciones
    DROP CONSTRAINT IF EXISTS chk_transaccion_canal;

ALTER TABLE transacciones
    ADD CONSTRAINT chk_transaccion_canal
        CHECK (canal_preferido IN ('whatsapp', 'email'));

-- 2. LOGS: registro de payloads rechazados

ALTER TABLE logs
    ALTER COLUMN transaccion_id DROP NOT NULL,
    ALTER COLUMN tenant_id DROP NOT NULL;

-- Un log asociado a una transacción debe indicar también su tenant.
-- Sin esto, la FK compuesta (tenant_id, transaccion_id) no se comprobaría
-- cuando tenant_id es NULL (MATCH SIMPLE).
ALTER TABLE logs
    DROP CONSTRAINT IF EXISTS chk_log_transaccion_tenant;

ALTER TABLE logs
    ADD CONSTRAINT chk_log_transaccion_tenant
        CHECK (transaccion_id IS NULL OR tenant_id IS NOT NULL);

COMMIT;
