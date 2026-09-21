-- =============================================================================
-- 09_triggers.sql — Triggers (sección 7 del examen)
-- Base: PostgreSQL / PL/pgSQL. Requiere 01_schema.sql.
-- Recomendado: cargar los datos (02a/02b) ANTES de crear los triggers, para que
-- la carga masiva no genere filas de auditoría ni bloqueos innecesarios.
--
-- ¿QUÉ ES UN TRIGGER?  Son DOS piezas:
--   1. Una FUNCIÓN que "devuelve trigger" (la lógica).
--   2. Un CREATE TRIGGER que la conecta a una tabla y a un evento.
--
--   CREATE OR REPLACE FUNCTION fn_trg_algo()
--   RETURNS trigger AS $$
--   BEGIN
--       ...lógica usando NEW / OLD...
--       RETURN NEW;
--   END;
--   $$ LANGUAGE plpgsql;
--
--   CREATE TRIGGER trg_tabla_algo
--   BEFORE UPDATE ON tabla            -- momento (BEFORE/AFTER) y evento
--   FOR EACH ROW                      -- una vez por fila (o FOR EACH STATEMENT)
--   EXECUTE FUNCTION fn_trg_algo();
--
-- VARIABLES ESPECIALES DENTRO DE LA FUNCIÓN
--   NEW = la fila NUEVA (INSERT y UPDATE)       OLD = la fila ANTERIOR (UPDATE y DELETE)
--   TG_OP = 'INSERT' | 'UPDATE' | 'DELETE'
--
-- BEFORE vs AFTER
--   BEFORE: corre antes de guardar. Puede MODIFICAR NEW (ej. updated_at) o
--           CANCELAR con RAISE EXCEPTION. Debe terminar con RETURN NEW
--           (en DELETE: RETURN OLD). Devolver NULL cancela la fila en silencio.
--   AFTER:  corre cuando la fila ya se guardó. Sirve para auditoría. Su valor
--           de retorno se ignora (se acostumbra RETURN NULL).
--
-- DECISIONES (confírmalas con el profesor):
--   * Varios triggers repiten reglas que el schema ya garantiza (UNIQUE, FK,
--     CHECK). El examen los pide igual, y el trigger da un mensaje de error
--     claro (el error del schema es más técnico).
--   * Trigger 11: el porcentaje 0–100 se valida en evaluations (score/max_score).
--   * Trigger 12 audita los cambios de datos de la organización (contacto,
--     nombre, ciudad...) y el 13 los de estado (is_active): así un mismo UPDATE
--     no genera dos filas de auditoría.
--   * Trigger 14: "plantilla" = la tabla templates (catálogo). El 7 cubre
--     tenanttemplates (plantillas ASIGNADAS).
-- =============================================================================


-- =============================================================================
-- 1, 2 y 7. updated_at automático (tenants, persons, tenanttemplates)
-- Clave: UNA sola función reutilizable y un trigger por tabla. BEFORE UPDATE
-- porque cambia NEW antes de guardar la fila.
-- Prueba: UPDATE tenants SET phone = '6070000000' WHERE id = 1;  -> updated_at cambia.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1. tenants
DROP TRIGGER IF EXISTS trg_tenants_set_updated_at ON tenants;
CREATE TRIGGER trg_tenants_set_updated_at
BEFORE UPDATE ON tenants
FOR EACH ROW
EXECUTE FUNCTION fn_trg_set_updated_at();

-- 2. persons
DROP TRIGGER IF EXISTS trg_persons_set_updated_at ON persons;
CREATE TRIGGER trg_persons_set_updated_at
BEFORE UPDATE ON persons
FOR EACH ROW
EXECUTE FUNCTION fn_trg_set_updated_at();

-- 7. tenanttemplates (plantillas asignadas a una organización)
DROP TRIGGER IF EXISTS trg_tenanttemplates_set_updated_at ON tenanttemplates;
CREATE TRIGGER trg_tenanttemplates_set_updated_at
BEFORE UPDATE ON tenanttemplates
FOR EACH ROW
EXECUTE FUNCTION fn_trg_set_updated_at();


-- =============================================================================
-- 3. Impedir registrar una persona en una organización inactiva
-- Clave: BEFORE INSERT OR UPDATE OF tenant_id. "UPDATE OF columna" dispara el
-- trigger solo si esa columna aparece en el UPDATE (así editar el teléfono de
-- una persona antigua no se bloquea si su organización luego se inactivó).
-- Prueba: INSERT INTO persons (...) con tenant_id de una organización inactiva.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_person_tenant_active()
RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM tenants AS t
                   WHERE t.id = NEW.tenant_id
                     AND t.is_active = true) THEN
        RAISE EXCEPTION 'No se puede registrar la persona: la organización % está inactiva o no existe',
                        NEW.tenant_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_persons_tenant_active ON persons;
CREATE TRIGGER trg_persons_tenant_active
BEFORE INSERT OR UPDATE OF tenant_id ON persons
FOR EACH ROW
EXECUTE FUNCTION fn_trg_person_tenant_active();


-- =============================================================================
-- 4. Impedir asignar un módulo ya asignado a la organización
-- Clave: BEFORE INSERT + EXISTS. (El UNIQUE del schema ya lo impide; el trigger
-- da un mensaje entendible.)
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_module_not_assigned()
RETURNS trigger AS $$
BEGIN
    IF EXISTS (SELECT 1
               FROM tenant_modules AS tm
               WHERE tm.tenant_id = NEW.tenant_id
                 AND tm.module_id = NEW.module_id) THEN
        RAISE EXCEPTION 'El módulo % ya está asignado a la organización %',
                        NEW.module_id, NEW.tenant_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenant_modules_not_assigned ON tenant_modules;
CREATE TRIGGER trg_tenant_modules_not_assigned
BEFORE INSERT ON tenant_modules
FOR EACH ROW
EXECUTE FUNCTION fn_trg_module_not_assigned();


-- =============================================================================
-- 5. Impedir asignar plantillas a organizaciones inactivas
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_template_tenant_active()
RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM tenants AS t
                   WHERE t.id = NEW.tenant_id
                     AND t.is_active = true) THEN
        RAISE EXCEPTION 'No se puede asignar la plantilla: la organización % está inactiva o no existe',
                        NEW.tenant_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenanttemplates_tenant_active ON tenanttemplates;
CREATE TRIGGER trg_tenanttemplates_tenant_active
BEFORE INSERT OR UPDATE OF tenant_id ON tenanttemplates
FOR EACH ROW
EXECUTE FUNCTION fn_trg_template_tenant_active();


-- =============================================================================
-- 6. El cargo de una persona debe pertenecer a SU organización
-- Clave: compara el tenant_id del cargo con el de la persona (NEW.tenant_id).
-- (La FK compuesta del schema ya lo garantiza; el trigger da un mensaje claro.)
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_person_position_same_tenant()
RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM positions AS pos
                   WHERE pos.id = NEW.position_id
                     AND pos.tenant_id = NEW.tenant_id) THEN
        RAISE EXCEPTION 'El cargo % no pertenece a la organización % de la persona',
                        NEW.position_id, NEW.tenant_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_persons_position_same_tenant ON persons;
CREATE TRIGGER trg_persons_position_same_tenant
BEFORE INSERT OR UPDATE OF position_id, tenant_id ON persons
FOR EACH ROW
EXECUTE FUNCTION fn_trg_person_position_same_tenant();


-- =============================================================================
-- 8. Impedir eliminar una organización con personas asociadas
-- Clave: BEFORE DELETE usa OLD (la fila que se va a borrar) y termina con
-- RETURN OLD. Al lanzar el error, el DELETE completo se cancela.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_prevent_tenant_delete()
RETURNS trigger AS $$
DECLARE
    v_persons integer;
BEGIN
    SELECT COUNT(*) INTO v_persons
    FROM persons AS p
    WHERE p.tenant_id = OLD.id;

    IF v_persons > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar la organización %: tiene % personas asociadas',
                        OLD.id, v_persons;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenants_prevent_delete ON tenants;
CREATE TRIGGER trg_tenants_prevent_delete
BEFORE DELETE ON tenants
FOR EACH ROW
EXECUTE FUNCTION fn_trg_prevent_tenant_delete();


-- =============================================================================
-- 9. Impedir eliminar un sistema SST que usan organizaciones
-- Nota: cuenta las organizaciones que lo tienen ACTIVO. Si solo quedan
-- habilitaciones inactivas, la FK del schema igual bloquea el borrado.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_prevent_system_delete()
RETURNS trigger AS $$
DECLARE
    v_tenants integer;
BEGIN
    SELECT COUNT(*) INTO v_tenants
    FROM tenantsystems AS ts
    WHERE ts.type_system_sst_id = OLD.id
      AND ts.is_active = true;

    IF v_tenants > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar el sistema %: lo utilizan % organizaciones',
                        OLD.id, v_tenants;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_type_system_sst_prevent_delete ON type_system_sst;
CREATE TRIGGER trg_type_system_sst_prevent_delete
BEFORE DELETE ON type_system_sst
FOR EACH ROW
EXECUTE FUNCTION fn_trg_prevent_system_delete();


-- =============================================================================
-- 10. Impedir eliminar un módulo asignado a una o más organizaciones
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_prevent_module_delete()
RETURNS trigger AS $$
DECLARE
    v_tenants integer;
BEGIN
    SELECT COUNT(*) INTO v_tenants
    FROM tenant_modules AS tm
    WHERE tm.module_id = OLD.id
      AND tm.is_active = true;

    IF v_tenants > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar el módulo %: está asignado a % organizaciones',
                        OLD.id, v_tenants;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_modules_prevent_delete ON modules;
CREATE TRIGGER trg_modules_prevent_delete
BEFORE DELETE ON modules
FOR EACH ROW
EXECUTE FUNCTION fn_trg_prevent_module_delete();


-- =============================================================================
-- 11. El porcentaje de cumplimiento debe estar entre 0 y 100
-- Clave: el porcentaje de una evaluación es score / max_score * 100. Se valida
-- ANTES de guardar. Si max_score fuera 0, la división fallaría, así que se
-- comprueba primero.
-- Prueba: INSERT en evaluations con score = 120 y max_score = 100 -> error.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_evaluation_pct_range()
RETURNS trigger AS $$
DECLARE
    v_pct numeric;
BEGIN
    IF NEW.score IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.max_score IS NULL OR NEW.max_score <= 0 THEN
        RAISE EXCEPTION 'El puntaje máximo debe ser mayor que 0';
    END IF;

    v_pct := 100.0 * NEW.score / NEW.max_score;

    IF v_pct < 0 OR v_pct > 100 THEN
        RAISE EXCEPTION 'El porcentaje de cumplimiento calculado (% %%) debe estar entre 0 y 100',
                        ROUND(v_pct, 2);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_evaluations_pct_range ON evaluations;
CREATE TRIGGER trg_evaluations_pct_range
BEFORE INSERT OR UPDATE ON evaluations
FOR EACH ROW
EXECUTE FUNCTION fn_trg_evaluation_pct_range();


-- =============================================================================
-- 12. Auditoría de cambios en los datos principales de una organización
-- Clave: AFTER UPDATE (la fila ya se guardó). to_jsonb(OLD) convierte la fila
-- anterior en un JSON; jsonb_each la recorre clave por clave y se guardan SOLO
-- las claves que cambiaron (columnas, valor anterior, valor nuevo).
-- Se ignoran updated_at (siempre cambia) e is_active (lo audita el trigger 13).
-- Prueba: UPDATE tenants SET email = 'otro@correo.co' WHERE id = 1;
--         SELECT ... FROM audit_log ORDER BY id DESC;
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_audit_tenant_changes()
RETURNS trigger AS $$
DECLARE
    v_cols text[];
    v_old  jsonb;
    v_new  jsonb;
BEGIN
    SELECT array_agg(o.key ORDER BY o.key),
           jsonb_object_agg(o.key, o.value)
    INTO v_cols, v_old
    FROM jsonb_each(to_jsonb(OLD)) AS o
    WHERE o.key NOT IN ('updated_at', 'is_active')
      AND o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);

    IF v_cols IS NULL THEN
        RETURN NULL;          -- no cambió ningún dato principal
    END IF;

    SELECT jsonb_object_agg(n.key, n.value)
    INTO v_new
    FROM jsonb_each(to_jsonb(NEW)) AS n
    WHERE n.key = ANY (v_cols);

    INSERT INTO audit_log (tenant_id, table_name, record_pk, operation, db_user,
                           application_name, client_addr, changed_columns,
                           old_values, new_values, extra_context)
    VALUES (NEW.id, 'tenants', NEW.id::text, 'U', current_user,
            NULLIF(current_setting('application_name', true), ''), inet_client_addr(),
            v_cols, v_old, v_new,
            jsonb_build_object('evento', 'cambio_datos'));

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenants_audit_changes ON tenants;
CREATE TRIGGER trg_tenants_audit_changes
AFTER UPDATE ON tenants
FOR EACH ROW
EXECUTE FUNCTION fn_trg_audit_tenant_changes();


-- =============================================================================
-- 13. Auditoría del cambio de ESTADO de una organización (valor anterior y nuevo)
-- Clave: la cláusula WHEN (...) del CREATE TRIGGER filtra: el trigger solo se
-- ejecuta si is_active realmente cambió.
-- Prueba: CALL sp_set_tenant_status(1, false);
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_audit_tenant_status()
RETURNS trigger AS $$
BEGIN
    INSERT INTO audit_log (tenant_id, table_name, record_pk, operation, db_user,
                           application_name, client_addr, changed_columns,
                           old_values, new_values, extra_context)
    VALUES (NEW.id, 'tenants', NEW.id::text, 'U', current_user,
            NULLIF(current_setting('application_name', true), ''), inet_client_addr(),
            ARRAY['is_active'],
            jsonb_build_object('is_active', OLD.is_active),
            jsonb_build_object('is_active', NEW.is_active),
            jsonb_build_object('evento', 'cambio_estado'));

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenants_audit_status ON tenants;
CREATE TRIGGER trg_tenants_audit_status
AFTER UPDATE OF is_active ON tenants
FOR EACH ROW
WHEN (OLD.is_active IS DISTINCT FROM NEW.is_active)
EXECUTE FUNCTION fn_trg_audit_tenant_status();


-- =============================================================================
-- 14. Registrar fecha y usuario responsable cuando una PLANTILLA se modifica
-- Clave: current_user = usuario de base de datos que ejecutó el UPDATE; la
-- fecha queda en changed_at (por defecto now()). Las plantillas son un
-- catálogo global, por eso tenant_id queda NULL. También se actualiza
-- templates.updated_at con la función genérica del trigger 1.
-- Prueba: UPDATE templates SET name = 'Nuevo nombre' WHERE id = 1;
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_trg_audit_template_changes()
RETURNS trigger AS $$
BEGIN
    IF (to_jsonb(OLD) - 'updated_at') IS NOT DISTINCT FROM (to_jsonb(NEW) - 'updated_at') THEN
        RETURN NULL;          -- no cambió nada relevante
    END IF;

    INSERT INTO audit_log (tenant_id, table_name, record_pk, operation, db_user,
                           application_name, client_addr,
                           old_values, new_values, extra_context)
    VALUES (NULL, 'templates', NEW.id::text, 'U', current_user,
            NULLIF(current_setting('application_name', true), ''), inet_client_addr(),
            to_jsonb(OLD), to_jsonb(NEW),
            jsonb_build_object('evento', 'plantilla_modificada'));

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_templates_set_updated_at ON templates;
CREATE TRIGGER trg_templates_set_updated_at
BEFORE UPDATE ON templates
FOR EACH ROW
EXECUTE FUNCTION fn_trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_templates_audit_changes ON templates;
CREATE TRIGGER trg_templates_audit_changes
AFTER UPDATE ON templates
FOR EACH ROW
EXECUTE FUNCTION fn_trg_audit_template_changes();


-- =============================================================================
-- 15. Liberar los bloqueos de edición VENCIDOS (editing_locks)
-- Problema real: un bloqueo vencido pero sin liberar (released_at NULL) sigue
-- ocupando el "único bloqueo vigente por documento" y no dejaría crear otro.
-- Solución: antes de cada INSERT en editing_locks se marcan como liberados
-- (released_at = su fecha de vencimiento) todos los vencidos.
-- Clave: FOR EACH STATEMENT = una vez por sentencia (no por fila). Al ser
-- BEFORE INSERT y hacer UPDATE (no INSERT), no se llama a sí mismo.
-- La función fn_release_expired_locks() también se puede ejecutar a mano
-- (SELECT fn_release_expired_locks();) o programar periódicamente.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_release_expired_locks()
RETURNS integer AS $$
DECLARE
    v_released integer;
BEGIN
    UPDATE editing_locks
    SET released_at = expires_at,
        updated_at  = now()
    WHERE released_at IS NULL
      AND expires_at < now();

    GET DIAGNOSTICS v_released = ROW_COUNT;
    RETURN v_released;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_trg_release_expired_locks()
RETURNS trigger AS $$
BEGIN
    PERFORM fn_release_expired_locks();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_editing_locks_release_expired ON editing_locks;
CREATE TRIGGER trg_editing_locks_release_expired
BEFORE INSERT ON editing_locks
FOR EACH STATEMENT
EXECUTE FUNCTION fn_trg_release_expired_locks();


-- =============================================================================
-- Documentación de los triggers (COMMENT ON TRIGGER, visible en pgAdmin)
-- =============================================================================
COMMENT ON TRIGGER trg_tenants_set_updated_at ON tenants IS 'Actualiza updated_at en cada modificación de la organización.';
COMMENT ON TRIGGER trg_persons_set_updated_at ON persons IS 'Actualiza updated_at en cada modificación de la persona.';
COMMENT ON TRIGGER trg_persons_tenant_active ON persons IS 'Impide registrar o trasladar personas a una organización inactiva.';
COMMENT ON TRIGGER trg_tenant_modules_not_assigned ON tenant_modules IS 'Impide asignar un módulo ya asignado a la organización.';
COMMENT ON TRIGGER trg_tenanttemplates_tenant_active ON tenanttemplates IS 'Impide asignar plantillas a organizaciones inactivas.';
COMMENT ON TRIGGER trg_persons_position_same_tenant ON persons IS 'Valida que el cargo pertenezca a la misma organización de la persona.';
COMMENT ON TRIGGER trg_tenanttemplates_set_updated_at ON tenanttemplates IS 'Registra la fecha de modificación de una plantilla asignada.';
COMMENT ON TRIGGER trg_tenants_prevent_delete ON tenants IS 'Impide eliminar una organización con personas asociadas.';
COMMENT ON TRIGGER trg_type_system_sst_prevent_delete ON type_system_sst IS 'Impide eliminar un sistema SST usado por organizaciones.';
COMMENT ON TRIGGER trg_modules_prevent_delete ON modules IS 'Impide eliminar un módulo asignado a organizaciones.';
COMMENT ON TRIGGER trg_evaluations_pct_range ON evaluations IS 'Valida que el porcentaje calculado (score/max_score) esté entre 0 y 100.';
COMMENT ON TRIGGER trg_tenants_audit_changes ON tenants IS 'Audita en audit_log los cambios de datos principales de la organización.';
COMMENT ON TRIGGER trg_tenants_audit_status ON tenants IS 'Audita en audit_log el valor anterior y nuevo del estado de la organización.';
COMMENT ON TRIGGER trg_templates_audit_changes ON templates IS 'Registra fecha y usuario responsable cuando se modifica una plantilla.';
COMMENT ON TRIGGER trg_templates_set_updated_at ON templates IS 'Actualiza updated_at de la plantilla.';
COMMENT ON TRIGGER trg_editing_locks_release_expired ON editing_locks IS 'Libera los bloqueos de edición vencidos antes de crear uno nuevo.';


-- =============================================================================
-- Ayuda para revisar los triggers creados
-- =============================================================================
SELECT c.relname AS table_name,
       tg.tgname AS trigger_name,
       tg.tgenabled AS enabled
FROM pg_trigger AS tg
INNER JOIN pg_class AS c ON c.oid = tg.tgrelid
WHERE NOT tg.tgisinternal
ORDER BY c.relname, tg.tgname;
