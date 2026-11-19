-- Nota: este   SCRIPT Vacia SOLO los datos simulados (staging + hechos simulados) para recargarlos desde cero.
-- No toca las tablas operativas (orden, detalle_orden, ...) ni los datos reales que teniamos en el el Proyecto 2.
-- ATENCION: Usarlo SOLO SI ya habian subido la primera version de los datos simulados, se corrigio porque tenia un pequeño error
BEGIN;
DELETE FROM datamart.fact_ventas WHERE origen_datos = 'Simulado SQL';
TRUNCATE TABLE staging.ventas_simuladas;
COMMIT;
