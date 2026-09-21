-- =============================================================================
-- sql/01_schema.sql — DDL del modelo lógico (fuente de verdad: docs/01_modelo_datos.md)
-- Plataforma multi-tenant de gestión SST y PESV — PostgreSQL
--
-- Contenido: 19 tablas con PK, FK (ON DELETE RESTRICT), UNIQUE y CHECK nombrados
--            (prefijos pk_, fk_, uq_, ck_ + tabla + columna), índices únicos
--            parciales que respaldan restricciones, COMMENT ON TABLE/COLUMN y
--            NOT NULL sin nombre.
--
-- NO incluye: datos, vistas, funciones, procedimientos ni triggers (archivos
-- posteriores). Los índices de consulta van en sql/09_indices.sql. El
-- mantenimiento de updated_at (S18), RLS y las reglas no declarativas de
-- §12.4 se implementan con triggers/políticas en archivos posteriores.
--
-- Convención de nombres de restricciones:
--   pk_<tabla>                      clave primaria
--   fk_<tabla>_<columna>            clave foránea (compuesta: dos columnas en el nombre)
--   uq_<tabla>_<columnas>           unique
--   ck_<tabla>_<columna>            check (los NOT NULL van sin nombre)
-- =============================================================================

BEGIN;

-- =============================================================================
-- BLOQUE DE LIMPIEZA (orden inverso de dependencias) — permite re-ejecutar
-- =============================================================================

DROP TABLE IF EXISTS audit_log      CASCADE;
DROP TABLE IF EXISTS editing_locks  CASCADE;
DROP TABLE IF EXISTS evaluations    CASCADE;
DROP TABLE IF EXISTS documents      CASCADE;
DROP TABLE IF EXISTS tenanttemplates CASCADE;
DROP TABLE IF EXISTS formats_sst    CASCADE;
DROP TABLE IF EXISTS templates      CASCADE;
DROP TABLE IF EXISTS tenant_modules CASCADE;
DROP TABLE IF EXISTS tenantsystems  CASCADE;
DROP TABLE IF EXISTS persons        CASCADE;
DROP TABLE IF EXISTS positions      CASCADE;
DROP TABLE IF EXISTS tenants        CASCADE;
DROP TABLE IF EXISTS cities         CASCADE;
DROP TABLE IF EXISTS departments    CASCADE;
DROP TABLE IF EXISTS modules        CASCADE;
DROP TABLE IF EXISTS countries      CASCADE;
DROP TABLE IF EXISTS tenant_sizes   CASCADE;
DROP TABLE IF EXISTS phva_stages    CASCADE;
DROP TABLE IF EXISTS type_system_sst CASCADE;

-- =============================================================================
-- 1. type_system_sst — tipos de sistema de gestión (SST, PESV)            §4.6
-- =============================================================================
CREATE TABLE type_system_sst (
    id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_type_system_sst PRIMARY KEY,
    code        varchar(20)  NOT NULL,
    name        varchar(120) NOT NULL,
    description text,
    legal_basis varchar(300),
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_type_system_sst_code UNIQUE (code),
    CONSTRAINT uq_type_system_sst_name UNIQUE (name)
);

COMMENT ON TABLE type_system_sst IS 'Catálogo global de tipos de sistema de gestión que la plataforma administra (SST, PESV).';

-- =============================================================================
-- 2. phva_stages — fases del ciclo PHVA (Planear, Hacer, Verificar, Actuar) §4.7
-- =============================================================================
CREATE TABLE phva_stages (
    id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_phva_stages PRIMARY KEY,
    code        char(1)      NOT NULL,
    name        varchar(40)  NOT NULL,
    description text,
    sort_order  smallint     NOT NULL,
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_phva_stages_code UNIQUE (code),
    CONSTRAINT uq_phva_stages_name UNIQUE (name)
);

COMMENT ON TABLE phva_stages IS 'Catálogo global de las fases del ciclo PHVA con las que se clasifican las plantillas.';

-- =============================================================================
-- 3. tenant_sizes — clasificación de tamaño de empresa                     §4.4
-- =============================================================================
CREATE TABLE tenant_sizes (
    id            bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_tenant_sizes PRIMARY KEY,
    code          varchar(20) NOT NULL,
    name          varchar(80) NOT NULL,
    min_employees integer     NOT NULL,
    max_employees integer,
    description   text,
    sort_order    smallint    NOT NULL,
    is_active     boolean     NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_tenant_sizes_code UNIQUE (code),
    CONSTRAINT uq_tenant_sizes_name UNIQUE (name),
    CONSTRAINT ck_tenant_sizes_min_employees CHECK (min_employees >= 1),
    CONSTRAINT ck_tenant_sizes_max_employees CHECK (max_employees IS NULL OR max_employees >= min_employees)
);

COMMENT ON TABLE tenant_sizes IS 'Catálogo global de tamaños de empresa (micro, pequeña, mediana, grande) por rango de trabajadores.';
COMMENT ON COLUMN tenant_sizes.max_employees IS 'Límite superior inclusivo del rango; nulo significa rango abierto (sin tope).';

-- =============================================================================
-- 4. countries — catálogo de países                                        §4.1
-- =============================================================================
CREATE TABLE countries (
    id           bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_countries PRIMARY KEY,
    iso_code     char(2)      NOT NULL,
    iso_code3    char(3)      NOT NULL,
    name         varchar(120) NOT NULL,
    phone_prefix varchar(8)   NOT NULL,
    is_active    boolean     NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_countries_iso_code  UNIQUE (iso_code),
    CONSTRAINT uq_countries_iso_code3 UNIQUE (iso_code3),
    CONSTRAINT uq_countries_name      UNIQUE (name)
);

COMMENT ON TABLE countries IS 'Catálogo global de países que soporta la ubicación geográfica y los prefijos telefónicos.';

-- =============================================================================
-- 5. modules — módulos funcionales por sistema                             §4.5
-- =============================================================================
CREATE TABLE modules (
    id                 bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_modules PRIMARY KEY,
    type_system_sst_id bigint       NOT NULL,
    code               varchar(40)  NOT NULL,
    title              varchar(120) NOT NULL,
    description        text,
    sort_order         smallint     NOT NULL DEFAULT 0,
    is_active          boolean      NOT NULL DEFAULT true,
    created_at         timestamptz  NOT NULL DEFAULT now(),
    updated_at         timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT fk_modules_type_system_sst_id
        FOREIGN KEY (type_system_sst_id) REFERENCES type_system_sst (id) ON DELETE RESTRICT,
    CONSTRAINT uq_modules_system_code UNIQUE (type_system_sst_id, code)
);

COMMENT ON TABLE modules IS 'Catálogo global de módulos funcionales de la plataforma, clasificado por tipo de sistema de gestión.';

-- =============================================================================
-- 6. departments — divisiones administrativas de primer nivel              §4.2
-- =============================================================================
CREATE TABLE departments (
    id         bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_departments PRIMARY KEY,
    country_id bigint       NOT NULL,
    code       varchar(10)  NOT NULL,
    name       varchar(150) NOT NULL,
    is_active  boolean     NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_departments_country_id
        FOREIGN KEY (country_id) REFERENCES countries (id) ON DELETE RESTRICT,
    CONSTRAINT uq_departments_country_code UNIQUE (country_id, code),
    CONSTRAINT uq_departments_country_name UNIQUE (country_id, name),
    CONSTRAINT uq_departments_id_country   UNIQUE (id, country_id)
);

COMMENT ON TABLE departments IS 'División administrativa de primer nivel dentro de un país (departamento/estado/región).';

-- =============================================================================
-- 7. cities — municipios / ciudades                                        §4.3
-- =============================================================================
CREATE TABLE cities (
    id            bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_cities PRIMARY KEY,
    department_id bigint       NOT NULL,
    code          varchar(10)  NOT NULL,
    name          varchar(150) NOT NULL,
    is_active     boolean     NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_cities_department_id
        FOREIGN KEY (department_id) REFERENCES departments (id) ON DELETE RESTRICT,
    CONSTRAINT uq_cities_department_code UNIQUE (department_id, code),
    CONSTRAINT uq_cities_department_name UNIQUE (department_id, name)
);

COMMENT ON TABLE cities IS 'Municipio/ciudad; nivel geográfico que se asigna a las empresas (departamento y país se derivan).';

-- =============================================================================
-- 8. tenants — empresas / organizaciones cliente                           §5.1
-- =============================================================================
CREATE TABLE tenants (
    id             bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_tenants PRIMARY KEY,
    tenant_size_id bigint       NOT NULL,
    city_id        bigint       NOT NULL,
    legal_name     varchar(200) NOT NULL,
    trade_name     varchar(200),
    tax_id         varchar(30)  NOT NULL,
    check_digit    char(1),
    email          varchar(160) NOT NULL,
    phone          varchar(30)  NOT NULL,
    address        varchar(200),
    contact_name   varchar(160),
    contact_email  varchar(160),
    slug           varchar(60)  NOT NULL,
    is_active      boolean     NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_tenants_tenant_size_id
        FOREIGN KEY (tenant_size_id) REFERENCES tenant_sizes (id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenants_city_id
        FOREIGN KEY (city_id) REFERENCES cities (id) ON DELETE RESTRICT,
    CONSTRAINT uq_tenants_tax_id UNIQUE (tax_id),
    CONSTRAINT uq_tenants_slug   UNIQUE (slug),
    CONSTRAINT ck_tenants_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

COMMENT ON TABLE tenants IS 'Organización cliente: identificación única, contacto, ubicación por municipio y tamaño.';
COMMENT ON COLUMN tenants.tax_id IS 'Identificación fiscal única de la organización (NIT/RUC/CIF), sin dígito de verificación separado.';
COMMENT ON COLUMN tenants.is_active IS 'Borrado lógico: false = empresa inactiva en la plataforma, conservando su histórico.';

-- =============================================================================
-- 9. positions — cargos por empresa                                        §5.2
-- =============================================================================
CREATE TABLE positions (
    id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_positions PRIMARY KEY,
    tenant_id   bigint       NOT NULL,
    name        varchar(160) NOT NULL,
    code        varchar(20),
    risk_level  smallint     NOT NULL,
    description text,
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_positions_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    CONSTRAINT uq_positions_tenant_name UNIQUE (tenant_id, name),
    CONSTRAINT uq_positions_id_tenant   UNIQUE (id, tenant_id),
    CONSTRAINT ck_positions_risk_level CHECK (risk_level BETWEEN 1 AND 5)
);

COMMENT ON TABLE positions IS 'Catálogo por empresa de cargos ocupados por las personas, con nivel de riesgo I–V.';
COMMENT ON COLUMN positions.risk_level IS 'Nivel de riesgo del cargo en escala 1 a 5 (I–V).';

-- =============================================================================
-- 10. persons — personas / trabajadores por empresa                        §5.3
-- =============================================================================
CREATE TABLE persons (
    id               bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_persons PRIMARY KEY,
    tenant_id        bigint       NOT NULL,
    position_id      bigint       NOT NULL,
    document_type    varchar(10)  NOT NULL,
    document_number  varchar(30)  NOT NULL,
    first_name       varchar(100) NOT NULL,
    last_name        varchar(100) NOT NULL,
    email            varchar(160),
    phone            varchar(30),
    birth_date       date,
    hire_date        date         NOT NULL,
    termination_date date,
    is_active        boolean     NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_persons_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    -- FK compuesta: el cargo debe pertenecer a la misma empresa que la persona (§3.2)
    CONSTRAINT fk_persons_position_id_tenant_id
        FOREIGN KEY (position_id, tenant_id) REFERENCES positions (id, tenant_id) ON DELETE RESTRICT,
    CONSTRAINT uq_persons_tenant_document UNIQUE (tenant_id, document_type, document_number),
    CONSTRAINT uq_persons_id_tenant       UNIQUE (id, tenant_id),
    CONSTRAINT ck_persons_document_type CHECK (document_type IN ('CC', 'CE', 'TI', 'PA', 'PPT', 'NIT')),
    CONSTRAINT ck_persons_termination_date CHECK (termination_date IS NULL OR termination_date >= hire_date)
);

-- Índice único parcial que respalda la clave candidata {tenant_id, email}
-- (solo cuando email no es nulo; §5.3)
CREATE UNIQUE INDEX uq_persons_tenant_email
    ON persons (tenant_id, email)
    WHERE email IS NOT NULL;

COMMENT ON TABLE persons IS 'Personas vinculadas a cada empresa con identificación, contacto, cargo y fechas laborales.';
COMMENT ON COLUMN persons.is_active IS 'Borrado lógico: false = vinculación laboral retirada, conservando el histórico.';

-- =============================================================================
-- 11. tenantsystems — sistemas habilitados por empresa                     §6.1
-- =============================================================================
CREATE TABLE tenantsystems (
    id                 bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_tenantsystems PRIMARY KEY,
    tenant_id          bigint      NOT NULL,
    type_system_sst_id bigint      NOT NULL,
    activated_at       timestamptz NOT NULL DEFAULT now(),
    deactivated_at     timestamptz,
    notes              varchar(300),
    is_active          boolean     NOT NULL DEFAULT true,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_tenantsystems_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenantsystems_type_system_sst_id
        FOREIGN KEY (type_system_sst_id) REFERENCES type_system_sst (id) ON DELETE RESTRICT,
    CONSTRAINT uq_tenantsystems_tenant_system UNIQUE (tenant_id, type_system_sst_id),
    CONSTRAINT uq_tenantsystems_id_tenant     UNIQUE (id, tenant_id)
);

COMMENT ON TABLE tenantsystems IS 'Sistemas de gestión (SST, PESV) que cada empresa tiene activos en la plataforma.';

-- =============================================================================
-- 12. tenant_modules — módulos habilitados por empresa                     §6.2
-- =============================================================================
CREATE TABLE tenant_modules (
    id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_tenant_modules PRIMARY KEY,
    tenant_id   bigint      NOT NULL,
    module_id   bigint      NOT NULL,
    enabled_at  timestamptz NOT NULL DEFAULT now(),
    disabled_at timestamptz,
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_tenant_modules_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenant_modules_module_id
        FOREIGN KEY (module_id) REFERENCES modules (id) ON DELETE RESTRICT,
    CONSTRAINT uq_tenant_modules_tenant_module UNIQUE (tenant_id, module_id),
    CONSTRAINT uq_tenant_modules_id_tenant     UNIQUE (id, tenant_id)
);

COMMENT ON TABLE tenant_modules IS 'Habilitación de módulos funcionales por empresa (licenciamiento/alcance).';

-- =============================================================================
-- 13. templates — catálogo maestro de plantillas (global)                  §7.1
-- =============================================================================
CREATE TABLE templates (
    id                 bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_templates PRIMARY KEY,
    type_system_sst_id bigint       NOT NULL,
    phva_stage_id      bigint       NOT NULL,
    code               varchar(30)  NOT NULL,
    name               varchar(200) NOT NULL,
    description        text,
    version            varchar(10)  NOT NULL DEFAULT '1.0',
    legal_reference    varchar(300),
    is_active          boolean      NOT NULL DEFAULT true,
    created_at         timestamptz  NOT NULL DEFAULT now(),
    updated_at         timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT fk_templates_type_system_sst_id
        FOREIGN KEY (type_system_sst_id) REFERENCES type_system_sst (id) ON DELETE RESTRICT,
    CONSTRAINT fk_templates_phva_stage_id
        FOREIGN KEY (phva_stage_id) REFERENCES phva_stages (id) ON DELETE RESTRICT,
    CONSTRAINT uq_templates_system_code_version UNIQUE (type_system_sst_id, code, version)
);

COMMENT ON TABLE templates IS 'Catálogo global de plantillas de documentos clasificadas por sistema de gestión y fase PHVA.';

-- =============================================================================
-- 14. formats_sst — formatos/archivos de una plantilla                     §7.2
-- =============================================================================
CREATE TABLE formats_sst (
    id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_formats_sst PRIMARY KEY,
    template_id bigint       NOT NULL,
    module_id   bigint       NOT NULL,
    code        varchar(30)  NOT NULL,
    name        varchar(200) NOT NULL,
    file_url    varchar(400) NOT NULL,
    mime_type   varchar(100) NOT NULL DEFAULT 'application/pdf',
    checksum    varchar(64),
    version     varchar(10)  NOT NULL,
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_formats_sst_template_id
        FOREIGN KEY (template_id) REFERENCES templates (id) ON DELETE RESTRICT,
    CONSTRAINT fk_formats_sst_module_id
        FOREIGN KEY (module_id) REFERENCES modules (id) ON DELETE RESTRICT,
    CONSTRAINT uq_formats_sst_template_code_version UNIQUE (template_id, code, version)
);

COMMENT ON TABLE formats_sst IS 'Formatos/archivos (PDF, XLSX, DOCX) asociados a una plantilla y a un módulo del mismo sistema.';
COMMENT ON COLUMN formats_sst.checksum IS 'Hash SHA-256 en hexadecimal para verificar la integridad del archivo.';

-- =============================================================================
-- 15. tenanttemplates — plantilla asignada a una empresa                   §8.1
-- =============================================================================
CREATE TABLE tenanttemplates (
    id                     bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_tenanttemplates PRIMARY KEY,
    tenant_id              bigint      NOT NULL,
    template_id            bigint      NOT NULL,
    assigned_at            timestamptz NOT NULL DEFAULT now(),
    due_date               date,
    responsible_person_id  bigint,
    assigned_by_person_id  bigint,
    notes                  varchar(300),
    is_active              boolean     NOT NULL DEFAULT true,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_tenanttemplates_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenanttemplates_template_id
        FOREIGN KEY (template_id) REFERENCES templates (id) ON DELETE RESTRICT,
    -- FK compuestas: responsable y quien asigna pertenecen a la misma empresa (§3.2)
    CONSTRAINT fk_tenanttemplates_responsible_person_id_tenant_id
        FOREIGN KEY (responsible_person_id, tenant_id) REFERENCES persons (id, tenant_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenanttemplates_assigned_by_person_id_tenant_id
        FOREIGN KEY (assigned_by_person_id, tenant_id) REFERENCES persons (id, tenant_id) ON DELETE RESTRICT,
    CONSTRAINT uq_tenanttemplates_tenant_template UNIQUE (tenant_id, template_id),
    CONSTRAINT uq_tenanttemplates_id_tenant       UNIQUE (id, tenant_id)
);

COMMENT ON TABLE tenanttemplates IS 'Asignación de una plantilla global a una empresa, con responsable y fecha límite.';

-- =============================================================================
-- 16. documents — instancia diligenciable con estado                       §9.1
-- =============================================================================
CREATE TABLE documents (
    id               bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_documents PRIMARY KEY,
    tenanttemplate_id bigint      NOT NULL,
    version          smallint     NOT NULL DEFAULT 1,
    title            varchar(200) NOT NULL,
    state            varchar(20)  NOT NULL DEFAULT 'no_iniciado',
    content          jsonb,
    file_url         varchar(400),
    started_at       timestamptz,
    finished_at      timestamptz,
    is_active        boolean     NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_documents_tenanttemplate_id
        FOREIGN KEY (tenanttemplate_id) REFERENCES tenanttemplates (id) ON DELETE RESTRICT,
    CONSTRAINT uq_documents_tenanttemplate_version UNIQUE (tenanttemplate_id, version),
    CONSTRAINT ck_documents_state CHECK (state IN ('no_iniciado', 'borrador', 'finalizado')),
    -- Reglas de estado de §9.1
    CONSTRAINT ck_documents_state_no_iniciado
        CHECK (state <> 'no_iniciado' OR (started_at IS NULL AND finished_at IS NULL AND content IS NULL)),
    CONSTRAINT ck_documents_state_borrador
        CHECK (state <> 'borrador' OR (started_at IS NOT NULL AND finished_at IS NULL)),
    CONSTRAINT ck_documents_state_finalizado
        CHECK (state <> 'finalizado' OR (started_at IS NOT NULL AND finished_at IS NOT NULL)),
    CONSTRAINT ck_documents_finished_at
        CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at),
    -- Regla declarativa de §12.4: el contenido es obligatorio al finalizar
    CONSTRAINT ck_documents_state_finalizado_content
        CHECK (state <> 'finalizado' OR content IS NOT NULL),
    -- El contenido diligenciado debe ser un objeto JSON (respuestas de formulario, §9.1)
    CONSTRAINT ck_documents_content_object
        CHECK (content IS NULL OR jsonb_typeof(content) = 'object')
);

COMMENT ON TABLE documents IS 'Instancia diligenciable de cada plantilla asignada, con estado no_iniciado, borrador o finalizado.';
COMMENT ON COLUMN documents.version IS 'Número de versión del documento; una reapertura crea una versión nueva y conserva el histórico.';
COMMENT ON COLUMN documents.state IS 'Estado de avance: no_iniciado, borrador o finalizado; las transiciones solo avanzan.';
COMMENT ON COLUMN documents.content IS 'Respuestas del formulario en JSON; nulo mientras el estado es no_iniciado.';
COMMENT ON COLUMN documents.started_at IS 'Marca de tiempo fijada al pasar el documento a borrador.';
COMMENT ON COLUMN documents.finished_at IS 'Marca de tiempo fijada al finalizar el documento; debe ser mayor o igual a started_at.';

-- =============================================================================
-- 17. evaluations — mediciones de cumplimiento                             §9.2
-- =============================================================================
CREATE TABLE evaluations (
    id                  bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_evaluations PRIMARY KEY,
    tenant_id           bigint        NOT NULL,
    template_id         bigint        NOT NULL,
    evaluation_date     date          NOT NULL,
    score               numeric(5,2),
    max_score           numeric(5,2)  NOT NULL DEFAULT 100,
    evaluator_person_id bigint,
    observations        text,
    is_active           boolean       NOT NULL DEFAULT true,
    created_at          timestamptz   NOT NULL DEFAULT now(),
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT fk_evaluations_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluations_template_id
        FOREIGN KEY (template_id) REFERENCES templates (id) ON DELETE RESTRICT,
    -- FK compuesta: el evaluador pertenece a la misma empresa (§3.2)
    CONSTRAINT fk_evaluations_evaluator_person_id_tenant_id
        FOREIGN KEY (evaluator_person_id, tenant_id) REFERENCES persons (id, tenant_id) ON DELETE RESTRICT,
    CONSTRAINT uq_evaluations_tenant_template_date UNIQUE (tenant_id, template_id, evaluation_date),
    CONSTRAINT ck_evaluations_max_score CHECK (max_score > 0),
    CONSTRAINT ck_evaluations_score CHECK (score IS NULL OR (score >= 0 AND score <= max_score))
);

COMMENT ON TABLE evaluations IS 'Medición de cumplimiento de una empresa sobre una plantilla, con puntaje y evaluador.';
COMMENT ON COLUMN evaluations.score IS 'Puntaje obtenido entre 0 y max_score; nulo mientras la medición no se cierra.';

-- =============================================================================
-- 18. editing_locks — bloqueos de edición concurrente                      §9.3
-- =============================================================================
CREATE TABLE editing_locks (
    id                   bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_editing_locks PRIMARY KEY,
    document_id          bigint      NOT NULL,
    locked_by_person_id  bigint      NOT NULL,
    lock_token           uuid        NOT NULL,
    locked_at            timestamptz NOT NULL DEFAULT now(),
    expires_at           timestamptz NOT NULL,
    released_at          timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_editing_locks_document_id
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE RESTRICT,
    CONSTRAINT fk_editing_locks_locked_by_person_id
        FOREIGN KEY (locked_by_person_id) REFERENCES persons (id) ON DELETE RESTRICT,
    CONSTRAINT uq_editing_locks_lock_token UNIQUE (lock_token),
    CONSTRAINT ck_editing_locks_expires_at  CHECK (expires_at > locked_at),
    CONSTRAINT ck_editing_locks_released_at CHECK (released_at IS NULL OR released_at >= locked_at)
);

-- Índice único parcial: un solo bloqueo vigente por documento (§9.3);
-- los bloqueos históricos (released_at NOT NULL) se conservan sin restricción.
CREATE UNIQUE INDEX uq_editing_locks_document_active
    ON editing_locks (document_id)
    WHERE released_at IS NULL;

COMMENT ON TABLE editing_locks IS 'Bloqueos de edición concurrente sobre documentos, con caducidad y liberación.';
COMMENT ON COLUMN editing_locks.lock_token IS 'Token entregado al cliente; evita liberar un bloqueo desde otra sesión.';
COMMENT ON COLUMN editing_locks.expires_at IS 'Caducidad obligatoria del bloqueo, renovable por heartbeat del cliente.';
COMMENT ON COLUMN editing_locks.released_at IS 'Nulo = bloqueo vigente; con valor, bloqueo liberado (histórico conservado).';

-- =============================================================================
-- 19. audit_log — auditoría genérica append-only                           §10.1
-- =============================================================================
CREATE TABLE audit_log (
    id                   bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_audit_log PRIMARY KEY,
    tenant_id            bigint,
    table_name           varchar(63) NOT NULL,
    record_pk            text        NOT NULL,
    operation            char(1)     NOT NULL,
    changed_at           timestamptz NOT NULL DEFAULT now(),
    changed_by_person_id bigint,
    db_user              varchar(63) NOT NULL,
    application_name     varchar(63),
    client_addr          inet,
    request_id           uuid,
    changed_columns      text[],
    old_values           jsonb,
    new_values           jsonb,
    extra_context        jsonb,
    CONSTRAINT fk_audit_log_tenant_id
        FOREIGN KEY (tenant_id) REFERENCES tenants (id) ON DELETE RESTRICT,
    CONSTRAINT ck_audit_log_operation CHECK (operation IN ('I', 'U', 'D'))
);

COMMENT ON TABLE audit_log IS 'Bitácora genérica e inmutable de cambios de datos, agnóstica al esquema y con tenant opcional.';
COMMENT ON COLUMN audit_log.record_pk IS 'Clave primaria serializada del registro afectado; soporta PK compuestas.';

COMMIT;
