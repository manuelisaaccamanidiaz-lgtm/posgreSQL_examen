-- =============================================================================
-- 07_procedimientos.sql — Procedimientos almacenados (sección 5 del examen)
-- Base: PostgreSQL / PL/pgSQL. Requiere 01_schema.sql.
--
-- Convenciones (las de tu guía): sp_ = procedimiento, p_ = parámetro,
-- v_ = variable. Los nombres van en inglés para coincidir con el schema.
-- Regla del proyecto: sin SELECT *; alias en cada tabla.
--
-- ESTRUCTURA DE TODOS LOS PROCEDIMIENTOS
--   CREATE OR REPLACE PROCEDURE sp_nombre(parámetros)
--   LANGUAGE plpgsql
--   AS $$
--   DECLARE   v_variable tipo;         -- variables (opcional)
--   BEGIN
--       validaciones con IF ... RAISE EXCEPTION ...;
--       operación (INSERT / UPDATE / DELETE);
--       RAISE NOTICE 'mensaje';
--   END;
--   $$;
--   Se ejecuta con CALL sp_nombre(...);
--
-- IDEAS CLAVE
--   * RAISE NOTICE  = muestra un mensaje y sigue.
--     RAISE EXCEPTION = lanza un error, detiene el procedimiento y DESHACE todo
--     lo que ese CALL haya hecho (un procedimiento corre dentro de una
--     transacción).
--   * Un procedimiento NO devuelve valores con RETURN (eso es de las funciones).
--     Para devolver algo se usa un parámetro INOUT: entra como NULL y sale con
--     el resultado. Si tiene DEFAULT NULL, ni siquiera hay que pasarlo.
--   * SELECT ... INTO v_x FROM ...; IF NOT FOUND THEN ... -> ¿no hubo fila?
--   * updated_at NO se actualiza solo (los triggers vienen después), por eso
--     los UPDATE lo cambian a mano con updated_at = now().
--   * Reglas de negocio ADOPTADAS (el examen no las define; confírmalas con el
--     profesor): solo se trabaja con organizaciones activas; una plantilla solo
--     se asigna si la organización tiene habilitado el sistema de la plantilla.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Registrar una organización (sin duplicar su identificación)
-- Clave: validar con EXISTS ANTES de insertar; RETURNING ... INTO devuelve el id
-- generado por la base. "Identificación definida por el sistema" = tax_id y slug.
-- Ejemplo: CALL sp_register_tenant(1, 1, 'Nueva S.A.S.', '900999888',
--                                  'info@nueva.co', '6070000000', 'nueva');
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_register_tenant(
    p_tenant_size_id  bigint,
    p_city_id         bigint,
    p_legal_name      varchar,
    p_tax_id          varchar,
    p_email           varchar,
    p_phone           varchar,
    p_slug            varchar,
    INOUT p_tenant_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_legal_name IS NULL OR btrim(p_legal_name) = '' THEN
        RAISE EXCEPTION 'El nombre de la organización es obligatorio';
    END IF;

    IF EXISTS (SELECT 1 FROM tenants AS t WHERE t.tax_id = p_tax_id) THEN
        RAISE EXCEPTION 'Ya existe una organización con la identificación fiscal %', p_tax_id;
    END IF;

    IF EXISTS (SELECT 1 FROM tenants AS t WHERE t.slug = p_slug) THEN
        RAISE EXCEPTION 'Ya existe una organización con el slug %', p_slug;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tenant_sizes AS ts
                   WHERE ts.id = p_tenant_size_id AND ts.is_active = true) THEN
        RAISE EXCEPTION 'El tamaño de empresa % no existe o está inactivo', p_tenant_size_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM cities AS c
                   WHERE c.id = p_city_id AND c.is_active = true) THEN
        RAISE EXCEPTION 'La ciudad % no existe o está inactiva', p_city_id;
    END IF;

    INSERT INTO tenants (tenant_size_id, city_id, legal_name, tax_id, email, phone, slug)
    VALUES (p_tenant_size_id, p_city_id, p_legal_name, p_tax_id, p_email, p_phone, p_slug)
    RETURNING id INTO p_tenant_id;

    RAISE NOTICE 'Organización registrada con id %', p_tenant_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 2. Registrar una persona y asociarla a una organización y a un cargo
-- Clave: el cargo debe ser de ESA organización (regla multi-tenant). El schema ya
-- lo garantiza con una FK compuesta, pero validar antes da un mensaje claro.
-- Ejemplo: CALL sp_register_person(1, 1, 'CC', '1010', 'Laura', 'Mora');
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_register_person(
    p_tenant_id       bigint,
    p_position_id     bigint,
    p_document_type   varchar,
    p_document_number varchar,
    p_first_name      varchar,
    p_last_name       varchar,
    p_hire_date       date    DEFAULT CURRENT_DATE,
    p_email           varchar DEFAULT NULL,
    INOUT p_person_id bigint  DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_active boolean;
BEGIN
    SELECT t.is_active INTO v_tenant_active
    FROM tenants AS t
    WHERE t.id = p_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;
    IF NOT v_tenant_active THEN
        RAISE EXCEPTION 'La organización % está inactiva; no se pueden registrar personas', p_tenant_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM positions AS pos
                   WHERE pos.id = p_position_id
                     AND pos.tenant_id = p_tenant_id
                     AND pos.is_active = true) THEN
        RAISE EXCEPTION 'El cargo % no existe, está inactivo o no pertenece a la organización %',
                        p_position_id, p_tenant_id;
    END IF;

    IF EXISTS (SELECT 1 FROM persons AS p
               WHERE p.tenant_id = p_tenant_id
                 AND p.document_type = p_document_type
                 AND p.document_number = p_document_number) THEN
        RAISE EXCEPTION 'Ya existe una persona con el documento % % en la organización %',
                        p_document_type, p_document_number, p_tenant_id;
    END IF;

    INSERT INTO persons (tenant_id, position_id, document_type, document_number,
                         first_name, last_name, email, hire_date)
    VALUES (p_tenant_id, p_position_id, p_document_type, p_document_number,
            p_first_name, p_last_name, p_email, p_hire_date)
    RETURNING id INTO p_person_id;

    RAISE NOTICE 'Persona registrada con id %', p_person_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 3. Cambiar el estado de una organización (activa / inactiva)
-- Clave: IF / ELSE para no hacer un UPDATE inútil si ya tiene ese estado.
-- Ejemplo: CALL sp_set_tenant_status(3, false);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_set_tenant_status(
    p_tenant_id bigint,
    p_is_active boolean
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current boolean;
BEGIN
    SELECT t.is_active INTO v_current
    FROM tenants AS t
    WHERE t.id = p_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;

    IF v_current = p_is_active THEN
        RAISE NOTICE 'La organización % ya estaba %', p_tenant_id,
                     CASE WHEN p_is_active THEN 'activa' ELSE 'inactiva' END;
    ELSE
        UPDATE tenants
        SET is_active  = p_is_active,
            updated_at = now()
        WHERE id = p_tenant_id;

        RAISE NOTICE 'La organización % ahora está %', p_tenant_id,
                     CASE WHEN p_is_active THEN 'activa' ELSE 'inactiva' END;
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- 4. Asignar un módulo a una organización (sin duplicados)
-- Clave: IF / ELSIF / ELSE con tres casos:
--   no existe la asignación -> se crea;
--   existe y está activa    -> error (duplicado);
--   existe pero inactiva    -> se reactiva.
-- Ejemplo: CALL sp_assign_module(2, 1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_assign_module(
    p_tenant_id bigint,
    p_module_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_active boolean;
    v_module_active boolean;
    v_link_active   boolean;
BEGIN
    SELECT t.is_active INTO v_tenant_active FROM tenants AS t WHERE t.id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;
    IF NOT v_tenant_active THEN
        RAISE EXCEPTION 'La organización % está inactiva', p_tenant_id;
    END IF;

    SELECT m.is_active INTO v_module_active FROM modules AS m WHERE m.id = p_module_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El módulo % no existe', p_module_id;
    END IF;
    IF NOT v_module_active THEN
        RAISE EXCEPTION 'El módulo % está inactivo', p_module_id;
    END IF;

    SELECT tm.is_active INTO v_link_active
    FROM tenant_modules AS tm
    WHERE tm.tenant_id = p_tenant_id
      AND tm.module_id = p_module_id;

    IF NOT FOUND THEN
        INSERT INTO tenant_modules (tenant_id, module_id)
        VALUES (p_tenant_id, p_module_id);
        RAISE NOTICE 'Módulo % asignado a la organización %', p_module_id, p_tenant_id;
    ELSIF v_link_active THEN
        RAISE EXCEPTION 'El módulo % ya está asignado y activo en la organización %',
                        p_module_id, p_tenant_id;
    ELSE
        UPDATE tenant_modules
        SET is_active   = true,
            enabled_at  = now(),
            disabled_at = NULL,
            updated_at  = now()
        WHERE tenant_id = p_tenant_id
          AND module_id = p_module_id;
        RAISE NOTICE 'Asignación del módulo % reactivada en la organización %',
                     p_module_id, p_tenant_id;
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- 5. Habilitar un sistema SST (SST / PESV) para una organización
-- Clave: misma técnica que sp_assign_module (crear / error / reactivar).
-- Ejemplo: CALL sp_enable_system(1, 2);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_enable_system(
    p_tenant_id bigint,
    p_system_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_active boolean;
    v_system_active boolean;
    v_link_active   boolean;
BEGIN
    SELECT t.is_active INTO v_tenant_active FROM tenants AS t WHERE t.id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;
    IF NOT v_tenant_active THEN
        RAISE EXCEPTION 'La organización % está inactiva', p_tenant_id;
    END IF;

    SELECT s.is_active INTO v_system_active FROM type_system_sst AS s WHERE s.id = p_system_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El sistema % no existe', p_system_id;
    END IF;
    IF NOT v_system_active THEN
        RAISE EXCEPTION 'El sistema % está inactivo', p_system_id;
    END IF;

    SELECT ts.is_active INTO v_link_active
    FROM tenantsystems AS ts
    WHERE ts.tenant_id = p_tenant_id
      AND ts.type_system_sst_id = p_system_id;

    IF NOT FOUND THEN
        INSERT INTO tenantsystems (tenant_id, type_system_sst_id)
        VALUES (p_tenant_id, p_system_id);
        RAISE NOTICE 'Sistema % habilitado para la organización %', p_system_id, p_tenant_id;
    ELSIF v_link_active THEN
        RAISE EXCEPTION 'El sistema % ya está habilitado en la organización %',
                        p_system_id, p_tenant_id;
    ELSE
        UPDATE tenantsystems
        SET is_active      = true,
            activated_at   = now(),
            deactivated_at = NULL,
            updated_at     = now()
        WHERE tenant_id = p_tenant_id
          AND type_system_sst_id = p_system_id;
        RAISE NOTICE 'Sistema % reactivado para la organización %', p_system_id, p_tenant_id;
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- 6. Asignar una plantilla a una organización indicando sistema, etapa PHVA y formato
-- Clave: el procedimiento comprueba que el sistema, la etapa y el formato que le
-- pasas SÍ correspondan a la plantilla. Además crea el documento inicial
-- (estado no_iniciado): una fila de documents por asignación (supuesto S12).
-- Ejemplo: CALL sp_assign_template(3, 1, 1, 1, 1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_assign_template(
    p_tenant_id             bigint,
    p_template_id           bigint,
    p_system_id             bigint,
    p_phva_stage_id         bigint,
    p_format_id             bigint,
    p_due_date              date   DEFAULT NULL,
    p_responsible_person_id bigint DEFAULT NULL,
    INOUT p_tenanttemplate_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_active   boolean;
    v_template_active boolean;
    v_template_system bigint;
    v_template_phva   bigint;
    v_template_name   varchar;
BEGIN
    SELECT t.is_active INTO v_tenant_active FROM tenants AS t WHERE t.id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;
    IF NOT v_tenant_active THEN
        RAISE EXCEPTION 'La organización % está inactiva', p_tenant_id;
    END IF;

    SELECT tp.is_active, tp.type_system_sst_id, tp.phva_stage_id, tp.name
    INTO v_template_active, v_template_system, v_template_phva, v_template_name
    FROM templates AS tp
    WHERE tp.id = p_template_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La plantilla % no existe', p_template_id;
    END IF;
    IF NOT v_template_active THEN
        RAISE EXCEPTION 'La plantilla % está inactiva', p_template_id;
    END IF;
    IF v_template_system <> p_system_id THEN
        RAISE EXCEPTION 'La plantilla % no pertenece al sistema %', p_template_id, p_system_id;
    END IF;
    IF v_template_phva <> p_phva_stage_id THEN
        RAISE EXCEPTION 'La plantilla % no pertenece a la etapa PHVA %', p_template_id, p_phva_stage_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM formats_sst AS f
                   WHERE f.id = p_format_id
                     AND f.template_id = p_template_id
                     AND f.is_active = true) THEN
        RAISE EXCEPTION 'El formato % no existe, está inactivo o no corresponde a la plantilla %',
                        p_format_id, p_template_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tenantsystems AS ts
                   WHERE ts.tenant_id = p_tenant_id
                     AND ts.type_system_sst_id = p_system_id
                     AND ts.is_active = true) THEN
        RAISE EXCEPTION 'La organización % no tiene habilitado el sistema %', p_tenant_id, p_system_id;
    END IF;

    IF EXISTS (SELECT 1 FROM tenanttemplates AS tt
               WHERE tt.tenant_id = p_tenant_id
                 AND tt.template_id = p_template_id) THEN
        RAISE EXCEPTION 'La plantilla % ya está asignada a la organización %', p_template_id, p_tenant_id;
    END IF;

    IF p_responsible_person_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM persons AS p
                       WHERE p.id = p_responsible_person_id
                         AND p.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'La persona responsable % no pertenece a la organización %',
                        p_responsible_person_id, p_tenant_id;
    END IF;

    INSERT INTO tenanttemplates (tenant_id, template_id, due_date, responsible_person_id)
    VALUES (p_tenant_id, p_template_id, p_due_date, p_responsible_person_id)
    RETURNING id INTO p_tenanttemplate_id;

    INSERT INTO documents (tenanttemplate_id, title)
    VALUES (p_tenanttemplate_id, v_template_name);

    RAISE NOTICE 'Plantilla % asignada a la organización % (asignación %)',
                 p_template_id, p_tenant_id, p_tenanttemplate_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 7. Cambiar el cargo de una persona dentro de su organización
-- Clave: la organización se obtiene DE LA PERSONA (SELECT ... INTO con varias
-- variables) y el nuevo cargo debe pertenecer a esa misma organización.
-- Ejemplo: CALL sp_change_person_position(2, 1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_change_person_position(
    p_person_id       bigint,
    p_new_position_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id        bigint;
    v_current_position bigint;
    v_person_active    boolean;
BEGIN
    SELECT p.tenant_id, p.position_id, p.is_active
    INTO v_tenant_id, v_current_position, v_person_active
    FROM persons AS p
    WHERE p.id = p_person_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La persona % no existe', p_person_id;
    END IF;
    IF NOT v_person_active THEN
        RAISE EXCEPTION 'La persona % está inactiva', p_person_id;
    END IF;
    IF v_current_position = p_new_position_id THEN
        RAISE EXCEPTION 'La persona % ya tiene el cargo %', p_person_id, p_new_position_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM positions AS pos
                   WHERE pos.id = p_new_position_id
                     AND pos.tenant_id = v_tenant_id
                     AND pos.is_active = true) THEN
        RAISE EXCEPTION 'El cargo % no existe, está inactivo o pertenece a otra organización',
                        p_new_position_id;
    END IF;

    UPDATE persons
    SET position_id = p_new_position_id,
        updated_at  = now()
    WHERE id = p_person_id;

    RAISE NOTICE 'Persona % cambió del cargo % al cargo %',
                 p_person_id, v_current_position, p_new_position_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 8. Trasladar una persona de una organización a otra
-- Clave: por las FK compuestas, una persona referenciada como responsable,
-- asignador o evaluador de su organización actual NO puede cambiar de
-- organización sin más. Antes del traslado se limpian esas referencias y se
-- liberan sus bloqueos de edición; luego se cambian organización y cargo en el
-- MISMO UPDATE (la FK compuesta se comprueba al final de la sentencia).
-- Ejemplo: CALL sp_transfer_person(5, 1, 2);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_transfer_person(
    p_person_id        bigint,
    p_new_tenant_id    bigint,
    p_new_position_id  bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_tenant_id   bigint;
    v_person_active   boolean;
    v_document_type   varchar;
    v_document_number varchar;
    v_email           varchar;
    v_new_active      boolean;
BEGIN
    SELECT p.tenant_id, p.is_active, p.document_type, p.document_number, p.email
    INTO v_old_tenant_id, v_person_active, v_document_type, v_document_number, v_email
    FROM persons AS p
    WHERE p.id = p_person_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La persona % no existe', p_person_id;
    END IF;
    IF NOT v_person_active THEN
        RAISE EXCEPTION 'La persona % está inactiva', p_person_id;
    END IF;
    IF v_old_tenant_id = p_new_tenant_id THEN
        RAISE EXCEPTION 'La persona % ya pertenece a la organización %', p_person_id, p_new_tenant_id;
    END IF;

    SELECT t.is_active INTO v_new_active FROM tenants AS t WHERE t.id = p_new_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización destino % no existe', p_new_tenant_id;
    END IF;
    IF NOT v_new_active THEN
        RAISE EXCEPTION 'La organización destino % está inactiva', p_new_tenant_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM positions AS pos
                   WHERE pos.id = p_new_position_id
                     AND pos.tenant_id = p_new_tenant_id
                     AND pos.is_active = true) THEN
        RAISE EXCEPTION 'El cargo % no existe, está inactivo o no pertenece a la organización destino %',
                        p_new_position_id, p_new_tenant_id;
    END IF;

    IF EXISTS (SELECT 1 FROM persons AS p
               WHERE p.tenant_id = p_new_tenant_id
                 AND p.document_type = v_document_type
                 AND p.document_number = v_document_number) THEN
        RAISE EXCEPTION 'La organización destino ya tiene una persona con el documento % %',
                        v_document_type, v_document_number;
    END IF;

    IF v_email IS NOT NULL
       AND EXISTS (SELECT 1 FROM persons AS p
                   WHERE p.tenant_id = p_new_tenant_id
                     AND p.email = v_email) THEN
        RAISE EXCEPTION 'La organización destino ya tiene una persona con el correo %', v_email;
    END IF;

    -- Limpiar lo que la persona tenía en la organización de origen
    UPDATE tenanttemplates
    SET responsible_person_id = NULL, updated_at = now()
    WHERE tenant_id = v_old_tenant_id AND responsible_person_id = p_person_id;

    UPDATE tenanttemplates
    SET assigned_by_person_id = NULL, updated_at = now()
    WHERE tenant_id = v_old_tenant_id AND assigned_by_person_id = p_person_id;

    UPDATE evaluations
    SET evaluator_person_id = NULL, updated_at = now()
    WHERE tenant_id = v_old_tenant_id AND evaluator_person_id = p_person_id;

    UPDATE editing_locks
    SET released_at = now(), updated_at = now()
    WHERE locked_by_person_id = p_person_id AND released_at IS NULL;

    -- Traslado (organización y cargo en la misma sentencia)
    UPDATE persons
    SET tenant_id   = p_new_tenant_id,
        position_id = p_new_position_id,
        updated_at  = now()
    WHERE id = p_person_id;

    RAISE NOTICE 'Persona % trasladada de la organización % a la organización %',
                 p_person_id, v_old_tenant_id, p_new_tenant_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 9. Deshabilitar todos los módulos de una organización inactiva
-- Clave: GET DIAGNOSTICS v_x = ROW_COUNT dice cuántas filas afectó el último UPDATE.
-- Ejemplo: CALL sp_set_tenant_status(3, false); CALL sp_disable_tenant_modules(3);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_disable_tenant_modules(
    p_tenant_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_active boolean;
    v_disabled      integer;
BEGIN
    SELECT t.is_active INTO v_tenant_active FROM tenants AS t WHERE t.id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;
    IF v_tenant_active THEN
        RAISE EXCEPTION 'La organización % sigue activa; márcala como inactiva primero', p_tenant_id;
    END IF;

    UPDATE tenant_modules
    SET is_active   = false,
        disabled_at = now(),
        updated_at  = now()
    WHERE tenant_id = p_tenant_id
      AND is_active = true;

    GET DIAGNOSTICS v_disabled = ROW_COUNT;

    RAISE NOTICE 'Se deshabilitaron % módulos de la organización %', v_disabled, p_tenant_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 10. Eliminar una asignación de módulo (de forma controlada)
-- Clave: ANTES de borrar se busca si algo depende de ella. Dependiente = una
-- plantilla ya asignada a la organización que tiene formatos de ese módulo.
-- IF NOT FOUND después de un DELETE detecta que no había nada que borrar.
-- Ejemplo: CALL sp_remove_module_assignment(3, 3);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_remove_module_assignment(
    p_tenant_id bigint,
    p_module_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_dependents integer;
BEGIN
    SELECT COUNT(DISTINCT tt.id) INTO v_dependents
    FROM tenanttemplates AS tt
    INNER JOIN formats_sst AS f ON f.template_id = tt.template_id
                               AND f.module_id = p_module_id
    WHERE tt.tenant_id = p_tenant_id
      AND tt.is_active = true;

    IF v_dependents > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar: % plantillas asignadas a la organización % dependen del módulo %',
                        v_dependents, p_tenant_id, p_module_id;
    END IF;

    DELETE FROM tenant_modules
    WHERE tenant_id = p_tenant_id
      AND module_id = p_module_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El módulo % no estaba asignado a la organización %', p_module_id, p_tenant_id;
    END IF;

    RAISE NOTICE 'Asignación del módulo % eliminada de la organización %', p_module_id, p_tenant_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 11. Número total de plantillas de una organización (con RAISE NOTICE)
-- Clave: SELECT COUNT(*) INTO variable. Solo cuenta asignaciones activas.
-- Ejemplo: CALL sp_count_tenant_templates(1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_count_tenant_templates(
    p_tenant_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tenants AS t WHERE t.id = p_tenant_id) THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;

    SELECT COUNT(*) INTO v_total
    FROM tenanttemplates AS tt
    WHERE tt.tenant_id = p_tenant_id
      AND tt.is_active = true;

    RAISE NOTICE 'La organización % tiene % plantillas asignadas', p_tenant_id, v_total;
END;
$$;


-- -----------------------------------------------------------------------------
-- 12. Porcentaje de cumplimiento documental de una organización
-- Clave: finalizados y pendientes se cuentan en una sola consulta con
-- SUM(CASE ...); solo cuenta la última versión activa de cada documento.
-- El resultado sale por el parámetro INOUT p_percentage (y por RAISE NOTICE).
-- Con 0 documentos no se puede dividir: el resultado queda en NULL.
-- Ejemplo: CALL sp_calc_tenant_compliance(1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_calc_tenant_compliance(
    p_tenant_id          bigint,
    INOUT p_percentage   numeric DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_finished integer;
    v_pending  integer;
    v_total    integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tenants AS t WHERE t.id = p_tenant_id) THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;

    SELECT COALESCE(SUM(CASE WHEN d.state = 'finalizado' THEN 1 ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN d.state IN ('no_iniciado', 'borrador') THEN 1 ELSE 0 END), 0)
    INTO v_finished, v_pending
    FROM tenanttemplates AS tt
    INNER JOIN documents AS d ON d.tenanttemplate_id = tt.id
                             AND d.is_active = true
                             AND d.version = (SELECT MAX(d2.version)
                                              FROM documents AS d2
                                              WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                                                AND d2.is_active = true)
    WHERE tt.tenant_id = p_tenant_id
      AND tt.is_active = true;

    v_total := v_finished + v_pending;

    IF v_total = 0 THEN
        p_percentage := NULL;
        RAISE NOTICE 'La organización % no tiene documentos: no hay porcentaje', p_tenant_id;
    ELSE
        p_percentage := ROUND(100.0 * v_finished / v_total, 2);
        RAISE NOTICE 'Organización %: % finalizados, % pendientes, cumplimiento % %%',
                     p_tenant_id, v_finished, v_pending, p_percentage;
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- 13. Cantidad de documentos de una organización en una etapa PHVA
-- Clave: dos parámetros de entrada y uno INOUT con el resultado.
-- Ejemplo: CALL sp_count_docs_by_phva(1, 1);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_count_docs_by_phva(
    p_tenant_id             bigint,
    p_phva_stage_id         bigint,
    INOUT p_total_documents integer DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stage_name varchar;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tenants AS t WHERE t.id = p_tenant_id) THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;

    SELECT ph.name INTO v_stage_name FROM phva_stages AS ph WHERE ph.id = p_phva_stage_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La etapa PHVA % no existe', p_phva_stage_id;
    END IF;

    SELECT COUNT(d.id) INTO p_total_documents
    FROM tenanttemplates AS tt
    INNER JOIN templates AS tp ON tp.id = tt.template_id
                              AND tp.phva_stage_id = p_phva_stage_id
    INNER JOIN documents AS d  ON d.tenanttemplate_id = tt.id
                              AND d.is_active = true
                              AND d.version = (SELECT MAX(d2.version)
                                               FROM documents AS d2
                                               WHERE d2.tenanttemplate_id = d.tenanttemplate_id
                                                 AND d2.is_active = true)
    WHERE tt.tenant_id = p_tenant_id
      AND tt.is_active = true;

    RAISE NOTICE 'La organización % tiene % documentos en la etapa %',
                 p_tenant_id, p_total_documents, v_stage_name;
END;
$$;


-- -----------------------------------------------------------------------------
-- 14. Modificar los datos de contacto de una organización
-- Clave: un solo UPDATE cambia varias columnas y fija updated_at.
-- COALESCE(p_x, columna) = "si no me pasan valor, conserva el que ya tenía".
-- Ejemplo: CALL sp_update_tenant_contact(1, 'nuevo@andes.co', '6076111111',
--                                        p_contact_name => 'Laura Mora');
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_update_tenant_contact(
    p_tenant_id     bigint,
    p_email         varchar,
    p_phone         varchar,
    p_contact_name  varchar DEFAULT NULL,
    p_contact_email varchar DEFAULT NULL,
    p_address       varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_email IS NULL OR btrim(p_email) = '' OR p_phone IS NULL OR btrim(p_phone) = '' THEN
        RAISE EXCEPTION 'El correo y el teléfono son obligatorios';
    END IF;

    UPDATE tenants
    SET email         = p_email,
        phone         = p_phone,
        contact_name  = COALESCE(p_contact_name, contact_name),
        contact_email = COALESCE(p_contact_email, contact_email),
        address       = COALESCE(p_address, address),
        updated_at    = now()
    WHERE id = p_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;

    RAISE NOTICE 'Datos de contacto de la organización % actualizados', p_tenant_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- 15. Asignar plantillas CON MANEJO DE EXCEPCIONES
-- Diferencia con el 6: allí validamos a mano con RAISE EXCEPTION; aquí dejamos
-- que la base rechace lo inválido (UNIQUE, FK) y lo CAPTURAMOS con
-- EXCEPTION WHEN ... THEN. El procedimiento nunca "revienta": informa el
-- resultado en p_status.
-- Si ocurre un error dentro del bloque BEGIN ... EXCEPTION, PostgreSQL deshace
-- todo lo hecho en ese bloque (por ejemplo, la asignación no queda a medias).
-- Códigos que captura: unique_violation, foreign_key_violation, check_violation,
-- raise_exception (nuestros errores) y OTHERS (cualquier otro).
-- Ejemplo: CALL sp_assign_template_safe(1, 2);
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_assign_template_safe(
    p_tenant_id       bigint,
    p_template_id     bigint,
    p_due_date        date DEFAULT NULL,
    INOUT p_status    text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_active   boolean;
    v_template_name   varchar;
    v_tenanttemplate  bigint;
BEGIN
    SELECT t.is_active INTO v_tenant_active FROM tenants AS t WHERE t.id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La organización % no existe', p_tenant_id;
    END IF;
    IF NOT v_tenant_active THEN
        RAISE EXCEPTION 'La organización % está inactiva', p_tenant_id;
    END IF;

    SELECT tp.name INTO v_template_name FROM templates AS tp WHERE tp.id = p_template_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La plantilla % no existe', p_template_id;
    END IF;

    INSERT INTO tenanttemplates (tenant_id, template_id, due_date)
    VALUES (p_tenant_id, p_template_id, p_due_date)
    RETURNING id INTO v_tenanttemplate;

    INSERT INTO documents (tenanttemplate_id, title)
    VALUES (v_tenanttemplate, v_template_name);

    p_status := 'OK: plantilla ' || p_template_id || ' asignada (asignación ' || v_tenanttemplate || ')';
    RAISE NOTICE '%', p_status;

EXCEPTION
    WHEN unique_violation THEN
        p_status := 'ERROR: la plantilla ' || p_template_id || ' ya estaba asignada a la organización ' || p_tenant_id;
        RAISE NOTICE '%', p_status;
    WHEN foreign_key_violation THEN
        p_status := 'ERROR: una referencia no existe (' || SQLERRM || ')';
        RAISE NOTICE '%', p_status;
    WHEN check_violation THEN
        p_status := 'ERROR: un dato no cumple una regla (' || SQLERRM || ')';
        RAISE NOTICE '%', p_status;
    WHEN raise_exception THEN
        p_status := 'ERROR: ' || SQLERRM;
        RAISE NOTICE '%', p_status;
    WHEN OTHERS THEN
        p_status := 'ERROR inesperado [' || SQLSTATE || ']: ' || SQLERRM;
        RAISE NOTICE '%', p_status;
END;
$$;


-- =============================================================================
-- EXTRA (operaciones transaccionales): COMMIT dentro de un procedimiento
-- El examen menciona "operaciones transaccionales". Un procedimiento (a
-- diferencia de una función) puede hacer COMMIT. Este recorre las
-- organizaciones inactivas con un ciclo FOR y confirma cada una por separado:
-- si falla la tercera, las dos primeras ya quedaron guardadas.
-- Restricciones: solo funciona con CALL directo (no dentro de BEGIN ... COMMIT
-- abierto) y no dentro de un bloque con EXCEPTION.
-- Ejemplo: CALL sp_disable_modules_of_inactive_tenants();
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_disable_modules_of_inactive_tenants()
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant RECORD;
BEGIN
    FOR v_tenant IN
        SELECT t.id
        FROM tenants AS t
        WHERE t.is_active = false
        ORDER BY t.id
    LOOP
        CALL sp_disable_tenant_modules(v_tenant.id);
        COMMIT;
    END LOOP;
END;
$$;


-- =============================================================================
-- Documentación de los procedimientos (COMMENT ON, visible en pgAdmin)
-- =============================================================================
COMMENT ON PROCEDURE sp_register_tenant IS 'Registra una organización validando que tax_id y slug no existan; devuelve el id nuevo.';
COMMENT ON PROCEDURE sp_register_person IS 'Registra una persona en una organización activa con un cargo de esa misma organización.';
COMMENT ON PROCEDURE sp_set_tenant_status IS 'Activa o inactiva una organización.';
COMMENT ON PROCEDURE sp_assign_module IS 'Asigna un módulo a una organización sin duplicar; reactiva si estaba inactivo.';
COMMENT ON PROCEDURE sp_enable_system IS 'Habilita un sistema SST/PESV para una organización; reactiva si estaba inactivo.';
COMMENT ON PROCEDURE sp_assign_template IS 'Asigna una plantilla validando sistema, etapa PHVA y formato; crea el documento inicial.';
COMMENT ON PROCEDURE sp_change_person_position IS 'Cambia el cargo de una persona dentro de su organización.';
COMMENT ON PROCEDURE sp_transfer_person IS 'Traslada una persona a otra organización limpiando sus referencias en la anterior.';
COMMENT ON PROCEDURE sp_disable_tenant_modules IS 'Deshabilita todos los módulos de una organización inactiva.';
COMMENT ON PROCEDURE sp_remove_module_assignment IS 'Elimina una asignación de módulo si no hay plantillas que dependan de ella.';
COMMENT ON PROCEDURE sp_count_tenant_templates IS 'Muestra con RAISE NOTICE cuántas plantillas tiene una organización.';
COMMENT ON PROCEDURE sp_calc_tenant_compliance IS 'Calcula el porcentaje de cumplimiento documental de una organización (INOUT).';
COMMENT ON PROCEDURE sp_count_docs_by_phva IS 'Cuenta los documentos de una organización en una etapa PHVA (INOUT).';
COMMENT ON PROCEDURE sp_update_tenant_contact IS 'Modifica los datos de contacto de una organización y actualiza updated_at.';
COMMENT ON PROCEDURE sp_assign_template_safe IS 'Asigna una plantilla capturando excepciones; informa el resultado en p_status.';
COMMENT ON PROCEDURE sp_disable_modules_of_inactive_tenants IS 'Recorre las organizaciones inactivas y deshabilita sus módulos con COMMIT por organización.';
