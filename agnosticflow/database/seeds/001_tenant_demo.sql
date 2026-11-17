
-- =====================================================
-- AGNOSTICFLOW
-- Entregable 3: Datos de prueba
-- Base de datos: agnosticflow
-- =====================================================
-- Tenant fijo para probar la ingesta por webhook.
-- Idempotente: se puede ejecutar varias veces.

INSERT INTO tenants (id, nombre)
VALUES (
    '11111111-1111-4111-8111-111111111111',
    'Tenant Demo'
)
ON CONFLICT (id) DO NOTHING;
