
-- =====================================================
-- AGNOSTICFLOW
-- ENTREGABLE 3 (AGNOSTIC-15): PRUEBAS DEL NÚMERO DE SOCIO
-- Base de datos: agnosticflow
-- =====================================================

BEGIN;

-- -----------------------------------------------------
-- TEST 6: NUMERACIÓN SECUENCIAL E INDEPENDIENTE POR TENANT
-- Tres altas en el tenant A deben recibir 1, 2 y 3;
-- la primera alta del tenant B vuelve a empezar en 1
-- -----------------------------------------------------

DO $$
DECLARE
    tenant_a UUID;
    tenant_b UUID;
    numeros_a INTEGER[];
    numero_b INTEGER;
BEGIN
    INSERT INTO tenants (nombre)
    VALUES ('TEST_SOCIO_A')
    RETURNING id INTO tenant_a;

    INSERT INTO tenants (nombre)
    VALUES ('TEST_SOCIO_B')
    RETURNING id INTO tenant_b;

    INSERT INTO clientes (tenant_id, nombre, dni, telefono, email)
    VALUES
        (tenant_a, 'Socio A1', 'TEST-SA1', '600000101', 'sa1@example.com'),
        (tenant_a, 'Socio A2', 'TEST-SA2', '600000102', 'sa2@example.com'),
        (tenant_a, 'Socio A3', 'TEST-SA3', '600000103', 'sa3@example.com');

    INSERT INTO clientes (tenant_id, nombre, dni, telefono, email)
    VALUES (tenant_b, 'Socio B1', 'TEST-SB1', '600000201', 'sb1@example.com')
    RETURNING numero_socio INTO numero_b;

    SELECT ARRAY_AGG(numero_socio ORDER BY dni)
    INTO numeros_a
    FROM clientes
    WHERE tenant_id = tenant_a;

    IF numeros_a = ARRAY[1, 2, 3] AND numero_b = 1 THEN
        RAISE NOTICE
            'PASS TEST 6: Numero de socio secuencial e independiente por tenant';
    ELSE
        RAISE EXCEPTION
            'FAIL TEST 6: Tenant A = %, tenant B = % (se esperaba {1,2,3} y 1)',
            numeros_a, numero_b;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 7: RESTRICCIÓN UNIQUE (tenant_id, numero_socio)
-- Comprobar en el catálogo que existe la restricción
-- y que la columna es NOT NULL
-- -----------------------------------------------------

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'clientes'::regclass
          AND conname = 'uq_cliente_tenant_numero_socio'
          AND contype = 'u'
          AND pg_get_constraintdef(oid) = 'UNIQUE (tenant_id, numero_socio)'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'clientes'
          AND column_name = 'numero_socio'
          AND is_nullable = 'NO'
    ) THEN
        RAISE NOTICE
            'PASS TEST 7: UNIQUE (tenant_id, numero_socio) y NOT NULL configurados';
    ELSE
        RAISE EXCEPTION
            'FAIL TEST 7: Falta la restriccion UNIQUE o el NOT NULL de numero_socio';
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 8: EL NÚMERO LO ASIGNA SIEMPRE LA BBDD
-- Si quien inserta envía un numero_socio (p. ej. n8n),
-- se ignora y se usa el siguiente del contador
-- -----------------------------------------------------

DO $$
DECLARE
    tenant_test UUID;
    numero_asignado INTEGER;
BEGIN
    INSERT INTO tenants (nombre)
    VALUES ('TEST_SOCIO_MANUAL')
    RETURNING id INTO tenant_test;

    INSERT INTO clientes (tenant_id, nombre, dni, telefono, email, numero_socio)
    VALUES (tenant_test, 'Socio manual', 'TEST-SM1', '600000301', 'sm1@example.com', 999)
    RETURNING numero_socio INTO numero_asignado;

    IF numero_asignado = 1 THEN
        RAISE NOTICE
            'PASS TEST 8: El numero enviado se ignora y la BBDD asigna el 1';
    ELSE
        RAISE EXCEPTION
            'FAIL TEST 8: Se ha guardado el numero % enviado desde fuera',
            numero_asignado;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 9: EL NÚMERO DE SOCIO NO SE PUEDE MODIFICAR
-- Un UPDATE de numero_socio debe ser rechazado
-- -----------------------------------------------------

DO $$
DECLARE
    tenant_test UUID;
    cliente_test UUID;
BEGIN
    INSERT INTO tenants (nombre)
    VALUES ('TEST_SOCIO_INMUTABLE')
    RETURNING id INTO tenant_test;

    INSERT INTO clientes (tenant_id, nombre, dni, telefono, email)
    VALUES (tenant_test, 'Socio fijo', 'TEST-SF1', '600000401', 'sf1@example.com')
    RETURNING id INTO cliente_test;

    BEGIN
        UPDATE clientes
        SET numero_socio = 50
        WHERE id = cliente_test;

        RAISE EXCEPTION
            'FAIL TEST 9: Se ha permitido modificar el numero de socio';

    EXCEPTION
        WHEN restrict_violation THEN
            RAISE NOTICE
                'PASS TEST 9: El numero de socio es inmutable';
    END;
END;
$$;


-- -----------------------------------------------------
-- TEST 10: TENANT INEXISTENTE
-- Un cliente con un tenant que no existe se sigue
-- rechazando con foreign_key_violation y no deja número
-- -----------------------------------------------------

DO $$
BEGIN
    BEGIN
        INSERT INTO clientes (tenant_id, nombre, dni, telefono, email)
        VALUES (
            '00000000-0000-4000-8000-000000000002',
            'Socio huerfano',
            'TEST-SH1',
            '600000501',
            'sh1@example.com'
        );

        RAISE EXCEPTION
            'FAIL TEST 10: Se ha permitido un cliente con tenant inexistente';

    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE
                'PASS TEST 10: Tenant inexistente rechazado por foreign key';
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
    RAISE NOTICE 'PRUEBAS DEL NUMERO DE SOCIO FINALIZADAS';
    RAISE NOTICE '=====================================';
END;
$$;
