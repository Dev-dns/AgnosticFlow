
-- Crear la base de datos de negocio de AgnosticFlow.
-- PostgreSQL ya crea POSTGRES_DB para n8n.

SELECT 'CREATE DATABASE agnosticflow'
WHERE NOT EXISTS (
    SELECT FROM pg_database
    WHERE datname = 'agnosticflow'
)
\gexec
