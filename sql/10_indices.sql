-- =============================================================================
-- 10_indices.sql — Diseño de índices (objetivo específico 12 del examen)
-- Base: PostgreSQL. Requiere 01_schema.sql. Ejecutar DESPUÉS de cargar los
-- datos (02a/02b) y de probar las consultas, para poder medir el efecto.
--
-- IDEA GENERAL
--   Un índice es como el índice de un libro: PostgreSQL encuentra las filas
--   sin leer la tabla entera. A cambio, ocupa espacio y hace un poco más lentos
--   los INSERT / UPDATE / DELETE, porque hay que mantenerlo al día.
--   => Solo se crean los que un análisis (EXPLAIN) justifica.
--
-- QUÉ CREA POSTGRESQL SOLO
--   * PRIMARY KEY y UNIQUE  -> crean un índice automáticamente.
--   * FOREIGN KEY           -> NO crea índice en la columna que referencia.
--     Ese índice es útil para los JOIN y para que borrar o cambiar una fila
--     "padre" no obligue a leer toda la tabla "hija" (por eso la sección 1
--     busca las FK sin índice).
--   Regla práctica: un índice compuesto (a, b) sirve para buscar por "a" y por
--   "a y b", pero NO para buscar solo por "b". Por eso en este proyecto casi
--   todo empieza por tenant_id (multi-tenant) y ya está cubierto por los UNIQUE.
--
-- ÍNDICES QUE YA EXISTEN (los crean las restricciones del schema, no se repiten):
--   persons(tenant_id, document_type, document_number), positions(tenant_id, name),
--   tenant_modules(tenant_id, module_id), tenantsystems(tenant_id, type_system_sst_id),
--   tenanttemplates(tenant_id, template_id), documents(tenanttemplate_id, version),
--   modules(type_system_sst_id, code), templates(type_system_sst_id, code, version),
--   formats_sst(template_id, code, version), cities(department_id, ...),
--   departments(country_id, ...), y los de la vista materializada (05_vistas.sql).
-- =============================================================================


-- =============================================================================
-- 1. INVENTARIO: claves foráneas SIN índice de apoyo
-- Cuenta como apoyo un índice (no parcial) cuyas primeras columnas sean las de
-- la FK. Es la lista de candidatos; la sección 2 decide cuáles valen la pena.
-- =============================================================================
SELECT c.conrelid::regclass AS table_name,
       c.conname            AS fk_name,
       (SELECT string_agg(a.attname, ', ' ORDER BY k.ord)
        FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
        INNER JOIN pg_attribute AS a ON a.attrelid = c.conrelid
                                    AND a.attnum = k.attnum) AS fk_columns
FROM pg_constraint AS c
WHERE c.contype = 'f'
  AND NOT EXISTS (SELECT 1
                  FROM pg_index AS i
                  WHERE i.indrelid = c.conrelid
                    AND i.indisvalid
                    AND i.indpred IS NULL
                    AND (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey
                    AND c.conkey @> (i.indkey::int2[])[0:cardinality(c.conkey) - 1])
ORDER BY 1, 2;


-- =============================================================================
-- 2. ÍNDICES PROPUESTOS (cada uno con la consulta o el proceso al que sirve)
-- CREATE INDEX IF NOT EXISTS permite volver a ejecutar el archivo sin error.
-- Nombre: ix_<tabla>_<columnas>.
-- =============================================================================

-- 2.1 tenants(city_id)  [FK sin índice]
-- Sirve a: JOIN tenants -> cities (consultas intermedias 4 y 19, vw_tenant_geography).
CREATE INDEX IF NOT EXISTS ix_tenants_city_id
    ON tenants (city_id);

-- 2.2 tenants(tenant_size_id)  [FK sin índice]
-- Sirve a: JOIN con tenant_sizes (intermedia 3, avanzada 16).
CREATE INDEX IF NOT EXISTS ix_tenants_tenant_size_id
    ON tenants (tenant_size_id);

-- 2.3 tenants(created_at)
-- Sirve a: consultas por período (básica 12). Un B-tree acelera rangos (>=, <).
CREATE INDEX IF NOT EXISTS ix_tenants_created_at
    ON tenants (created_at);

-- 2.4 persons(position_id, tenant_id)  [FK compuesta sin índice]
-- Sirve a: JOIN persons -> positions y conteo de personas por cargo
-- (intermedia 20, avanzada 17, vw_tenant_position_persons, procedimientos 7 y 8).
CREATE INDEX IF NOT EXISTS ix_persons_position_tenant
    ON persons (position_id, tenant_id);

-- 2.5 tenant_modules(module_id)  [FK sin índice]
-- El UNIQUE existente empieza por tenant_id, así que buscar por módulo NO lo usa.
-- Sirve a: "módulos sin asignar" (intermedia 17), trigger 10 (antes de borrar
-- un módulo consulta quién lo tiene) y el procedimiento 10.
CREATE INDEX IF NOT EXISTS ix_tenant_modules_module_id
    ON tenant_modules (module_id);

-- 2.6 tenantsystems(type_system_sst_id)  [FK sin índice]
-- Sirve a: trigger 9 (antes de borrar un sistema consulta quién lo usa) y a los
-- JOIN por sistema (intermedia 9).
CREATE INDEX IF NOT EXISTS ix_tenantsystems_type_system_sst_id
    ON tenantsystems (type_system_sst_id);

-- 2.7 templates(phva_stage_id)  [FK sin índice]
-- Sirve a: todo lo que agrupa o filtra por etapa PHVA (intermedia 18, avanzadas
-- 5–9 y 20, procedimiento 13, función 5).
CREATE INDEX IF NOT EXISTS ix_templates_phva_stage_id
    ON templates (phva_stage_id);

-- 2.8 formats_sst(module_id)  [FK sin índice]
-- Sirve a: intermedias 11 y 12 (formatos por módulo) y procedimiento 10.
CREATE INDEX IF NOT EXISTS ix_formats_sst_module_id
    ON formats_sst (module_id);

-- 2.9 tenanttemplates(template_id)  [FK sin índice]
-- El UNIQUE existente empieza por tenant_id; buscar "quién tiene esta plantilla"
-- o unir con templates por esta columna necesita su propio índice.
CREATE INDEX IF NOT EXISTS ix_tenanttemplates_template_id
    ON tenanttemplates (template_id);

-- 2.10 editing_locks(expires_at) PARCIAL: solo bloqueos sin liberar
-- Sirve a: trigger 15, que en CADA INSERT busca los bloqueos vencidos
-- (released_at IS NULL AND expires_at < now()). El índice parcial solo guarda
-- los pocos bloqueos vigentes, así que es pequeño y muy rápido.
CREATE INDEX IF NOT EXISTS ix_editing_locks_open_expires_at
    ON editing_locks (expires_at)
    WHERE released_at IS NULL;

-- 2.11 audit_log(tenant_id, changed_at DESC)  [también cubre la FK tenant_id]
-- Sirve a: "últimos cambios de una organización" (WHERE tenant_id = ... ORDER BY
-- changed_at DESC). Las filas ya salen en orden, sin ordenar aparte.
CREATE INDEX IF NOT EXISTS ix_audit_log_tenant_changed_at
    ON audit_log (tenant_id, changed_at DESC);

-- 2.12 audit_log(table_name, record_pk)
-- Sirve a: "historial de una fila concreta" (WHERE table_name = 'tenants'
-- AND record_pk = '1').
CREATE INDEX IF NOT EXISTS ix_audit_log_table_record
    ON audit_log (table_name, record_pk);

-- 2.13 documents(content) con GIN  [modelo híbrido JSONB]
-- Un B-tree no sirve para "buscar dentro de un JSON". GIN indexa las claves y
-- valores del JSONB y acelera @> (contiene), ? (existe la clave), ?| y ?&.
-- Sirve a: las consultas JSONB (11_consultas_jsonb.sql).
-- (jsonb_path_ops es más pequeño y rápido pero solo soporta @>.)
CREATE INDEX IF NOT EXISTS ix_documents_content_gin
    ON documents USING gin (content);


-- =============================================================================
-- 3. CANDIDATOS DESCARTADOS (y por qué): saber decir "no" también es diseño
--
--  * evaluations(template_id), evaluations(evaluator_person_id, tenant_id),
--    tenanttemplates(responsible_person_id, tenant_id),
--    tenanttemplates(assigned_by_person_id, tenant_id),
--    editing_locks(locked_by_person_id), editing_locks(document_id):
--    solo se consultarían al borrar o trasladar una PERSONA o un DOCUMENTO, algo
--    poco frecuente. Cada índice extra cuesta en cada escritura. Se
--    reconsideran si el volumen crece o el traslado de personas se vuelve común.
--
--  * documents(state) o un índice parcial de "pendientes"
--    (WHERE state IN ('no_iniciado','borrador')):
--    con la distribución de datos de prueba (~65 % de los documentos están
--    pendientes) casi la mayoría de las filas entraría al índice: PostgreSQL
--    seguiría prefiriendo leer la tabla. Un índice parcial solo rinde cuando
--    la condición selecciona una MINORÍA de filas.
--    Además, se llega a los documentos por tenanttemplate_id, que ya está
--    cubierto por UNIQUE (tenanttemplate_id, version).
--
--  * persons(tenant_id) o positions(tenant_id): ya son la primera columna de un
--    UNIQUE. Duplicarlos solo gastaría espacio.
--
--  * tenants(legal_name) para "nombre contiene una palabra" (ILIKE '%palabra%'):
--    un B-tree no ayuda cuando el comodín está AL PRINCIPIO. Haría falta la
--    extensión pg_trgm (índice GIN de trigramas). Se deja como mejora opcional:
--      -- CREATE EXTENSION IF NOT EXISTS pg_trgm;
--      -- CREATE INDEX ix_tenants_legal_name_trgm
--      --     ON tenants USING gin (legal_name gin_trgm_ops);
--
--  * Índices sobre columnas booleanas como is_active: tienen solo 2 valores,
--    casi nunca ayudan.
-- =============================================================================


-- =============================================================================
-- 4. LABORATORIO: medir el efecto de un índice con EXPLAIN ANALYZE
-- Con pocos datos, PostgreSQL lee la tabla completa aunque exista el índice
-- (es más barato). Para ver la diferencia hace falta volumen, así que este
-- bloque crea una tabla TEMPORAL con 300 000 filas (no toca tus tablas y
-- desaparece al cerrar la sesión). Ejecútalo COMPLETO de una sola vez.
--
-- Cómo leer el resultado de EXPLAIN:
--   Seq Scan          = lee TODA la tabla (lento con muchas filas).
--   Index Scan /
--   Bitmap Index Scan = usa el índice.
--   "Execution Time"  = tiempo real en milisegundos.
-- =============================================================================
CREATE TEMP TABLE lab_persons AS
SELECT g                       AS id,
       (g % 500) + 1           AS tenant_id,      -- 500 organizaciones
       (g % 10 <> 0)           AS is_active,
       DATE '2019-01-01' + (g % 2500) AS hire_date
FROM generate_series(1, 300000) AS g;

ANALYZE lab_persons;

-- ANTES (sin índice): esperado -> Seq Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.id, l.hire_date
FROM lab_persons AS l
WHERE l.tenant_id = 42;

CREATE INDEX ix_lab_persons_tenant_id ON lab_persons (tenant_id);
ANALYZE lab_persons;

-- DESPUÉS (con índice): esperado -> Bitmap Index Scan o Index Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.id, l.hire_date
FROM lab_persons AS l
WHERE l.tenant_id = 42;

DROP TABLE lab_persons;


-- =============================================================================
-- 5. ¿SE USAN LOS ÍNDICES? Índices sin uso (candidatos a eliminar)
-- idx_scan = cuántas veces PostgreSQL usó el índice desde que se reiniciaron las
-- estadísticas. Se excluyen los UNIQUE y PK, porque sirven de restricción
-- aunque nunca se lean. Ejecútalo DESPUÉS de correr varias consultas reales.
-- Si un índice tiene idx_scan = 0 tras un uso normal, se elimina:
--   DROP INDEX nombre_del_indice;
-- =============================================================================
SELECT s.relname      AS table_name,
       s.indexrelname AS index_name,
       s.idx_scan     AS times_used,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size
FROM pg_stat_user_indexes AS s
INNER JOIN pg_index AS i ON i.indexrelid = s.indexrelid
WHERE NOT i.indisunique
ORDER BY s.idx_scan, pg_relation_size(s.indexrelid) DESC;


-- =============================================================================
-- 6. MANTENIMIENTO
-- Tras cargar muchos datos, actualiza las estadísticas para que el planificador
-- elija bien (y, si quieres, compacta con VACUUM):
-- =============================================================================
ANALYZE;
