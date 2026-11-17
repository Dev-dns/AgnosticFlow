
-- =====================================================
-- AGNOSTICFLOW
-- ENTREGABLE 2: PRUEBAS DE CALIDAD
-- Base de datos: agnosticflow
-- =====================================================

BEGIN;

-- -----------------------------------------------------
-- TEST 1: INTEGRIDAD REFERENCIAL
-- Comprobar que no se permiten tenants inexistentes
-- -----------------------------------------------------

DO $$
DECLARE
    tenant_valido UUID;
    cliente_valido UUID;
BEGIN
    -- Crear tenant de prueba
    INSERT INTO tenants (nombre)
    VALUES ('TEST_TENANT_1')
    RETURNING id INTO tenant_valido;

    -- Crear cliente asociado
    INSERT INTO clientes (
        tenant_id, nombre, dni, telefono, email
    )
    VALUES (
        tenant_valido,
        'Cliente de prueba',
        'TEST-001',
        '600000000',
        'test@example.com'
    )
    RETURNING id INTO cliente_valido;

    -- Intentar insertar transacción con tenant inexistente
    BEGIN
        INSERT INTO transacciones (
            tenant_id, cliente_id, servicio, canal_preferido
        )
        VALUES (
            '00000000-0000-4000-8000-000000000001',
            cliente_valido,
            'Servicio de prueba',
            'email'
        );

        RAISE EXCEPTION
            'FAIL: Se ha permitido un tenant inexistente';

    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE
                'PASS TEST 1: Foreign Key rechaza tenant inexistente';
    END;
END;
$$;


-- -----------------------------------------------------
-- TEST 2: INDICE B-TREE
-- Comprobar que tenant_id tiene indice B-Tree
-- en transacciones
-- -----------------------------------------------------

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'transacciones'
          AND indexname = 'idx_transacciones_tenant'
          AND indexdef ILIKE '%USING btree%'
    ) THEN
        RAISE NOTICE
            'PASS TEST 2: Indice B-Tree correctamente configurado';
    ELSE
        RAISE EXCEPTION
            'FAIL TEST 2: No existe el indice B-Tree esperado';
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 3: UUID COMO CLAVE PRIMARIA
-- Comprobar que las cuatro tablas utilizan UUID
-- como identificador y clave primaria
-- -----------------------------------------------------

DO $$
DECLARE
    tablas_correctas INTEGER;
BEGIN
    SELECT COUNT(DISTINCT t.table_name)
    INTO tablas_correctas
    FROM information_schema.tables t
    JOIN pg_constraint c
      ON c.conrelid = (
          SELECT cl.oid
          FROM pg_class cl
          JOIN pg_namespace ns ON ns.oid = cl.relnamespace
          WHERE ns.nspname = 'public'
            AND cl.relname = t.table_name
      )
     AND c.contype = 'p'
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attnum = ANY(c.conkey)
    WHERE t.table_schema = 'public'
      AND t.table_name IN (
          'tenants',
          'clientes',
          'transacciones',
          'logs'
      )
      AND a.attname = 'id'
      AND a.atttypid = 'uuid'::regtype;

    IF tablas_correctas = 4 THEN
        RAISE NOTICE
            'PASS TEST 3: Las cuatro tablas tienen UUID como PK';
    ELSE
        RAISE EXCEPTION
            'FAIL TEST 3: Solo % de 4 tablas tienen UUID como PK',
            tablas_correctas;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- TEST 4: AISLAMIENTO MULTI-TENANT
-- Impedir que una transaccion utilice un cliente
-- perteneciente a otro tenant
-- -----------------------------------------------------

DO $$
DECLARE
    tenant_a UUID;
    tenant_b UUID;
    cliente_a UUID;
BEGIN
    INSERT INTO tenants (nombre)
    VALUES ('TEST_TENANT_A')
    RETURNING id INTO tenant_a;

    INSERT INTO tenants (nombre)
    VALUES ('TEST_TENANT_B')
    RETURNING id INTO tenant_b;

    INSERT INTO clientes (
        tenant_id, nombre, dni, telefono, email
    )
    VALUES (
        tenant_a,
        'Cliente A',
        'TEST-A',
        '600000001',
        'clientea@example.com'
    )
    RETURNING id INTO cliente_a;

    -- Intentar utilizar el cliente A desde el tenant B
    BEGIN
        INSERT INTO transacciones (
            tenant_id, cliente_id, servicio, canal_preferido
        )
        VALUES (
            tenant_b,
            cliente_a,
            'Servicio de prueba',
            'email'
        );

        RAISE EXCEPTION
            'FAIL: Se ha permitido mezclar tenants';

    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE
                'PASS TEST 4: Aislamiento Multi-Tenant correcto';
    END;
END;
$$;


-- -----------------------------------------------------
-- TEST 5: OPERACION CORRECTA
-- Comprobar que se pueden crear registros validos
-- y relacionarlos correctamente
-- -----------------------------------------------------

DO $$
DECLARE
    tenant_id_test UUID;
    cliente_id_test UUID;
    transaccion_id_test UUID;
BEGIN
    INSERT INTO tenants (nombre)
    VALUES ('TEST_TENANT_VALIDO')
    RETURNING id INTO tenant_id_test;

    INSERT INTO clientes (
        tenant_id, nombre, dni, telefono, email
    )
    VALUES (
        tenant_id_test,
        'Cliente correcto',
        'TEST-VALIDO',
        '600000002',
        'valido@example.com'
    )
    RETURNING id INTO cliente_id_test;

    INSERT INTO transacciones (
        tenant_id, cliente_id, estado, servicio, canal_preferido
    )
    VALUES (
        tenant_id_test,
        cliente_id_test,
        'PENDIENTE',
        'Servicio de prueba',
        'email'
    )
    RETURNING id INTO transaccion_id_test;

    INSERT INTO logs (
        tenant_id, transaccion_id, nivel, mensaje
    )
    VALUES (
        tenant_id_test,
        transaccion_id_test,
        'INFO',
        'Prueba de integridad correcta'
    );

    RAISE NOTICE
        'PASS TEST 5: Insercion y relaciones validas correctas';
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
    RAISE NOTICE 'TODAS LAS PRUEBAS HAN FINALIZADO';
    RAISE NOTICE '=====================================';
END;
$$;

