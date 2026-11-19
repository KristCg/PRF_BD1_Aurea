CREATE TABLE staging.ventas_simuladas (
    LIKE staging.ventas_originales
);

SELECT COUNT(*) AS lineas_simuladas
FROM staging.ventas_simuladas;

SELECT *
FROM staging.ventas_simuladas
LIMIT 5;