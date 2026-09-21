-- =============================================================================
-- 03_consultas_basicas.sql — Consultas SQL básicas (sección 1 del examen)
-- Base: PostgreSQL. Requiere haber ejecutado antes 01_schema.sql.
--
-- Cómo usarlo en pgAdmin: selecciona UNA consulta y ejecútala (F5).
-- Los valores de ejemplo (ids, palabras, fechas) se cambian por tu criterio.
-- Regla del proyecto: sin SELECT *; siempre se listan las columnas.
-- Convención: en consultas de una sola tabla no usamos alias (más legible).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Todos los registros de tenants (todas las columnas, listadas una a una)
-- Clave: SELECT columnas FROM tabla
-- -----------------------------------------------------------------------------
SELECT id, tenant_size_id, city_id, legal_name, trade_name, tax_id, check_digit,
       email, phone, address, contact_name, contact_email, slug,
       is_active, created_at, updated_at
FROM tenants;


-- -----------------------------------------------------------------------------
-- 2. Nombre, correo de contacto y teléfono de las organizaciones
-- Clave: elegir solo algunas columnas
-- Nota: "nombre" = legal_name (razón social); "correo" = email de la empresa.
-- -----------------------------------------------------------------------------
SELECT legal_name, email, phone
FROM tenants;


-- -----------------------------------------------------------------------------
-- 3. Personas con nombres, apellidos y correo
-- Clave: SELECT de varias columnas
-- -----------------------------------------------------------------------------
SELECT first_name, last_name, email
FROM persons;


-- -----------------------------------------------------------------------------
-- 4. Personas activas
-- Clave: WHERE con una condición booleana ("estado activo" = is_active)
-- -----------------------------------------------------------------------------
SELECT id, first_name, last_name, email
FROM persons
WHERE is_active = true;


-- -----------------------------------------------------------------------------
-- 5. Organizaciones cuyo nombre contiene una palabra
-- Clave: ILIKE con comodines %. ILIKE ignora mayúsculas (propio de PostgreSQL);
--        con LIKE sí distinguiría mayúsculas de minúsculas.
-- Cambia 'construc' por la palabra que te pidan.
-- -----------------------------------------------------------------------------
SELECT id, legal_name, trade_name
FROM tenants
WHERE legal_name ILIKE '%construc%';


-- -----------------------------------------------------------------------------
-- 6. Países ordenados alfabéticamente
-- Clave: ORDER BY (ASC es el orden por defecto)
-- -----------------------------------------------------------------------------
SELECT id, iso_code, name
FROM countries
ORDER BY name;


-- -----------------------------------------------------------------------------
-- 7. Departamentos de un país determinado
-- Clave: WHERE sobre la llave foránea country_id
-- Cambia el 1 por el id del país (ver consulta 6 para conocer los ids).
-- -----------------------------------------------------------------------------
SELECT id, code, name
FROM departments
WHERE country_id = 1
ORDER BY name;


-- -----------------------------------------------------------------------------
-- 8. Ciudades de un departamento determinado
-- Clave: igual que la 7, pero con department_id
-- -----------------------------------------------------------------------------
SELECT id, code, name
FROM cities
WHERE department_id = 1
ORDER BY name;


-- -----------------------------------------------------------------------------
-- 9. Cargos ordenados por descripción
-- Clave: ORDER BY sobre una columna que puede ser NULL.
-- En orden ascendente PostgreSQL deja los NULL al final.
-- -----------------------------------------------------------------------------
SELECT id, tenant_id, name, code, risk_level, description
FROM positions
ORDER BY description;


-- -----------------------------------------------------------------------------
-- 10. Personas de una organización determinada (por tenant_id)
-- Clave: WHERE con la columna que separa a las empresas (multi-tenant)
-- -----------------------------------------------------------------------------
SELECT id, document_type, document_number, first_name, last_name, email
FROM persons
WHERE tenant_id = 1;


-- -----------------------------------------------------------------------------
-- 11. Organizaciones habilitadas (activas)
-- Clave: WHERE is_active = true
-- -----------------------------------------------------------------------------
SELECT id, legal_name, trade_name
FROM tenants
WHERE is_active = true;


-- -----------------------------------------------------------------------------
-- 12. Organizaciones registradas dentro de un período
-- Clave: rango de fechas con >= y <  (límite final EXCLUIDO).
-- created_at es timestamptz: si usaras BETWEEN '2026-01-01' AND '2026-06-30',
-- quedaría fuera todo lo del 30 de junio después de las 00:00.
-- Este ejemplo cubre del 1 de enero al 30 de junio de 2026.
-- -----------------------------------------------------------------------------
SELECT id, legal_name, created_at
FROM tenants
WHERE created_at >= '2026-01-01'
  AND created_at <  '2026-07-01'
ORDER BY created_at;

-- Variante con BETWEEN (compara solo la parte de fecha, por eso es correcta):
-- SELECT id, legal_name, created_at
-- FROM tenants
-- WHERE created_at::date BETWEEN '2026-01-01' AND '2026-06-30';


-- -----------------------------------------------------------------------------
-- 13. Tamaños de empresa distintos
-- Clave: DISTINCT elimina filas repetidas. Aquí ya son únicos por las
-- restricciones, pero el enunciado pide "los diferentes".
-- -----------------------------------------------------------------------------
SELECT DISTINCT code, name, min_employees, max_employees, sort_order
FROM tenant_sizes
ORDER BY sort_order;


-- -----------------------------------------------------------------------------
-- 14. Tipos de sistema SST distintos (SST, PESV)
-- Clave: DISTINCT
-- -----------------------------------------------------------------------------
SELECT DISTINCT code, name, description
FROM type_system_sst
ORDER BY name;


-- -----------------------------------------------------------------------------
-- 15. Módulos con título, descripción y orden de presentación
-- Clave: ORDER BY sobre sort_order
-- -----------------------------------------------------------------------------
SELECT title, description, sort_order
FROM modules
ORDER BY sort_order;


-- =============================================================================
-- EXTRAS DE PRÁCTICA (no son del examen, pero el profesor podría pedir
-- variaciones con estos operadores: IS NULL, IN, LIMIT, BETWEEN, DISTINCT)
-- =============================================================================

-- E1. Personas sin correo electrónico
-- Clave: IS NULL (nunca "= NULL", porque NULL no es igual a nada)
SELECT id, first_name, last_name
FROM persons
WHERE email IS NULL;

-- E2. Organizaciones ubicadas en alguna de varias ciudades
-- Clave: IN (lista de valores)
SELECT id, legal_name, city_id
FROM tenants
WHERE city_id IN (1, 2, 3);

-- E3. Las 5 personas contratadas más recientemente
-- Clave: ORDER BY ... DESC + LIMIT
SELECT id, first_name, last_name, hire_date
FROM persons
ORDER BY hire_date DESC
LIMIT 5;

-- E4. Personas contratadas dentro de un rango de fechas
-- Clave: BETWEEN (hire_date es tipo date, por eso aquí sí funciona bien)
SELECT id, first_name, last_name, hire_date
FROM persons
WHERE hire_date BETWEEN '2024-01-01' AND '2024-12-31'
ORDER BY hire_date;

-- E5. Tipos de documento que se usan en las personas
-- Clave: DISTINCT sobre una columna que sí se repite
SELECT DISTINCT document_type
FROM persons
ORDER BY document_type;
