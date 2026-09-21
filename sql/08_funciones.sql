-- =============================================================================
-- 08_funciones.sql — Funciones almacenadas (sección 6 del examen)
-- Base: PostgreSQL / PL/pgSQL. Requiere 01_schema.sql.
--
-- Convenciones (las de tu guía): fn_ = función, p_ = parámetro, v_ = variable.
-- Nombres en inglés para coincidir con el schema.
-- Regla del proyecto: sin SELECT *; alias en cada tabla; columnas calificadas.
--
-- FUNCIÓN vs PROCEDIMIENTO (pregunta típica del profesor)
--   * Función:       CREATE FUNCTION ... RETURNS tipo; se usa con SELECT y
--                    DEVUELVE un valor (o una tabla). Puede ir dentro de una
--                    consulta:  SELECT fn_algo(t.id) FROM tenants AS t;
--   * Procedimiento: CREATE PROCEDURE; se usa con CALL; representa una
--                    operación (insertar, actualizar) y puede hacer COMMIT.
--
-- ESTRUCTURA (la de tu guía)
--   CREATE OR REPLACE FUNCTION fn_nombre(p_parametro tipo)
--   RETURNS tipo_de_retorno AS $$
--   DECLARE   v_variable tipo;         -- opcional
--   BEGIN
--       ...lógica...
--       RETURN valor;
--   END;
--   $$ LANGUAGE plpgsql STABLE;
--   (STABLE = promete que la función solo lee datos y no los modifica; es
--    opcional, pero ayuda al optimizador.)
--
-- CUIDADO CON RETURNS TABLE: las columnas de salida se comportan como
-- VARIABLES dentro de la función. Si una columna de salida se llama igual que
-- una columna de la tabla (por ejemplo "id"), un SELECT id sin alias da el error
-- "column reference is ambiguous". Solución: calificar SIEMPRE con alias de
-- tabla (p.id) y usar nombres de salida distintos (person_id).
--
-- DECISIONES (confírmalas con el profesor): las funciones son "tolerantes":
-- si la organización o la persona no existe, devuelven 0, false o NULL en vez de
-- lanzar un error, para poder usarlas dentro de un SELECT sobre muchas filas.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Cantidad total de personas de una organización
-- Clave: SELECT COUNT(*) INTO variable; RETURN variable.
-- Ejemplo: SELECT fn_count_tenant_persons(1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_count_tenant_persons(p_tenant_id bigint)
RETURNS integer AS $$
DECLARE
    v_total integer;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM persons AS p
    WHERE p.tenant_id = p_tenant_id;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 2. Porcentaje de cumplimiento documental de una organización
-- Clave: finalizados / total * 100, contando solo la última versión activa de
-- cada documento. NULLIF evita dividir por cero: sin documentos devuelve NULL.
-- Ejemplo: SELECT fn_tenant_compliance_pct(1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tenant_compliance_pct(p_tenant_id bigint)
RETURNS numeric AS $$
DECLARE
    v_pct numeric;
BEGIN
    SELECT ROUND(100.0 * SUM(CASE WHEN d.state = 'finalizado' THEN 1 ELSE 0 END)
                 / NULLIF(COUNT(d.id), 0), 2)
    INTO v_pct
    FROM tenanttemplates AS tt
    INNER JOIN documents AS d ON d.tenanttemplate_id = tt.id
                             AND d.is_active = true
                             AND d.version = (SELECT MAX(d2.version)
                                              FROM documents AS d2
                                              WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                                                AND d2.is_active = true)
    WHERE tt.tenant_id = p_tenant_id
      AND tt.is_active = true;

    RETURN v_pct;
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 3. ¿La organización tiene habilitado un módulo? (devuelve boolean)
-- Clave: RETURN EXISTS (subconsulta) devuelve true/false directamente.
-- Ejemplo: SELECT fn_tenant_has_module(1, 2);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tenant_has_module(p_tenant_id bigint, p_module_id bigint)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (SELECT 1
                   FROM tenant_modules AS tm
                   WHERE tm.tenant_id = p_tenant_id
                     AND tm.module_id = p_module_id
                     AND tm.is_active = true);
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 4. Nombre completo de una persona
-- Clave: || une textos. Si la persona no existe, devuelve NULL.
-- Ejemplo: SELECT fn_person_full_name(1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_person_full_name(p_person_id bigint)
RETURNS text AS $$
DECLARE
    v_full_name text;
BEGIN
    SELECT p.first_name || ' ' || p.last_name INTO v_full_name
    FROM persons AS p
    WHERE p.id = p_person_id;

    RETURN v_full_name;
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 5. Cantidad de plantillas de una organización en una etapa PHVA
-- Clave: dos parámetros; el JOIN llega a la etapa a través de templates.
-- Ejemplo: SELECT fn_count_templates_by_phva(1, 1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_count_templates_by_phva(p_tenant_id bigint, p_phva_stage_id bigint)
RETURNS integer AS $$
DECLARE
    v_total integer;
BEGIN
    SELECT COUNT(tt.id) INTO v_total
    FROM tenanttemplates AS tt
    INNER JOIN templates AS tp ON tp.id = tt.template_id
    WHERE tt.tenant_id = p_tenant_id
      AND tt.is_active = true
      AND tp.phva_stage_id = p_phva_stage_id;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 6. FUNCIÓN TABULAR: módulos habilitados de una organización
-- Clave: RETURNS TABLE(...) + RETURN QUERY SELECT ...  Se consulta como si fuera
-- una tabla:  SELECT ... FROM fn_tenant_enabled_modules(1) AS f;
-- Los nombres de salida (module_id, module_title...) son distintos a los de las
-- tablas y las columnas van calificadas (evita el error de ambigüedad).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tenant_enabled_modules(p_tenant_id bigint)
RETURNS TABLE (
    module_id    bigint,
    module_title varchar,
    system_code  varchar,
    enabled_at   timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id,
           m.title,
           s.code,
           tm.enabled_at
    FROM tenant_modules AS tm
    INNER JOIN modules         AS m ON m.id = tm.module_id
    INNER JOIN type_system_sst AS s ON s.id = m.type_system_sst_id
    WHERE tm.tenant_id = p_tenant_id
      AND tm.is_active = true
    ORDER BY s.code, m.sort_order;
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 7. FUNCIÓN TABULAR: personas de una organización con su cargo
-- Ejemplo: SELECT f.full_name, f.position_name FROM fn_tenant_persons_positions(1) AS f;
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tenant_persons_positions(p_tenant_id bigint)
RETURNS TABLE (
    person_id        bigint,
    full_name        text,
    position_name    varchar,
    person_is_active boolean
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.id,
           p.first_name || ' ' || p.last_name,
           pos.name,
           p.is_active
    FROM persons AS p
    INNER JOIN positions AS pos ON pos.id = p.position_id
    WHERE p.tenant_id = p_tenant_id
    ORDER BY p.last_name, p.first_name;
END;
$$ LANGUAGE plpgsql STABLE;


-- -----------------------------------------------------------------------------
-- 8. Clasificar el nivel de cumplimiento: Bajo / Medio / Alto
-- Clave: una función puede LLAMAR a otra (usa la función 2) y clasificar con
-- IF / ELSIF. Umbrales adoptados (igual que la consulta avanzada 12):
-- Bajo < 40, Medio 40–69, Alto >= 70. Sin documentos: 'Sin documentos'.
-- Ejemplo: SELECT fn_compliance_level(1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_compliance_level(p_tenant_id bigint)
RETURNS text AS $$
DECLARE
    v_pct numeric;
BEGIN
    v_pct := fn_tenant_compliance_pct(p_tenant_id);

    IF v_pct IS NULL THEN
        RETURN 'Sin documentos';
    ELSIF v_pct < 40 THEN
        RETURN 'Bajo';
    ELSIF v_pct < 70 THEN
        RETURN 'Medio';
    ELSE
        RETURN 'Alto';
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;


-- =============================================================================
-- EXTRAS DE USO (esto es lo que distingue a una función de un procedimiento)
-- =============================================================================

-- E1. Una función se puede usar DENTRO de un SELECT, fila por fila
SELECT t.id,
       t.legal_name,
       fn_count_tenant_persons(t.id)   AS total_persons,
       fn_tenant_compliance_pct(t.id)  AS compliance_pct,
       fn_compliance_level(t.id)       AS compliance_level
FROM tenants AS t
ORDER BY t.legal_name;

-- E2. Una función tabular se puede unir con otra tabla usando CROSS JOIN LATERAL
-- (LATERAL permite que la función use el t.id de la fila actual de tenants)
SELECT t.legal_name,
       f.module_title,
       f.system_code
FROM tenants AS t
CROSS JOIN LATERAL fn_tenant_enabled_modules(t.id) AS f
ORDER BY t.legal_name, f.system_code, f.module_title;


-- =============================================================================
-- Documentación de las funciones (COMMENT ON, visible en pgAdmin)
-- =============================================================================
COMMENT ON FUNCTION fn_count_tenant_persons IS 'Cantidad total de personas de una organización.';
COMMENT ON FUNCTION fn_tenant_compliance_pct IS 'Porcentaje de cumplimiento documental (última versión activa); NULL si no hay documentos.';
COMMENT ON FUNCTION fn_tenant_has_module IS 'true si la organización tiene habilitado el módulo indicado.';
COMMENT ON FUNCTION fn_person_full_name IS 'Nombre completo (nombre y apellido) de una persona; NULL si no existe.';
COMMENT ON FUNCTION fn_count_templates_by_phva IS 'Cantidad de plantillas activas de una organización en una etapa PHVA.';
COMMENT ON FUNCTION fn_tenant_enabled_modules IS 'Tabla de módulos habilitados de una organización con su sistema.';
COMMENT ON FUNCTION fn_tenant_persons_positions IS 'Tabla de personas de una organización con su cargo.';
COMMENT ON FUNCTION fn_compliance_level IS 'Clasifica el cumplimiento como Bajo, Medio, Alto o Sin documentos.';
