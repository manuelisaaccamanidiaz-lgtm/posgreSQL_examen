-- =============================================================================
-- 06_consultas_avanzadas.sql — Consultas SQL avanzadas (sección 3 del examen)
-- Base: PostgreSQL. Requiere 01_schema.sql y 05_vistas.sql (Parte A: crea las
-- vistas materializadas vm_template_sst_docs_summary y vm_template_pesv_docs_summary
-- que usan las consultas 10–14 y 22–24). Para ver resultados, carga también los datos
-- y ejecuta REFRESH MATERIALIZED VIEW en esas dos vistas.
--
-- Conceptos: subconsultas, EXISTS, CTE (WITH), funciones de ventana (OVER),
-- agregación condicional (SUM + CASE), auto-JOIN, CROSS JOIN, vistas.
-- Regla del proyecto: sin SELECT *; alias en cada tabla; columnas calificadas.
--
-- SUPUESTOS (el examen no los define; confírmalos con el profesor):
--   A. Las dos vistas de resumen (definidas en 05_vistas.sql) tienen UNA fila por
--      organización y sistema. Solo cuenta la ÚLTIMA versión ACTIVA de cada documento.
--   B. Pendientes = no_iniciado + borrador.
--      Cumplimiento (%) = finalizados / total de documentos * 100.
--   C. Categorías de cumplimiento (consulta 12): Bajo < 40, Medio 40–69,
--      Alto >= 70. Umbral de la consulta 24: 20 puntos porcentuales.
--   D. Consulta 15: acumulado en el tiempo (por fecha de finalización) dentro
--      de cada organización.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Organización(es) con la mayor cantidad de personas
-- Clave: HAVING = (subconsulta con MAX). Si hay empate, muestra a todas las
-- empatadas. Con ORDER BY ... DESC LIMIT 1 solo saldría una (más simple, pero
-- oculta empates).
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       COUNT(p.id) AS total_persons
FROM tenants AS t
INNER JOIN persons AS p ON p.tenant_id = t.id
GROUP BY t.id, t.legal_name
HAVING COUNT(p.id) = (SELECT MAX(x.cnt)
                      FROM (SELECT COUNT(*) AS cnt
                            FROM persons
                            GROUP BY tenant_id) AS x);


-- -----------------------------------------------------------------------------
-- 2. Organizaciones con más personas que el promedio general
-- Clave: subconsulta escalar en el HAVING.
-- Promedio = total de personas / total de organizaciones (incluye las de 0).
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       COUNT(p.id) AS total_persons
FROM tenants AS t
LEFT JOIN persons AS p ON p.tenant_id = t.id
GROUP BY t.id, t.legal_name
HAVING COUNT(p.id) > (SELECT COUNT(*) FROM persons)::numeric
                   / (SELECT COUNT(*) FROM tenants);


-- -----------------------------------------------------------------------------
-- 3. Organizaciones con TODOS los módulos habilitados de un sistema SST
-- Clave: "todos" = contar los módulos distintos de la organización y compararlos
-- con el total de módulos del sistema. Cambia 'SST' por 'PESV' si lo piden.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name
FROM tenants AS t
INNER JOIN tenant_modules  AS tm ON tm.tenant_id = t.id AND tm.is_active = true
INNER JOIN modules         AS m  ON m.id = tm.module_id AND m.is_active = true
INNER JOIN type_system_sst AS s  ON s.id = m.type_system_sst_id
WHERE s.code = 'SST'
GROUP BY t.id, t.legal_name
HAVING COUNT(DISTINCT m.id) = (SELECT COUNT(*)
                               FROM modules AS m2
                               INNER JOIN type_system_sst AS s2 ON s2.id = m2.type_system_sst_id
                               WHERE s2.code = 'SST'
                                 AND m2.is_active = true);


-- -----------------------------------------------------------------------------
-- 4. Organizaciones con al menos un módulo pero SIN plantillas asignadas
-- Clave: EXISTS (¿hay al menos una fila?) y NOT EXISTS (¿no hay ninguna?).
-- El SELECT 1 interno da igual: solo importa si devuelve filas o no.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name
FROM tenants AS t
WHERE EXISTS (SELECT 1
              FROM tenant_modules AS tm
              WHERE tm.tenant_id = t.id
                AND tm.is_active = true)
  AND NOT EXISTS (SELECT 1
                  FROM tenanttemplates AS tt
                  WHERE tt.tenant_id = t.id);


-- -----------------------------------------------------------------------------
-- 5. Organizaciones con plantillas en TODAS las etapas PHVA
-- Clave: COUNT(DISTINCT etapa) = total de etapas (misma técnica de la 3).
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name
FROM tenants AS t
INNER JOIN tenanttemplates AS tt ON tt.tenant_id = t.id
INNER JOIN templates       AS tp ON tp.id = tt.template_id
GROUP BY t.id, t.legal_name
HAVING COUNT(DISTINCT tp.phva_stage_id) = (SELECT COUNT(*)
                                           FROM phva_stages
                                           WHERE is_active = true);


-- -----------------------------------------------------------------------------
-- 6. Plantillas por organización, discriminadas por etapa PHVA
-- Clave: GROUP BY con dos niveles (organización y etapa)
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       ph.name      AS phva_stage,
       COUNT(tt.id) AS total_templates
FROM tenanttemplates AS tt
INNER JOIN tenants     AS t  ON t.id  = tt.tenant_id
INNER JOIN templates   AS tp ON tp.id = tt.template_id
INNER JOIN phva_stages AS ph ON ph.id = tp.phva_stage_id
GROUP BY t.id, t.legal_name, ph.id, ph.name, ph.sort_order
ORDER BY t.legal_name, ph.sort_order;


-- -----------------------------------------------------------------------------
-- 7. Plantillas por etapa en columnas independientes (Planear/Hacer/Verificar/Actuar)
-- Clave: agregación condicional SUM(CASE WHEN ... THEN 1 ELSE 0 END).
-- Convierte filas en columnas ("pivotar").
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       SUM(CASE WHEN ph.code = 'P' THEN 1 ELSE 0 END) AS planear,
       SUM(CASE WHEN ph.code = 'H' THEN 1 ELSE 0 END) AS hacer,
       SUM(CASE WHEN ph.code = 'V' THEN 1 ELSE 0 END) AS verificar,
       SUM(CASE WHEN ph.code = 'A' THEN 1 ELSE 0 END) AS actuar
FROM tenants AS t
LEFT JOIN tenanttemplates AS tt ON tt.tenant_id = t.id
LEFT JOIN templates       AS tp ON tp.id = tt.template_id
LEFT JOIN phva_stages     AS ph ON ph.id = tp.phva_stage_id
GROUP BY t.id, t.legal_name
ORDER BY t.legal_name;


-- -----------------------------------------------------------------------------
-- 8. Porcentaje de cada etapa PHVA sobre el total de plantillas de la organización
-- Clave: CTE + función de ventana SUM(...) OVER (PARTITION BY organización).
-- La ventana suma el total de cada organización SIN colapsar las filas.
-- -----------------------------------------------------------------------------
WITH per_stage AS (
    SELECT t.id         AS tenant_id,
           t.legal_name,
           ph.name      AS phva_stage,
           ph.sort_order,
           COUNT(tt.id) AS total_templates
    FROM tenanttemplates AS tt
    INNER JOIN tenants     AS t  ON t.id  = tt.tenant_id
    INNER JOIN templates   AS tp ON tp.id = tt.template_id
    INNER JOIN phva_stages AS ph ON ph.id = tp.phva_stage_id
    GROUP BY t.id, t.legal_name, ph.id, ph.name, ph.sort_order
)
SELECT ps.legal_name,
       ps.phva_stage,
       ps.total_templates,
       ROUND(100.0 * ps.total_templates
             / SUM(ps.total_templates) OVER (PARTITION BY ps.tenant_id), 2) AS pct_of_total
FROM per_stage AS ps
ORDER BY ps.legal_name, ps.sort_order;


-- -----------------------------------------------------------------------------
-- 9. Etapa PHVA con más plantillas dentro de cada organización
-- Clave: RANK() OVER (PARTITION BY ... ORDER BY ... DESC) y filtrar rnk = 1.
-- RANK conserva empates; ROW_NUMBER() devolvería solo una por organización.
-- -----------------------------------------------------------------------------
WITH per_stage AS (
    SELECT t.id         AS tenant_id,
           t.legal_name,
           ph.name      AS phva_stage,
           COUNT(tt.id) AS total_templates
    FROM tenanttemplates AS tt
    INNER JOIN tenants     AS t  ON t.id  = tt.tenant_id
    INNER JOIN templates   AS tp ON tp.id = tt.template_id
    INNER JOIN phva_stages AS ph ON ph.id = tp.phva_stage_id
    GROUP BY t.id, t.legal_name, ph.id, ph.name
),
ranked AS (
    SELECT ps.tenant_id,
           ps.legal_name,
           ps.phva_stage,
           ps.total_templates,
           RANK() OVER (PARTITION BY ps.tenant_id ORDER BY ps.total_templates DESC) AS rnk
    FROM per_stage AS ps
)
SELECT r.legal_name,
       r.phva_stage,
       r.total_templates
FROM ranked AS r
WHERE r.rnk = 1
ORDER BY r.legal_name, r.phva_stage;


-- -----------------------------------------------------------------------------
-- 10. Porcentaje de documentos finalizados por organización (con las vistas de resumen)
-- Clave: UNION ALL une las filas de SST y de PESV; luego se suman por organización.
-- NULLIF(x, 0) evita dividir por cero.
-- -----------------------------------------------------------------------------
SELECT s.tenant_id,
       s.legal_name,
       SUM(s.total_documents)    AS total_documents,
       SUM(s.finished_documents) AS finished_documents,
       ROUND(100.0 * SUM(s.finished_documents) / NULLIF(SUM(s.total_documents), 0), 2) AS completion_pct
FROM (SELECT tenant_id, legal_name, total_documents, finished_documents
      FROM vm_template_sst_docs_summary
      UNION ALL
      SELECT tenant_id, legal_name, total_documents, finished_documents
      FROM vm_template_pesv_docs_summary) AS s
GROUP BY s.tenant_id, s.legal_name
ORDER BY completion_pct DESC;


-- -----------------------------------------------------------------------------
-- 11. Organizaciones por debajo del promedio general de cumplimiento
-- Clave: CTE "compliance" (la consulta 10 con nombre) + subconsulta con AVG.
-- -----------------------------------------------------------------------------
WITH compliance AS (
    SELECT s.tenant_id,
           s.legal_name,
           ROUND(100.0 * SUM(s.finished_documents) / NULLIF(SUM(s.total_documents), 0), 2) AS completion_pct
    FROM (SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_sst_docs_summary
          UNION ALL
          SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_pesv_docs_summary) AS s
    GROUP BY s.tenant_id, s.legal_name
)
SELECT c.tenant_id,
       c.legal_name,
       c.completion_pct
FROM compliance AS c
WHERE c.completion_pct < (SELECT AVG(completion_pct) FROM compliance)
ORDER BY c.completion_pct;


-- -----------------------------------------------------------------------------
-- 12. Clasificación de cumplimiento: Bajo / Medio / Alto
-- Clave: CASE WHEN (se evalúa de arriba abajo; gana la primera condición cierta)
-- -----------------------------------------------------------------------------
WITH compliance AS (
    SELECT s.tenant_id,
           s.legal_name,
           ROUND(100.0 * SUM(s.finished_documents) / NULLIF(SUM(s.total_documents), 0), 2) AS completion_pct
    FROM (SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_sst_docs_summary
          UNION ALL
          SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_pesv_docs_summary) AS s
    GROUP BY s.tenant_id, s.legal_name
)
SELECT c.tenant_id,
       c.legal_name,
       c.completion_pct,
       CASE WHEN c.completion_pct < 40 THEN 'Bajo'
            WHEN c.completion_pct < 70 THEN 'Medio'
            ELSE 'Alto'
       END AS compliance_level
FROM compliance AS c
ORDER BY c.completion_pct DESC;


-- -----------------------------------------------------------------------------
-- 13. Ranking de organizaciones por cumplimiento
-- Clave: RANK() OVER (ORDER BY ... DESC). Empates comparten posición y se
-- salta la siguiente (1, 2, 2, 4). DENSE_RANK() no salta (1, 2, 2, 3).
-- -----------------------------------------------------------------------------
WITH compliance AS (
    SELECT s.tenant_id,
           s.legal_name,
           ROUND(100.0 * SUM(s.finished_documents) / NULLIF(SUM(s.total_documents), 0), 2) AS completion_pct
    FROM (SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_sst_docs_summary
          UNION ALL
          SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_pesv_docs_summary) AS s
    GROUP BY s.tenant_id, s.legal_name
)
SELECT RANK() OVER (ORDER BY c.completion_pct DESC) AS ranking,
       c.legal_name,
       c.completion_pct
FROM compliance AS c
ORDER BY ranking, c.legal_name;


-- -----------------------------------------------------------------------------
-- 14. Cumplimiento de cada organización y diferencia frente al promedio general
-- Clave: AVG(...) OVER () = promedio de TODAS las filas sin colapsarlas.
-- -----------------------------------------------------------------------------
WITH compliance AS (
    SELECT s.tenant_id,
           s.legal_name,
           ROUND(100.0 * SUM(s.finished_documents) / NULLIF(SUM(s.total_documents), 0), 2) AS completion_pct
    FROM (SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_sst_docs_summary
          UNION ALL
          SELECT tenant_id, legal_name, total_documents, finished_documents
          FROM vm_template_pesv_docs_summary) AS s
    GROUP BY s.tenant_id, s.legal_name
)
SELECT c.legal_name,
       c.completion_pct,
       ROUND(AVG(c.completion_pct) OVER (), 2)                    AS general_average,
       ROUND(c.completion_pct - AVG(c.completion_pct) OVER (), 2) AS difference
FROM compliance AS c
ORDER BY difference DESC;


-- -----------------------------------------------------------------------------
-- 15. Cantidad ACUMULADA de documentos finalizados por organización
-- Clave: COUNT(*) OVER (PARTITION BY organización ORDER BY fecha).
-- Con ORDER BY dentro de OVER, el conteo va sumando fila por fila
-- (total acumulado o "running total").
-- -----------------------------------------------------------------------------
SELECT t.legal_name,
       d.title,
       d.finished_at::date AS finished_date,
       COUNT(*) OVER (PARTITION BY t.id ORDER BY d.finished_at) AS cumulative_finished
FROM documents AS d
INNER JOIN tenanttemplates AS tt ON tt.id = d.tenanttemplate_id
INNER JOIN tenants         AS t  ON t.id  = tt.tenant_id
WHERE d.state = 'finalizado'
  AND d.is_active = true
  AND d.version = (SELECT MAX(d2.version)
                   FROM documents AS d2
                   WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                     AND d2.is_active = true)
ORDER BY t.legal_name, d.finished_at;


-- -----------------------------------------------------------------------------
-- 16. Organizaciones en el mismo municipio pero con distinto tamaño
-- Clave: AUTO-JOIN (la tabla tenants se une consigo misma con dos alias).
-- t2.id > t1.id evita que cada pareja salga dos veces (A-B y B-A).
-- -----------------------------------------------------------------------------
SELECT c.name       AS city,
       t1.legal_name AS organization_1,
       ts1.name      AS size_1,
       t2.legal_name AS organization_2,
       ts2.name      AS size_2
FROM tenants AS t1
INNER JOIN tenants      AS t2  ON t2.city_id = t1.city_id
                              AND t2.id > t1.id
                              AND t2.tenant_size_id <> t1.tenant_size_id
INNER JOIN cities       AS c   ON c.id   = t1.city_id
INNER JOIN tenant_sizes AS ts1 ON ts1.id = t1.tenant_size_id
INNER JOIN tenant_sizes AS ts2 ON ts2.id = t2.tenant_size_id
ORDER BY c.name, t1.legal_name;


-- -----------------------------------------------------------------------------
-- 17. Personas cuyo cargo lo ocupan más personas que el promedio de ocupación
--     de los cargos de su organización
-- Clave: dos CTE encadenadas: (1) personas por cargo, (2) promedio por organización.
-- El promedio incluye cargos vacíos (LEFT JOIN).
-- -----------------------------------------------------------------------------
WITH position_counts AS (
    SELECT pos.tenant_id,
           pos.id       AS position_id,
           COUNT(p.id)  AS persons_in_position
    FROM positions AS pos
    LEFT JOIN persons AS p ON p.position_id = pos.id
    GROUP BY pos.tenant_id, pos.id
),
tenant_average AS (
    SELECT pc.tenant_id,
           AVG(pc.persons_in_position) AS avg_occupancy
    FROM position_counts AS pc
    GROUP BY pc.tenant_id
)
SELECT p.id,
       p.first_name,
       p.last_name,
       pos.name                    AS position_name,
       pc.persons_in_position,
       ROUND(ta.avg_occupancy, 2)  AS avg_occupancy
FROM persons AS p
INNER JOIN positions       AS pos ON pos.id = p.position_id
INNER JOIN position_counts AS pc  ON pc.position_id = p.position_id
INNER JOIN tenant_average  AS ta  ON ta.tenant_id = p.tenant_id
WHERE pc.persons_in_position > ta.avg_occupancy
ORDER BY p.tenant_id, pos.name, p.last_name;


-- -----------------------------------------------------------------------------
-- 18. CTE: personas por organización y luego solo las que superan el promedio
-- Clave: WITH nombre AS (consulta) SELECT ... FROM nombre.
-- Un CTE es una "consulta con nombre" que se puede reutilizar más abajo
-- (aquí se usa dos veces: para filtrar y para calcular el promedio).
-- -----------------------------------------------------------------------------
WITH persons_per_tenant AS (
    SELECT t.id        AS tenant_id,
           t.legal_name,
           COUNT(p.id) AS total_persons
    FROM tenants AS t
    LEFT JOIN persons AS p ON p.tenant_id = t.id
    GROUP BY t.id, t.legal_name
)
SELECT ppt.tenant_id,
       ppt.legal_name,
       ppt.total_persons
FROM persons_per_tenant AS ppt
WHERE ppt.total_persons > (SELECT AVG(total_persons) FROM persons_per_tenant)
ORDER BY ppt.total_persons DESC;


-- -----------------------------------------------------------------------------
-- 19. CTE que consolida módulos, plantillas y personas por organización
-- Clave: agregar CADA cosa por separado en su propio CTE y unir al final.
-- Si unieras las tres tablas directamente, las filas se multiplicarían y los
-- conteos saldrían inflados. COALESCE(x, 0) cambia NULL por 0.
-- -----------------------------------------------------------------------------
WITH modules_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_modules
    FROM tenant_modules
    WHERE is_active = true
    GROUP BY tenant_id
),
templates_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_templates
    FROM tenanttemplates
    WHERE is_active = true
    GROUP BY tenant_id
),
persons_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_persons
    FROM persons
    GROUP BY tenant_id
)
SELECT t.id,
       t.legal_name,
       COALESCE(m.total_modules, 0)   AS total_modules,
       COALESCE(tp.total_templates, 0) AS total_templates,
       COALESCE(p.total_persons, 0)   AS total_persons
FROM tenants AS t
LEFT JOIN modules_per_tenant   AS m  ON m.tenant_id  = t.id
LEFT JOIN templates_per_tenant AS tp ON tp.tenant_id = t.id
LEFT JOIN persons_per_tenant   AS p  ON p.tenant_id  = t.id
ORDER BY t.legal_name;


-- -----------------------------------------------------------------------------
-- 20. Organizaciones a las que les falta alguna etapa PHVA en sus plantillas
-- Clave: CROSS JOIN (todas las combinaciones organización x etapa) + NOT EXISTS
-- (no hay ninguna plantilla asignada de esa etapa). Muestra qué etapa falta.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       ph.name AS missing_stage
FROM tenants AS t
CROSS JOIN phva_stages AS ph
WHERE ph.is_active = true
  AND NOT EXISTS (SELECT 1
                  FROM tenanttemplates AS tt
                  INNER JOIN templates AS tp ON tp.id = tt.template_id
                  WHERE tt.tenant_id = t.id
                    AND tp.phva_stage_id = ph.id)
ORDER BY t.legal_name, ph.sort_order;


-- -----------------------------------------------------------------------------
-- 21. Última fecha de actualización por organización según sus plantillas
-- Clave: MAX(fecha). En PostgreSQL, ORDER BY ... DESC pone los NULL PRIMERO;
-- NULLS LAST los manda al final.
-- -----------------------------------------------------------------------------
SELECT t.id,
       t.legal_name,
       MAX(tt.updated_at) AS last_template_update
FROM tenants AS t
LEFT JOIN tenanttemplates AS tt ON tt.tenant_id = t.id
GROUP BY t.id, t.legal_name
ORDER BY last_template_update DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- 22. Organizaciones con documentos pendientes (vistas de resumen SST y PESV)
-- Clave: UNION ALL de las dos vistas, filtrando pending_documents > 0.
-- La columna fija 'SST' / 'PESV' indica de qué sistema viene cada fila.
-- -----------------------------------------------------------------------------
SELECT s.tenant_id,
       s.legal_name,
       'SST'               AS system_code,
       s.pending_documents
FROM vm_template_sst_docs_summary AS s
WHERE s.pending_documents > 0
UNION ALL
SELECT p.tenant_id,
       p.legal_name,
       'PESV'              AS system_code,
       p.pending_documents
FROM vm_template_pesv_docs_summary AS p
WHERE p.pending_documents > 0
ORDER BY legal_name, system_code;


-- -----------------------------------------------------------------------------
-- 23. Informe consolidado por organización
-- Clave: sumar las columnas de ambas vistas con UNION ALL + GROUP BY.
-- -----------------------------------------------------------------------------
SELECT u.tenant_id,
       u.legal_name,
       SUM(u.total_documents)       AS total_documents,
       SUM(u.finished_documents)    AS finished_documents,
       SUM(u.draft_documents)       AS draft_documents,
       SUM(u.not_started_documents) AS not_started_documents,
       SUM(u.pending_documents)     AS pending_documents,
       ROUND(100.0 * SUM(u.finished_documents) / NULLIF(SUM(u.total_documents), 0), 2) AS completion_pct
FROM (SELECT tenant_id, legal_name, total_documents, finished_documents,
             draft_documents, not_started_documents, pending_documents
      FROM vm_template_sst_docs_summary
      UNION ALL
      SELECT tenant_id, legal_name, total_documents, finished_documents,
             draft_documents, not_started_documents, pending_documents
      FROM vm_template_pesv_docs_summary) AS u
GROUP BY u.tenant_id, u.legal_name
ORDER BY u.legal_name;


-- -----------------------------------------------------------------------------
-- 24. Comparar cumplimiento SST vs PESV (diferencia mayor a un valor)
-- Clave: INNER JOIN entre las dos vistas por tenant_id; ABS() = valor absoluto.
-- Solo salen organizaciones que tienen documentos en AMBOS sistemas.
-- Cambia el 20 por el umbral que te pidan.
-- -----------------------------------------------------------------------------
SELECT s.tenant_id,
       s.legal_name,
       s.completion_pct                            AS sst_pct,
       p.completion_pct                            AS pesv_pct,
       ABS(s.completion_pct - p.completion_pct)    AS difference
FROM vm_template_sst_docs_summary AS s
INNER JOIN vm_template_pesv_docs_summary AS p ON p.tenant_id = s.tenant_id
WHERE ABS(s.completion_pct - p.completion_pct) > 20
ORDER BY difference DESC;


-- -----------------------------------------------------------------------------
-- 25. Vista que consolida personas, módulos, plantillas y sistemas por organización
-- Clave: CREATE VIEW guarda la CONSULTA (no los datos): al leerla se ejecuta
-- de nuevo. Se reutiliza la técnica de la 19: un CTE por cada conteo.
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_tenant_summary;
CREATE VIEW vw_tenant_summary AS
WITH persons_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_persons
    FROM persons
    GROUP BY tenant_id
),
modules_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_modules
    FROM tenant_modules
    WHERE is_active = true
    GROUP BY tenant_id
),
templates_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_templates
    FROM tenanttemplates
    WHERE is_active = true
    GROUP BY tenant_id
),
systems_per_tenant AS (
    SELECT tenant_id, COUNT(*) AS total_systems
    FROM tenantsystems
    WHERE is_active = true
    GROUP BY tenant_id
)
SELECT t.id        AS tenant_id,
       t.legal_name,
       COALESCE(p.total_persons, 0)    AS total_persons,
       COALESCE(m.total_modules, 0)    AS total_modules,
       COALESCE(tp.total_templates, 0) AS total_templates,
       COALESCE(s.total_systems, 0)    AS total_systems
FROM tenants AS t
LEFT JOIN persons_per_tenant   AS p  ON p.tenant_id  = t.id
LEFT JOIN modules_per_tenant   AS m  ON m.tenant_id  = t.id
LEFT JOIN templates_per_tenant AS tp ON tp.tenant_id = t.id
LEFT JOIN systems_per_tenant   AS s  ON s.tenant_id  = t.id;

-- Uso de la vista:
SELECT vts.tenant_id, vts.legal_name, vts.total_persons, vts.total_modules,
       vts.total_templates, vts.total_systems
FROM vw_tenant_summary AS vts
ORDER BY vts.legal_name;


-- =============================================================================
-- EXTRAS DE PRÁCTICA
-- =============================================================================

-- E1. Personas de organizaciones activas
-- Clave: IN con subconsulta (la subconsulta devuelve una lista de ids)
SELECT p.id, p.first_name, p.last_name
FROM persons AS p
WHERE p.tenant_id IN (SELECT t.id
                      FROM tenants AS t
                      WHERE t.is_active = true)
ORDER BY p.last_name;

-- E2. Documentos vigentes (última versión activa de cada asignación)
-- Clave: subconsulta CORRELACIONADA (usa una columna de la consulta externa).
-- Es el patrón que usan las vistas de resumen de 05_vistas.sql.
SELECT d.id, d.tenanttemplate_id, d.version, d.state
FROM documents AS d
WHERE d.is_active = true
  AND d.version = (SELECT MAX(d2.version)
                   FROM documents AS d2
                   WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                     AND d2.is_active = true)
ORDER BY d.tenanttemplate_id;
