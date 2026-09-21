-- =============================================================================
-- 05_vistas.sql — Vistas y vistas materializadas
--   Parte A: vistas materializadas de resumen documental (las que usan las
--            consultas 10–14 y 22–24 de 06_consultas_avanzadas.sql).
--   Parte B: sección 4 del examen (8 ejercicios).
-- Base: PostgreSQL. Requiere 01_schema.sql. EJECUTAR ANTES que
-- 06_consultas_avanzadas.sql.
--
-- Convención de nombres: vw_ = vista normal (guarda la consulta);
--                        vm_ = vista materializada (guarda también los datos).
-- Regla del proyecto: sin SELECT *; alias en cada tabla.
--
-- SUPUESTOS (el examen no los define; confírmalos con el profesor):
--   A. Las vistas vm_template_sst_docs_summary y vm_template_pesv_docs_summary
--      (que el examen nombra en la consulta avanzada 22 pero no describe)
--      tienen UNA fila por organización, con los documentos de las plantillas
--      de ese sistema (SST o PESV).
--   B. Por cada plantilla asignada solo cuenta la ÚLTIMA versión ACTIVA del
--      documento (supuesto S21 del modelo).
--   C. Pendientes = no_iniciado + borrador.
--      Cumplimiento (%) = finalizados / total de documentos * 100.
-- =============================================================================


-- =============================================================================
-- PARTE A — VISTAS MATERIALIZADAS DE RESUMEN DOCUMENTAL
--
-- Una vista materializada guarda el resultado en el disco, como una tabla.
-- NO se actualiza sola: después de cambiar documentos hay que ejecutar
-- REFRESH MATERIALIZED VIEW.
-- SUM(CASE WHEN ... THEN 1 ELSE 0 END) cuenta solo las filas que cumplen la
-- condición (agregación condicional). NULLIF(x, 0) evita dividir por cero.
-- =============================================================================

DROP MATERIALIZED VIEW IF EXISTS vm_template_sst_docs_summary;
CREATE MATERIALIZED VIEW vm_template_sst_docs_summary AS
SELECT t.id        AS tenant_id,
       t.legal_name,
       COUNT(d.id) AS total_documents,
       SUM(CASE WHEN d.state = 'finalizado'  THEN 1 ELSE 0 END) AS finished_documents,
       SUM(CASE WHEN d.state = 'borrador'    THEN 1 ELSE 0 END) AS draft_documents,
       SUM(CASE WHEN d.state = 'no_iniciado' THEN 1 ELSE 0 END) AS not_started_documents,
       SUM(CASE WHEN d.state IN ('no_iniciado', 'borrador') THEN 1 ELSE 0 END) AS pending_documents,
       ROUND(100.0 * SUM(CASE WHEN d.state = 'finalizado' THEN 1 ELSE 0 END)
             / NULLIF(COUNT(d.id), 0), 2) AS completion_pct
FROM tenants AS t
INNER JOIN tenanttemplates AS tt ON tt.tenant_id = t.id AND tt.is_active = true
INNER JOIN templates       AS tp ON tp.id = tt.template_id
INNER JOIN type_system_sst AS s  ON s.id = tp.type_system_sst_id AND s.code = 'SST'
INNER JOIN documents       AS d  ON d.tenanttemplate_id = tt.id
                                AND d.is_active = true
                                AND d.version = (SELECT MAX(d2.version)
                                                 FROM documents AS d2
                                                 WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                                                   AND d2.is_active = true)
GROUP BY t.id, t.legal_name;

DROP MATERIALIZED VIEW IF EXISTS vm_template_pesv_docs_summary;
CREATE MATERIALIZED VIEW vm_template_pesv_docs_summary AS
SELECT t.id        AS tenant_id,
       t.legal_name,
       COUNT(d.id) AS total_documents,
       SUM(CASE WHEN d.state = 'finalizado'  THEN 1 ELSE 0 END) AS finished_documents,
       SUM(CASE WHEN d.state = 'borrador'    THEN 1 ELSE 0 END) AS draft_documents,
       SUM(CASE WHEN d.state = 'no_iniciado' THEN 1 ELSE 0 END) AS not_started_documents,
       SUM(CASE WHEN d.state IN ('no_iniciado', 'borrador') THEN 1 ELSE 0 END) AS pending_documents,
       ROUND(100.0 * SUM(CASE WHEN d.state = 'finalizado' THEN 1 ELSE 0 END)
             / NULLIF(COUNT(d.id), 0), 2) AS completion_pct
FROM tenants AS t
INNER JOIN tenanttemplates AS tt ON tt.tenant_id = t.id AND tt.is_active = true
INNER JOIN templates       AS tp ON tp.id = tt.template_id
INNER JOIN type_system_sst AS s  ON s.id = tp.type_system_sst_id AND s.code = 'PESV'
INNER JOIN documents       AS d  ON d.tenanttemplate_id = tt.id
                                AND d.is_active = true
                                AND d.version = (SELECT MAX(d2.version)
                                                 FROM documents AS d2
                                                 WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                                                   AND d2.is_active = true)
GROUP BY t.id, t.legal_name;

-- Índice único por organización: acelera "WHERE tenant_id = ..." y es
-- OBLIGATORIO para poder usar REFRESH ... CONCURRENTLY (ver B7).
CREATE UNIQUE INDEX ux_vm_template_sst_docs_summary_tenant_id
    ON vm_template_sst_docs_summary (tenant_id);
CREATE UNIQUE INDEX ux_vm_template_pesv_docs_summary_tenant_id
    ON vm_template_pesv_docs_summary (tenant_id);

-- Después de cargar o cambiar documentos:
-- REFRESH MATERIALIZED VIEW vm_template_sst_docs_summary;
-- REFRESH MATERIALIZED VIEW vm_template_pesv_docs_summary;


-- =============================================================================
-- PARTE B — SECCIÓN 4 DEL EXAMEN
-- =============================================================================

-- -----------------------------------------------------------------------------
-- B1. vw_tenant_persons: organizaciones con sus personas y cargos
-- Clave: CREATE VIEW guarda la CONSULTA, no los datos; cada vez que la lees se
-- ejecuta de nuevo. LEFT JOIN para que no desaparezcan las organizaciones que
-- todavía no tienen personas.
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_tenant_persons;
CREATE VIEW vw_tenant_persons AS
SELECT t.id          AS tenant_id,
       t.legal_name  AS tenant_name,
       p.id          AS person_id,
       p.first_name,
       p.last_name,
       p.email       AS person_email,
       p.is_active   AS person_is_active,
       pos.id        AS position_id,
       pos.name      AS position_name
FROM tenants AS t
LEFT JOIN persons   AS p   ON p.tenant_id = t.id
LEFT JOIN positions AS pos ON pos.id = p.position_id;

-- Uso:
SELECT vtp.tenant_name, vtp.first_name, vtp.last_name, vtp.position_name
FROM vw_tenant_persons AS vtp
ORDER BY vtp.tenant_name, vtp.last_name;


-- -----------------------------------------------------------------------------
-- B2. Vista geográfica de las organizaciones (municipio, departamento, país)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_tenant_geography;
CREATE VIEW vw_tenant_geography AS
SELECT t.id     AS tenant_id,
       t.legal_name,
       c.name   AS city,
       d.name   AS department,
       co.name  AS country
FROM tenants AS t
INNER JOIN cities      AS c  ON c.id  = t.city_id
INNER JOIN departments AS d  ON d.id  = c.department_id
INNER JOIN countries   AS co ON co.id = d.country_id;

-- Uso:
SELECT vg.legal_name, vg.city, vg.department, vg.country
FROM vw_tenant_geography AS vg
ORDER BY vg.country, vg.department, vg.city;


-- -----------------------------------------------------------------------------
-- B3. Módulos habilitados por organización con su sistema SST
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_tenant_modules_system;
CREATE VIEW vw_tenant_modules_system AS
SELECT t.id         AS tenant_id,
       t.legal_name,
       m.id         AS module_id,
       m.title      AS module_title,
       s.code       AS system_code,
       s.name       AS system_name,
       tm.enabled_at
FROM tenant_modules AS tm
INNER JOIN tenants         AS t ON t.id = tm.tenant_id
INNER JOIN modules         AS m ON m.id = tm.module_id
INNER JOIN type_system_sst AS s ON s.id = m.type_system_sst_id
WHERE tm.is_active = true;

-- Uso:
SELECT vm.legal_name, vm.system_code, vm.module_title
FROM vw_tenant_modules_system AS vm
ORDER BY vm.legal_name, vm.system_code, vm.module_title;


-- -----------------------------------------------------------------------------
-- B4. Plantillas asociadas por organización y etapa PHVA
-- Clave: una vista puede contener GROUP BY y funciones agregadas.
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_tenant_templates_phva;
CREATE VIEW vw_tenant_templates_phva AS
SELECT t.id         AS tenant_id,
       t.legal_name,
       ph.code      AS phva_code,
       ph.name      AS phva_stage,
       ph.sort_order,
       COUNT(tt.id) AS total_templates
FROM tenanttemplates AS tt
INNER JOIN tenants     AS t  ON t.id  = tt.tenant_id
INNER JOIN templates   AS tp ON tp.id = tt.template_id
INNER JOIN phva_stages AS ph ON ph.id = tp.phva_stage_id
GROUP BY t.id, t.legal_name, ph.id, ph.code, ph.name, ph.sort_order;

-- Uso:
SELECT vp.legal_name, vp.phva_stage, vp.total_templates
FROM vw_tenant_templates_phva AS vp
ORDER BY vp.legal_name, vp.sort_order;


-- -----------------------------------------------------------------------------
-- B5. Total de personas por organización y cargo
-- Clave: LEFT JOIN desde positions para ver también los cargos sin personas.
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_tenant_position_persons;
CREATE VIEW vw_tenant_position_persons AS
SELECT t.id         AS tenant_id,
       t.legal_name,
       pos.id       AS position_id,
       pos.name     AS position_name,
       COUNT(p.id)  AS total_persons
FROM positions AS pos
INNER JOIN tenants AS t ON t.id = pos.tenant_id
LEFT JOIN  persons AS p ON p.position_id = pos.id
GROUP BY t.id, t.legal_name, pos.id, pos.name;

-- Uso:
SELECT vpp.legal_name, vpp.position_name, vpp.total_persons
FROM vw_tenant_position_persons AS vpp
ORDER BY vpp.legal_name, vpp.position_name;


-- -----------------------------------------------------------------------------
-- B6. Vista MATERIALIZADA de cumplimiento documental por organización
-- (total de documentos, finalizados, pendientes y porcentaje de cumplimiento)
-- Clave: a diferencia de las de la Parte A, esta suma TODOS los sistemas.
-- LEFT JOIN: las organizaciones sin documentos aparecen con total 0 y
-- porcentaje NULL (no se puede dividir entre 0).
-- -----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS vm_tenant_docs_compliance;
CREATE MATERIALIZED VIEW vm_tenant_docs_compliance AS
SELECT t.id        AS tenant_id,
       t.legal_name,
       COUNT(d.id) AS total_documents,
       SUM(CASE WHEN d.state = 'finalizado' THEN 1 ELSE 0 END) AS finished_documents,
       SUM(CASE WHEN d.state IN ('no_iniciado', 'borrador') THEN 1 ELSE 0 END) AS pending_documents,
       ROUND(100.0 * SUM(CASE WHEN d.state = 'finalizado' THEN 1 ELSE 0 END)
             / NULLIF(COUNT(d.id), 0), 2) AS completion_pct
FROM tenants AS t
LEFT JOIN tenanttemplates AS tt ON tt.tenant_id = t.id AND tt.is_active = true
LEFT JOIN documents       AS d  ON d.tenanttemplate_id = tt.id
                               AND d.is_active = true
                               AND d.version = (SELECT MAX(d2.version)
                                                FROM documents AS d2
                                                WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                                                  AND d2.is_active = true)
GROUP BY t.id, t.legal_name;

CREATE UNIQUE INDEX ux_vm_tenant_docs_compliance_tenant_id
    ON vm_tenant_docs_compliance (tenant_id);

-- Uso:
SELECT vc.tenant_id, vc.legal_name, vc.total_documents, vc.finished_documents,
       vc.pending_documents, vc.completion_pct
FROM vm_tenant_docs_compliance AS vc
ORDER BY vc.legal_name;


-- -----------------------------------------------------------------------------
-- B7. REFRESH MATERIALIZED VIEW y verificación de que refleja los cambios
-- Clave: la vista materializada NO cambia hasta que se hace REFRESH.
-- Todo el ejercicio va dentro de una transacción con ROLLBACK al final: se
-- puede repetir sin dejar cambios en tus datos (si quieres conservarlos,
-- cambia ROLLBACK por COMMIT). Ejecuta el bloque completo de una vez.
-- -----------------------------------------------------------------------------
BEGIN;

-- 1) Antes del cambio
SELECT vc.tenant_id, vc.legal_name, vc.total_documents, vc.finished_documents,
       vc.pending_documents, vc.completion_pct
FROM vm_tenant_docs_compliance AS vc
ORDER BY vc.tenant_id;

-- 2) Cambiamos un dato real: finalizamos un documento que estaba sin iniciar
--    (las restricciones del schema exigen fechas y contenido al finalizar)
UPDATE documents
SET state       = 'finalizado',
    started_at  = now(),
    finished_at = now(),
    content     = '{"nota": "demo de refresh"}'::jsonb
WHERE id = (SELECT MIN(d.id)
            FROM documents AS d
            WHERE d.state = 'no_iniciado');

-- 3) La vista materializada sigue igual (está desactualizada)
SELECT vc.tenant_id, vc.legal_name, vc.finished_documents, vc.completion_pct
FROM vm_tenant_docs_compliance AS vc
ORDER BY vc.tenant_id;

-- 4) Actualizamos la vista materializada
REFRESH MATERIALIZED VIEW vm_tenant_docs_compliance;

-- 5) Ahora sí refleja el cambio
SELECT vc.tenant_id, vc.legal_name, vc.finished_documents, vc.completion_pct
FROM vm_tenant_docs_compliance AS vc
ORDER BY vc.tenant_id;

ROLLBACK;

-- Variante sin bloquear las lecturas (requiere el índice único creado en B6):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY vm_tenant_docs_compliance;


-- -----------------------------------------------------------------------------
-- B8. ¿Qué columnas de la vista materializada deberían tener índice?
-- Contexto: el seguimiento por organización consulta cosas como
--   "el cumplimiento de la organización X"  y  "las organizaciones con pendientes".
--
--   1. tenant_id      -> SÍ (ya creado en B6). Es la columna por la que se busca
--                        y, además, es requisito de REFRESH ... CONCURRENTLY.
--   2. pending_documents -> OPCIONAL. Solo ayudaría un índice PARCIAL si casi
--                        todas las organizaciones estuvieran al día y se
--                        consultaran las pocas con pendientes.
--   3. completion_pct -> OPCIONAL. Solo si se hacen rankings o filtros
--                        (< 40 %) sobre miles de organizaciones.
--   4. legal_name, total_documents, finished_documents -> NO. Se leen, pero
--                        casi nunca se filtra por ellas.
--
-- Cada índice extra hace más lento el REFRESH y ocupa espacio; por eso solo
-- se crean los que un EXPLAIN demuestre que hacen falta. Ejemplos opcionales:
-- -----------------------------------------------------------------------------
-- CREATE INDEX ix_vm_tenant_docs_compliance_pending
--     ON vm_tenant_docs_compliance (pending_documents)
--     WHERE pending_documents > 0;
--
-- CREATE INDEX ix_vm_tenant_docs_compliance_pct
--     ON vm_tenant_docs_compliance (completion_pct);

-- Para comprobar si el índice se usa (con pocos datos PostgreSQL puede preferir
-- leer la tabla completa; con miles de filas usaría el índice):
EXPLAIN ANALYZE
SELECT vc.tenant_id, vc.completion_pct
FROM vm_tenant_docs_compliance AS vc
WHERE vc.tenant_id = 1;


-- =============================================================================
-- Ayudas para revisar lo creado
-- =============================================================================
SELECT v.viewname
FROM pg_views AS v
WHERE v.schemaname = 'public'
ORDER BY v.viewname;

SELECT mv.matviewname, mv.ispopulated
FROM pg_matviews AS mv
WHERE mv.schemaname = 'public'
ORDER BY mv.matviewname;
