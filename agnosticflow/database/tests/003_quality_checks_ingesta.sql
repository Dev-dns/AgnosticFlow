
-- =====================================================
-- AGNOSTICFLOW
-- ENTREGABLE 3: PRUEBAS DE LA MIGRACIÓN 002 (INGESTA)
-- Base de datos: agnosticflow
-- =====================================================

BEGIN;

-- Datos comunes para todas las pruebas
CREATE TEMP TABLE ctx ON COMMIT DROP AS
WITH t AS (
    INSERT INTO tenants (nombre) VALUES ('TEST_E3_A'), ('TEST_E3_B')
    RETURNING id, nombre
),
c AS (
    INSERT INTO clientes (tenant_id, nombre, dni, telefono, email)
    SELECT id, 'Cliente ' || nombre, 'TEST-' || nombre, '600000000', 'e3@example.com'
    FROM t
    RETURNING id AS cliente_id, tenant_id
)
SELECT c.tenant_id, c.cliente_id, t.nombre
FROM c JOIN t ON t.id = c.tenant_id;


-- -----------------------------------------------------
-- TEST 11: CANAL PREFERIDO
-- Solo se admiten 'whatsapp' o 'email'
-- -----------------------------------------------------

DO $$
DECLARE
    v_tenant UUID;
    v_cliente UUID;
BEGIN
    SELECT tenant_id, cliente_id INTO v_tenant, v_cliente
    FROM ctx WHERE nombre = 'TEST_E3_A';

    BEGIN
        INSERT INTO transacciones (tenant_id, cliente_id, servicio, canal_preferido)
        VALUES (v_tenant, v_cliente, 'Servicio', 'sms');

        RAISE EXCEPTION 'FAIL TEST 11: Se ha permitido un canal no válido';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS TEST 11: Canal no válido rechazado';
    END;
END;
$$;


-- -----------------------------------------------------
-- TEST 12: SERVICIO OBLIGATORIO
-- -----------------------------------------------------

DO $$
DECLARE
    v_tenant UUID;
    v_cliente UUID;
BEGIN
    SELECT tenant_id, cliente_id INTO v_tenant, v_cliente
    FROM ctx WHERE nombre = 'TEST_E3_A';

    BEGIN
        INSERT INTO transacciones (tenant_id, cliente_id, canal_preferido)
        VALUES (v_tenant, v_cliente, 'email');

        RAISE EXCEPTION 'FAIL TEST 12: Se ha permitido una transacción sin servicio';
    EXCEPTION
        WHEN not_null_violation THEN
            RAISE NOTICE 'PASS TEST 12: Servicio obligatorio';
    END;
END;
$$;


-- -----------------------------------------------------
-- TEST 13: LOG DE PAYLOAD RECHAZADO
-- Se puede registrar un log sin transacción ni tenant
-- -----------------------------------------------------

DO $$
BEGIN
    INSERT INTO logs (nivel, mensaje)
    VALUES ('WARN', 'Payload rechazado: falta email');

    RAISE NOTICE 'PASS TEST 13: Log sin transacción ni tenant permitido';
END;
$$;


-- -----------------------------------------------------
-- TEST 14: LOG CON TRANSACCIÓN EXIGE TENANT
-- -----------------------------------------------------

DO $$
DECLARE
    v_tenant UUID;
    v_cliente UUID;
    v_transaccion UUID;
BEGIN
    SELECT tenant_id, cliente_id INTO v_tenant, v_cliente
    FROM ctx WHERE nombre = 'TEST_E3_A';

    INSERT INTO transacciones (tenant_id, cliente_id, servicio, canal_preferido)
    VALUES (v_tenant, v_cliente, 'Servicio', 'whatsapp')
    RETURNING id INTO v_transaccion;

    BEGIN
        INSERT INTO logs (transaccion_id, nivel, mensaje)
        VALUES (v_transaccion, 'INFO', 'Sin tenant');

        RAISE EXCEPTION 'FAIL TEST 14: Se ha permitido un log con transacción y sin tenant';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS TEST 14: Log con transacción exige tenant';
    END;
END;
$$;


-- -----------------------------------------------------
-- TEST 15: AISLAMIENTO MULTI-TENANT EN LOGS
-- Un log no puede apuntar a la transacción de otro tenant
-- -----------------------------------------------------

DO $$
DECLARE
    v_tenant_a UUID;
    v_cliente_a UUID;
    v_tenant_b UUID;
    v_transaccion_a UUID;
BEGIN
    SELECT tenant_id, cliente_id INTO v_tenant_a, v_cliente_a
    FROM ctx WHERE nombre = 'TEST_E3_A';
    SELECT tenant_id INTO v_tenant_b
    FROM ctx WHERE nombre = 'TEST_E3_B';

    INSERT INTO transacciones (tenant_id, cliente_id, servicio, canal_preferido)
    VALUES (v_tenant_a, v_cliente_a, 'Servicio', 'email')
    RETURNING id INTO v_transaccion_a;

    BEGIN
        INSERT INTO logs (tenant_id, transaccion_id, nivel, mensaje)
        VALUES (v_tenant_b, v_transaccion_a, 'INFO', 'Tenant cruzado');

        RAISE EXCEPTION 'FAIL TEST 15: Se ha permitido mezclar tenants en logs';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS TEST 15: Aislamiento multi-tenant en logs correcto';
    END;
END;
$$;


-- -----------------------------------------------------
-- FINALIZACION
-- Revertir todos los datos temporales de las pruebas
-- -----------------------------------------------------

ROLLBACK;

DO $$
BEGIN
    RAISE NOTICE '=====================================';
    RAISE NOTICE 'TODAS LAS PRUEBAS DE LA MIGRACION 002 HAN FINALIZADO';
    RAISE NOTICE '=====================================';
END;
$$;
