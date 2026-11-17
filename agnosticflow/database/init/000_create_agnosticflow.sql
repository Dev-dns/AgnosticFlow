
-- Crear la base de datos de negocio de AgnosticFlow.
-- POSTGRES_DB (n8n) la crea la imagen de PostgreSQL; esta va aparte
-- para que las tablas internas de n8n no se mezclen con las de negocio.

SELECT 'CREATE DATABASE agnosticflow'
WHERE NOT EXISTS (
    SELECT FROM pg_database
    WHERE datname = 'agnosticflow'
)
\gexec
