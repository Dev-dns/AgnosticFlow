
-- =====================================================
-- AGNOSTICFLOW
-- Entregable 3 (AGNOSTIC-15): Número de Socio secuencial por tenant
-- Base de datos: agnosticflow
-- =====================================================
--
-- Requisito del cliente: al inscribirse, cada cliente recibe un
-- "Número de Socio" único y secuencial que queda en la BBDD y en el PDF.
--
-- Diseño:
--   * La numeración es independiente por tenant (cada negocio empieza en 1).
--   * El contador vive en tenants.ultimo_numero_socio. El trigger lo
--     incrementa con un UPDATE ... RETURNING, que bloquea la fila del
--     tenant hasta el COMMIT: dos altas simultáneas del mismo tenant
--     nunca reciben el mismo número y no quedan huecos por concurrencia.
--   * El número lo asigna siempre la BBDD. n8n no tiene que enviarlo
--     (si lo envía, se ignora) y no se puede modificar después.
--
-- Este script se ejecuta solo en volúmenes nuevos. En una BBDD que ya
-- existe, hay que lanzarlo a mano (rellena los clientes que ya existan):
--   docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < database/init/003_numero_socio.sql

\connect agnosticflow

BEGIN;

-- 1. COLUMNAS

ALTER TABLE tenants
    ADD COLUMN ultimo_numero_socio INTEGER NOT NULL DEFAULT 0;

ALTER TABLE clientes
    ADD COLUMN numero_socio INTEGER;

-- 2. RELLENAR LOS CLIENTES QUE YA EXISTAN (por orden de alta)

UPDATE clientes c
SET numero_socio = n.num
FROM (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY tenant_id
               ORDER BY created_at, id
           ) AS num
    FROM clientes
) n
WHERE c.id = n.id;

UPDATE tenants t
SET ultimo_numero_socio = COALESCE((
    SELECT MAX(c.numero_socio)
    FROM clientes c
    WHERE c.tenant_id = t.id
), 0);

-- 3. RESTRICCIONES

ALTER TABLE tenants
    ADD CONSTRAINT chk_tenant_ultimo_numero_socio
        CHECK (ultimo_numero_socio >= 0);

ALTER TABLE clientes
    ALTER COLUMN numero_socio SET NOT NULL,

    ADD CONSTRAINT chk_cliente_numero_socio
        CHECK (numero_socio > 0),

    -- El UNIQUE crea también el índice B-Tree (tenant_id, numero_socio)
    ADD CONSTRAINT uq_cliente_tenant_numero_socio
        UNIQUE (tenant_id, numero_socio);

-- 4. ASIGNACIÓN AUTOMÁTICA AL INSERTAR

CREATE FUNCTION asignar_numero_socio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tenants
    SET ultimo_numero_socio = ultimo_numero_socio + 1
    WHERE id = NEW.tenant_id
    RETURNING ultimo_numero_socio INTO NEW.numero_socio;

    -- Sin tenant no hay número: se devuelve el mismo error que daría la FK
    -- (si no, saltaría antes el NOT NULL de numero_socio)
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'El tenant % no existe', NEW.tenant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_clientes_numero_socio
    BEFORE INSERT ON clientes
    FOR EACH ROW
    EXECUTE FUNCTION asignar_numero_socio();

-- 5. EL NÚMERO NO SE PUEDE CAMBIAR

CREATE FUNCTION bloquear_cambio_numero_socio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.numero_socio IS DISTINCT FROM OLD.numero_socio
       OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION
            'El número de socio y el tenant de un cliente no se pueden modificar'
            USING ERRCODE = 'restrict_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_clientes_numero_socio_inmutable
    BEFORE UPDATE OF numero_socio, tenant_id ON clientes
    FOR EACH ROW
    EXECUTE FUNCTION bloquear_cambio_numero_socio();

COMMIT;
