-- =====================================================
-- AGNOSTICFLOW
-- ENTREGABLE 3 (AGNOSTIC-14): PRUEBAS DEL INSERT DE LA INGESTA
-- =====================================================
-- No se ejecuta suelto: lo lanza n8n/scripts/probar_insertar_ingesta.sh,
-- que antes prepara la consulta de n8n/sql/insertar_ingesta.sql como
-- "insertar_ingesta" y lo envuelve todo en una transacción con ROLLBACK.

INSERT INTO tenants (id, nombre) VALUES
    ('33333333-3333-4333-8333-333333333333', 'TEST_INGESTA_A'),
    ('44444444-4444-4444-8444-444444444444', 'TEST_INGESTA_B');

CREATE TEMP TABLE r16 AS EXECUTE insertar_ingesta(
    '33333333-3333-4333-8333-333333333333', 'Ana García', '111A',
    '+34600000001', 'ana@example.com', 'Inscripción anual', 'whatsapp');

CREATE TEMP TABLE r17 AS EXECUTE insertar_ingesta(
    '33333333-3333-4333-8333-333333333333', 'Ana G. (otro nombre)', '111A',
    '+34600000099', 'ana.nuevo@example.com', 'Renovación', 'email');

CREATE TEMP TABLE r18 AS EXECUTE insertar_ingesta(
    '33333333-3333-4333-8333-333333333333', 'Bruno Pérez', '222B',
    '+34600000002', 'bruno@example.com', 'Inscripción anual', 'email');

CREATE TEMP TABLE r19 AS EXECUTE insertar_ingesta(
    '44444444-4444-4444-8444-444444444444', 'Ana en otro negocio', '111A',
    '+34600000003', 'ana@otro.example.com', 'Inscripción anual', 'whatsapp');


-- -----------------------------------------------------
-- TEST 16: ALTA NUEVA
-- Crea cliente (Nº de Socio 1), transacción PENDIENTE con
-- servicio y canal, y un log INFO
-- -----------------------------------------------------

DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT * INTO r FROM r16;

    IF r.numero_socio = 1
       AND NOT r.cliente_existente
       AND r.estado = 'PENDIENTE'
       AND EXISTS (SELECT 1 FROM transacciones
                   WHERE id = r.transaccion_id
                     AND servicio = 'Inscripción anual'
                     AND canal_preferido = 'whatsapp')
       AND EXISTS (SELECT 1 FROM logs
                   WHERE transaccion_id = r.transaccion_id
                     AND nivel = 'INFO')
    THEN
        RAISE NOTICE 'PASS TEST 16: Alta nueva con cliente, transaccion y log';
    ELSE
        RAISE EXCEPTION 'FAIL TEST 16: Resultado inesperado: %', row_to_json(r);
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 17: REENVÍO DEL MISMO CLIENTE
-- No crea cliente nuevo: actualiza teléfono y email, conserva
-- nombre y Nº de Socio, y crea una transacción nueva
-- -----------------------------------------------------

DO $$
DECLARE
    r RECORD;
    c RECORD;
BEGIN
    SELECT * INTO r FROM r17;
    SELECT * INTO c FROM clientes
    WHERE tenant_id = '33333333-3333-4333-8333-333333333333' AND dni = '111A';

    IF r.cliente_existente
       AND r.numero_socio = 1
       AND r.cliente_id = (SELECT cliente_id FROM r16)
       AND r.transaccion_id <> (SELECT transaccion_id FROM r16)
       AND c.email = 'ana.nuevo@example.com'
       AND c.telefono = '+34600000099'
       AND c.nombre = 'Ana García'
       AND (SELECT count(*) FROM clientes
            WHERE tenant_id = '33333333-3333-4333-8333-333333333333'
              AND dni = '111A') = 1
    THEN
        RAISE NOTICE 'PASS TEST 17: Reenvio actualiza el contacto y crea transaccion nueva';
    ELSE
        RAISE EXCEPTION 'FAIL TEST 17: Resultado inesperado: % / %',
            row_to_json(r), row_to_json(c);
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 18: EL REENVÍO NO GASTA NÚMEROS DE SOCIO
-- Regresión: con INSERT ... ON CONFLICT el siguiente alta
-- recibía el 3 en lugar del 2
-- -----------------------------------------------------

DO $$
DECLARE
    numero INTEGER;
    contador INTEGER;
BEGIN
    SELECT numero_socio INTO numero FROM r18;
    SELECT ultimo_numero_socio INTO contador FROM tenants
    WHERE id = '33333333-3333-4333-8333-333333333333';

    IF numero = 2 AND contador = 2 THEN
        RAISE NOTICE 'PASS TEST 18: Numeracion sin huecos tras un reenvio';
    ELSE
        RAISE EXCEPTION 'FAIL TEST 18: Nuevo socio = %, contador = % (se esperaba 2 y 2)',
            numero, contador;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 19: MISMO DNI EN OTRO TENANT
-- Es otro cliente, con su propia numeración
-- -----------------------------------------------------

DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT * INTO r FROM r19;

    IF NOT r.cliente_existente
       AND r.numero_socio = 1
       AND r.cliente_id <> (SELECT cliente_id FROM r16)
    THEN
        RAISE NOTICE 'PASS TEST 19: Mismo DNI en otro tenant es un cliente distinto';
    ELSE
        RAISE EXCEPTION 'FAIL TEST 19: Resultado inesperado: %', row_to_json(r);
    END IF;
END;
$$;
