
-- =====================================================
-- AGNOSTICFLOW
-- Entregable 2: Esquema Relacional Multi-Tenant
-- Base de datos: agnosticflow
-- =====================================================

\connect agnosticflow

BEGIN;

-- 1. TENANTS
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(150) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. CLIENTES
CREATE TABLE clientes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    dni VARCHAR(20) NOT NULL,
    telefono VARCHAR(25) NOT NULL,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_cliente_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES tenants(id),

    CONSTRAINT uq_cliente_tenant_dni
        UNIQUE (tenant_id, dni),

    CONSTRAINT uq_cliente_tenant_id
        UNIQUE (tenant_id, id)
);

-- 3. TRANSACCIONES
CREATE TABLE transacciones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    cliente_id UUID NOT NULL,

    estado VARCHAR(30) NOT NULL DEFAULT 'PENDIENTE',
    pdf_uri TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_transaccion_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES tenants(id),

    CONSTRAINT fk_transaccion_cliente
        FOREIGN KEY (tenant_id, cliente_id)
        REFERENCES clientes(tenant_id, id),

    CONSTRAINT uq_transaccion_tenant_id
        UNIQUE (tenant_id, id),

    CONSTRAINT chk_transaccion_estado
        CHECK (estado IN (
            'PENDIENTE',
            'PROCESANDO',
            'COMPLETADO',
            'ERROR'
        ))
);

-- 4. LOGS
CREATE TABLE logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    transaccion_id UUID NOT NULL,

    nivel VARCHAR(10) NOT NULL DEFAULT 'INFO',
    mensaje TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_log_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES tenants(id),

    CONSTRAINT fk_log_transaccion
        FOREIGN KEY (tenant_id, transaccion_id)
        REFERENCES transacciones(tenant_id, id),

    CONSTRAINT chk_log_nivel
        CHECK (nivel IN ('INFO', 'WARN', 'ERROR'))
);

-- 5. INDICES B-TREE MULTI-TENANT

CREATE INDEX idx_clientes_tenant
    ON clientes USING BTREE (tenant_id);

CREATE INDEX idx_transacciones_tenant
    ON transacciones USING BTREE (tenant_id);

CREATE INDEX idx_logs_tenant
    ON logs USING BTREE (tenant_id);

CREATE INDEX idx_transacciones_tenant_fecha
    ON transacciones USING BTREE (tenant_id, created_at);

COMMIT;
