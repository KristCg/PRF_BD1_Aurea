-- =====================================================================
-- Cafeteria AUREA · CC3088 Base de Datos 1 · Proyecto No. 2
-- 00 · CARGA COMPLETA
--
-- Corre los seis scripts en orden sobre una base VACIA.
--
--     createdb PRF_Aurea
--     psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 00_cargar_todo.sql
--
-- Este archivo usa \ir, que es un comando de psql. En el Query Tool de
-- pgAdmin NO funciona: ahi hay que abrir y ejecutar los seis archivos
-- uno por uno, del 01 al 06. Ver el README.
-- =====================================================================

\echo '>>> 01 · esquema'
\ir 01_schema.sql
\echo '>>> 02 · funciones y triggers'
\ir 02_funciones.sql
\echo '>>> 03 · vistas y reportes'
\ir 03_vistas.sql
\echo '>>> 04 · indices'
\ir 04_indices.sql
\echo '>>> 05 · catalogo'
\ir 05_seed_catalogo.sql
\echo '>>> 06 · datos de demostracion'
\ir 06_seed_demo.sql
\echo ''
\echo '>>> Carga terminada.'
