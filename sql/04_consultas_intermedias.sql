-- =============================================================================
-- 04_consultas_intermedias.sql — Consultas SQL intermedias (sección 2 del examen)
-- Base: PostgreSQL. Requiere 01_schema.sql.
--
-- Conceptos: INNER JOIN, LEFT JOIN, COUNT, GROUP BY, HAVING, IS NULL, CASE.
-- Regla del proyecto: sin SELECT *; con JOIN siempre usamos alias de tabla
-- (p = persons, t = tenants, m = modules, ...) y calificamos cada columna.
--
-- TRUCOS PARA NO EQUIVOCARSE (léelos antes de practicar):
--   1. INNER JOIN solo muestra filas que tienen pareja en ambas tablas.
--   2. LEFT JOIN muestra TODAS las filas de la tabla de la izquierda, aunque
--      no tengan pareja (las columnas de la derecha salen NULL).
--   3. Si el enunciado dice "cada X" o "que no tengan...", parte de X con
--      LEFT JOIN.
--   4. COUNT(columna) no cuenta los NULL; COUNT(*) cuenta filas. Con LEFT JOIN
--      cuenta la columna de la tabla de la derecha (así una empresa sin
--      personas da 0 y no 1).
--   5. Toda columna del SELECT que no esté dentro de una función agregada
--      debe ir en el GROUP BY.
--   6. WHERE filtra filas ANTES de agrupar; HAVING filtra grupos DESPUÉS.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Personas con su nombre completo y la organización a la que pertenecen
-- Clave: INNER JOIN persons -> tenants; || une textos (en MySQL sería CONCAT).
-- -----------------------------------------------------------------------------
SELECT p.id,
       p.first_name || ' ' || p.last_name AS full_name,
       t.legal_name                       AS organization
FROM persons AS p
INNER JOIN tenants AS t ON t.id = p.tenant_id
ORDER BY t.legal_name, p.last_name;


-- -----------------------------------------------------------------------------
-- 2. Cada persona con el cargo que desempeña
-- Clave: INNER JOIN persons -> positions (por position_id)
-- -----------------------------------------------------------------------------
SELECT p.id,
       p.first_name,
       p.last_name,
       pos.name AS position_name
FROM persons AS p
INNER JOIN positions AS pos ON pos.id = p.position_id
ORDER BY p.last_name;


-- -----------------------------------------------------------------------------
-- 3. Cada organización con su tamaño de empresa
-- Clave: INNER JOIN tenants -> tenant_sizes
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       ts.name AS tenant_size
FROM tenants AS t
INNER JOIN tenant_sizes AS ts ON ts.id = t.tenant_size_id
ORDER BY t.legal_name;


-- -----------------------------------------------------------------------------
-- 4. Cada organización con su ciudad, departamento y país
-- Clave: cadena de JOIN: tenants -> cities -> departments -> countries
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       c.name  AS city,
       d.name  AS department,
       co.name AS country
FROM tenants AS t
INNER JOIN cities      AS c  ON c.id  = t.city_id
INNER JOIN departments AS d  ON d.id  = c.department_id
INNER JOIN countries   AS co ON co.id = d.country_id
ORDER BY co.name, d.name, c.name;


-- -----------------------------------------------------------------------------
-- 5. Cuántas personas hay registradas en cada organización
-- Clave: LEFT JOIN + COUNT(p.id) + GROUP BY.
-- LEFT JOIN para que las empresas sin personas aparezcan con 0.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       COUNT(p.id) AS total_persons
FROM tenants AS t
LEFT JOIN persons AS p ON p.tenant_id = t.id
GROUP BY t.id, t.legal_name
ORDER BY total_persons DESC, t.legal_name;


-- -----------------------------------------------------------------------------
-- 6. Organizaciones con MÁS de N personas registradas
-- Clave: HAVING filtra sobre el resultado del COUNT (WHERE no puede hacerlo).
-- Cambia el 2 por la cantidad que te pidan.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       COUNT(p.id) AS total_persons
FROM tenants AS t
INNER JOIN persons AS p ON p.tenant_id = t.id
GROUP BY t.id, t.legal_name
HAVING COUNT(p.id) > 2
ORDER BY total_persons DESC;


-- -----------------------------------------------------------------------------
-- 7. Módulos habilitados para cada organización (tenant_modules)
-- Clave: tabla intermedia (relación muchos a muchos) -> dos JOIN.
-- "Habilitado" = is_active = true.
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       m.title AS module_title,
       tm.enabled_at
FROM tenant_modules AS tm
INNER JOIN tenants AS t ON t.id = tm.tenant_id
INNER JOIN modules AS m ON m.id = tm.module_id
WHERE tm.is_active = true
ORDER BY t.legal_name, m.sort_order;


-- -----------------------------------------------------------------------------
-- 8. Cuántos módulos tiene habilitados cada organización
-- Clave: LEFT JOIN con la condición en el ON (no en el WHERE).
-- Si pusieras "tm.is_active = true" en el WHERE, las empresas con 0 módulos
-- desaparecerían y el LEFT JOIN se comportaría como un INNER JOIN.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       COUNT(tm.id) AS enabled_modules
FROM tenants AS t
LEFT JOIN tenant_modules AS tm
       ON tm.tenant_id = t.id
      AND tm.is_active = true
GROUP BY t.id, t.legal_name
ORDER BY enabled_modules DESC, t.legal_name;


-- -----------------------------------------------------------------------------
-- 9. Sistemas SST habilitados para cada organización
-- Clave: tenantsystems (intermedia) + type_system_sst
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       s.code AS system_code,
       s.name AS system_name
FROM tenantsystems AS ts
INNER JOIN tenants         AS t ON t.id = ts.tenant_id
INNER JOIN type_system_sst AS s ON s.id = ts.type_system_sst_id
WHERE ts.is_active = true
ORDER BY t.legal_name, s.code;


-- -----------------------------------------------------------------------------
-- 10. Módulos existentes con el sistema SST al que pertenecen
-- Clave: INNER JOIN modules -> type_system_sst
-- -----------------------------------------------------------------------------
SELECT m.id,
       m.title       AS module_title,
       s.name        AS system_name
FROM modules AS m
INNER JOIN type_system_sst AS s ON s.id = m.type_system_sst_id
ORDER BY s.name, m.sort_order;


-- -----------------------------------------------------------------------------
-- 11. Formatos registrados con el módulo al que pertenece cada uno
-- Clave: INNER JOIN formats_sst -> modules
-- -----------------------------------------------------------------------------
SELECT f.id,
       f.code,
       f.name  AS format_name,
       m.title AS module_title
FROM formats_sst AS f
INNER JOIN modules AS m ON m.id = f.module_id
ORDER BY m.title, f.code;


-- -----------------------------------------------------------------------------
-- 12. Cuántos formatos tiene cada módulo
-- Clave: LEFT JOIN desde modules (los módulos sin formatos salen con 0)
-- -----------------------------------------------------------------------------
SELECT m.id,
       m.title,
       COUNT(f.id) AS total_formats
FROM modules AS m
LEFT JOIN formats_sst AS f ON f.module_id = m.id
GROUP BY m.id, m.title
ORDER BY total_formats DESC, m.title;


-- -----------------------------------------------------------------------------
-- 13. Plantillas asignadas a cada organización (tenanttemplates)
-- Clave: tabla intermedia tenants <-> templates
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       tp.code AS template_code,
       tp.name AS template_name,
       tt.assigned_at
FROM tenanttemplates AS tt
INNER JOIN tenants   AS t  ON t.id  = tt.tenant_id
INNER JOIN templates AS tp ON tp.id = tt.template_id
ORDER BY t.legal_name, tp.code;


-- -----------------------------------------------------------------------------
-- 14. Cada plantilla asignada con organización, sistema SST y etapa PHVA
-- Clave: 4 JOIN; el sistema y la etapa PHVA se leen desde la plantilla.
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       tp.name AS template_name,
       s.name  AS system_name,
       ph.name AS phva_stage
FROM tenanttemplates AS tt
INNER JOIN tenants         AS t  ON t.id  = tt.tenant_id
INNER JOIN templates       AS tp ON tp.id = tt.template_id
INNER JOIN type_system_sst AS s  ON s.id  = tp.type_system_sst_id
INNER JOIN phva_stages     AS ph ON ph.id = tp.phva_stage_id
ORDER BY t.legal_name, ph.sort_order;


-- -----------------------------------------------------------------------------
-- 15. Cuántas plantillas tiene asignada cada organización
-- Clave: LEFT JOIN + COUNT desde tenants
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       COUNT(tt.id) AS total_templates
FROM tenants AS t
LEFT JOIN tenanttemplates AS tt ON tt.tenant_id = t.id
GROUP BY t.id, t.legal_name
ORDER BY total_templates DESC, t.legal_name;


-- -----------------------------------------------------------------------------
-- 16. Organizaciones que NO tienen personas registradas
-- Clave: LEFT JOIN + WHERE columna_derecha IS NULL (patrón "anti-join")
-- Se queda con las filas del lado izquierdo que no encontraron pareja.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name
FROM tenants AS t
LEFT JOIN persons AS p ON p.tenant_id = t.id
WHERE p.id IS NULL
ORDER BY t.legal_name;


-- -----------------------------------------------------------------------------
-- 17. Módulos que todavía no han sido asignados a ninguna organización
-- Clave: mismo patrón anti-join, ahora modules -> tenant_modules
-- -----------------------------------------------------------------------------
SELECT m.id,
       m.title
FROM modules AS m
LEFT JOIN tenant_modules AS tm ON tm.module_id = m.id
WHERE tm.id IS NULL
ORDER BY m.title;


-- -----------------------------------------------------------------------------
-- 18. Etapas PHVA con el número de plantillas asociadas a cada una
-- Clave: LEFT JOIN + COUNT (una etapa sin plantillas sale con 0)
-- -----------------------------------------------------------------------------
SELECT ph.id,
       ph.name,
       COUNT(tp.id) AS total_templates
FROM phva_stages AS ph
LEFT JOIN templates AS tp ON tp.phva_stage_id = ph.id
GROUP BY ph.id, ph.name, ph.sort_order
ORDER BY ph.sort_order;


-- -----------------------------------------------------------------------------
-- 19. Cuántas organizaciones hay registradas en cada ciudad
-- Clave: LEFT JOIN desde cities (las ciudades sin organizaciones salen con 0).
-- Si solo quieres las ciudades que sí tienen, cambia LEFT JOIN por INNER JOIN.
-- -----------------------------------------------------------------------------
SELECT c.id,
       c.name AS city,
       COUNT(t.id) AS total_tenants
FROM cities AS c
LEFT JOIN tenants AS t ON t.city_id = c.id
GROUP BY c.id, c.name
ORDER BY total_tenants DESC, c.name;


-- -----------------------------------------------------------------------------
-- 20. Cargos de cada organización y cuántas personas ocupan cada cargo
-- Clave: GROUP BY con varias columnas; LEFT JOIN a persons para ver cargos
-- vacíos con 0.
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       pos.name     AS position_name,
       COUNT(p.id)  AS total_persons
FROM positions AS pos
INNER JOIN tenants AS t ON t.id = pos.tenant_id
LEFT JOIN  persons AS p ON p.position_id = pos.id
GROUP BY t.id, t.legal_name, pos.id, pos.name
ORDER BY t.legal_name, pos.name;


-- =============================================================================
-- EXTRAS DE PRÁCTICA (el enunciado menciona "expresiones condicionales" y
-- funciones agregadas; el profesor podría pedir variaciones)
-- =============================================================================

-- E1. Estado de cada persona con texto legible
-- Clave: CASE WHEN ... THEN ... ELSE ... END (el "if" de SQL)
SELECT p.id,
       p.first_name,
       p.last_name,
       CASE WHEN p.is_active THEN 'Activa' ELSE 'Inactiva' END AS status
FROM persons AS p
ORDER BY p.last_name;

-- E2. Cuántos tipos de documento distintos usa cada organización
-- Clave: COUNT(DISTINCT columna) cuenta valores diferentes, no filas
SELECT t.legal_name,
       COUNT(DISTINCT p.document_type) AS different_document_types
FROM tenants AS t
LEFT JOIN persons AS p ON p.tenant_id = t.id
GROUP BY t.id, t.legal_name
ORDER BY t.legal_name;

-- E3. Primera y última contratación por organización
-- Clave: MIN y MAX (también existen AVG, SUM)
SELECT t.legal_name,
       MIN(p.hire_date) AS first_hire,
       MAX(p.hire_date) AS last_hire
FROM tenants AS t
INNER JOIN persons AS p ON p.tenant_id = t.id
GROUP BY t.id, t.legal_name
ORDER BY t.legal_name;
