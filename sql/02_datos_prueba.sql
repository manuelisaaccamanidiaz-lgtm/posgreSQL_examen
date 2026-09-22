-- =============================================================================
-- 02_datos_prueba.sql — Datos de prueba para demostrar consultas, vistas,
-- procedimientos, funciones y triggers del examen.
-- Base: PostgreSQL. Ejecutar DESPUÉS de 01_schema.sql (y ANTES de 03..09).
--
-- Contenido y escenarios cubiertos:
--   * Catálogos: 3 países, 8 departamentos, 22 ciudades (Santander completo),
--     2 sistemas (SST/PESV), 4 etapas PHVA, 4 tamaños, 12 módulos (8 SST +
--     4 PESV; MO_PCAP sin asignar), 25 plantillas, 28 formatos.
--   * 20 organizaciones (17 activas, 3 inactivas) con created_at entre 2025
--     y 2026 (incluye 2026-06-30 18:00 y 2026-07-01 00:00).
--   * 74 cargos (≈12 sin personas; ocupaciones 1/2/3/4/5 con empates).
--   * 77 personas (~14 % sin email, ~12 % inactivas; CC/CE/TI/PA/PPT;
--     hire_date 2019–2026 con fechas repetidas).
--   * 23 habilitaciones de sistema y 51 de módulos (t1 con TODOS los SST,
--     t2 y t6 con TODOS los PESV; una organización sin sistemas; una inactiva
--     con módulos aún habilitados; dos organizaciones con módulos pero sin
--     plantillas asignadas).
--   * 45 asignaciones de plantillas, 46 documentos (43 vigentes: 19
--     finalizados, 13 borrador, 11 no iniciado; 3 versiones históricas),
--     13 evaluaciones, 9 bloqueos (4 vigentes, 4 liberados, 1 vencido sin
--     liberar), 7 filas de auditoría.
--
-- Reglas: sin ids literales (FK por clave natural con subconsultas/CTE);
-- sin SELECT *; re-ejecutable (TRUNCATE ... RESTART IDENTITY CASCADE).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Limpieza (orden inverso de dependencias; CASCADE cubre las FK compuestas)
-- -----------------------------------------------------------------------------
TRUNCATE TABLE audit_log, editing_locks, evaluations, documents, tenanttemplates,
               formats_sst, templates, tenant_modules, tenantsystems, persons,
               positions, tenants, cities, departments, modules, countries,
               tenant_sizes, phva_stages, type_system_sst
RESTART IDENTITY CASCADE;

-- =============================================================================
-- 1. CATÁLOGOS GLOBALES
-- =============================================================================

INSERT INTO countries (iso_code, iso_code3, name, phone_prefix, is_active, created_at) VALUES
('CO', 'COL', 'Colombia',            '+57', true, '2025-01-05 09:00-05'),
('PE', 'PER', 'Perú',                '+51', true, '2025-01-05 09:05-05'),
('MX', 'MEX', 'México',              '+52', true, '2025-01-05 09:10-05');

INSERT INTO departments (country_id, code, name, is_active, created_at)
SELECT co.id, v.code, v.name, true, '2025-01-06 08:00-05'
FROM (VALUES
    ('CO', 'SANT', 'Santander'),
    ('CO', 'CUND', 'Cundinamarca'),
    ('CO', 'ANT',  'Antioquia'),
    ('CO', 'NORTE','Norte de Santander'),
    ('CO', 'VALL', 'Valle del Cauca'),
    ('CO', 'QUI',  'Quindío'),
    ('CO', 'MET',  'Meta'),
    ('PE', 'LMA',  'Lima')
) AS v(country_iso, code, name)
INNER JOIN countries AS co ON co.iso_code = v.country_iso;

INSERT INTO cities (department_id, code, name, is_active, created_at)
SELECT d.id, v.code, v.name, true, '2025-01-06 08:30-05'
FROM (VALUES
    ('SANT',  '68001', 'Bucaramanga'),
    ('SANT',  '68271', 'Floridablanca'),
    ('SANT',  '68307', 'Girón'),
    ('SANT',  '68573', 'Piedecuesta'),
    ('SANT',  '68132', 'Barrancabermeja'),     -- sin organizaciones
    ('CUND',  '11001', 'Bogotá D.C.'),
    ('CUND',  '25175', 'Chía'),                -- sin organizaciones
    ('CUND',  '25286', 'Cota'),                -- sin organizaciones
    ('ANT',   '05001', 'Medellín'),
    ('ANT',   '05615', 'Itagüí'),
    ('NORTE', '54001', 'Cúcuta'),
    ('NORTE', '54344', 'Pamplona'),            -- sin organizaciones
    ('VALL',  '76001', 'Cali'),
    ('VALL',  '76111', 'Palmira'),
    ('QUI',   '63001', 'Armenia'),
    ('QUI',   '63401', 'Calarcá'),             -- sin organizaciones
    ('MET',   '50001', 'Villavicencio'),
    ('MET',   '50573', 'Puerto López'),        -- sin organizaciones
    ('LMA',   '15001', 'Lima'),
    ('LMA',   '15012', 'Miraflores'),
    ('LMA',   '15013', 'San Isidro')
) AS v(dep_code, code, name)
INNER JOIN departments AS d ON d.code = v.dep_code;

INSERT INTO type_system_sst (code, name, description, legal_basis, is_active, created_at) VALUES
('SST', 'Sistema de Gestión de Seguridad y Salud en el Trabajo',
 'Gestión de peligros, riesgos y cumplimiento del Decreto 1072 de 2015.',
 'Decreto 1072 de 2015; Resolución 0312 de 2019', true, '2025-01-07 08:00-05'),
('PESV', 'Plan Estratégico de Seguridad Vial',
 'Gestión del riesgo vial de las actividades de transporte de la organización.',
 'Resolución 40595 de 2022 (Ministerio de Transporte)', true, '2025-01-07 08:05-05');

INSERT INTO phva_stages (code, name, description, sort_order, is_active, created_at) VALUES
('P', 'Planear',   'Diagnóstico, política, objetivos y programación.',        1, true, '2025-01-07 08:10-05'),
('H', 'Hacer',     'Identificación de peligros, evaluación y control.',       2, true, '2025-01-07 08:11-05'),
('V', 'Verificar', 'Inspecciones, mediciones, auditorías e indicadores.',     3, true, '2025-01-07 08:12-05'),
('A', 'Actuar',    'Revisión por la dirección y mejoramiento continuo.',      4, true, '2025-01-07 08:13-05');

INSERT INTO tenant_sizes (code, name, min_employees, max_employees, description, sort_order, is_active, created_at) VALUES
('MICRO', 'Microempresa',     1,   10,   'Hasta 10 trabajadores.',                  1, true, '2025-01-07 08:20-05'),
('PEQ',   'Pequeña empresa',  11,  50,   'Entre 11 y 50 trabajadores.',             2, true, '2025-01-07 08:20-05'),
('MED',   'Mediana empresa',  51,  200,  'Entre 51 y 200 trabajadores.',            3, true, '2025-01-07 08:20-05'),
('GRA',   'Gran empresa',     201, NULL, 'Más de 200 trabajadores (rango abierto).',4, true, '2025-01-07 08:20-05');

-- Módulos: 8 de SST (MO_PCAP queda SIN asignar a ninguna organización)
INSERT INTO modules (type_system_sst_id, code, title, description, sort_order, is_active, created_at)
SELECT s.id, v.code, v.title, v.description, v.sort_order, true, '2025-01-08 08:00-05'
FROM (VALUES
    ('SST', 'MO_POL_PROG',  'Planeación y Política',           'Política, objetivos y programación anual.', 1),
    ('SST', 'MO_MFG_RISK',  'Matriz de Peligros y Riesgos',    'Identificación, evaluación y valoración.',  2),
    ('SST', 'MO_MGMT_GEN',  'Gestión General',                 'Actividades generales del SG-SST.',         3),
    ('SST', 'MO_INSP_PROG', 'Inspecciones Programadas',        'Inspecciones planeadas y reportes.',        4),
    ('SST', 'MO_INC_INV',   'Investigación de Incidentes',     'Investigación de accidentes e incidentes.', 5),
    ('SST', 'MO_INT_AUD',   'Auditorías Internas',             'Programa y ejecución de auditorías.',       6),
    ('SST', 'MO_MGMT_REV',  'Revisión por la Dirección',       'Revisión y mejoramiento continuo.',         7),
    ('SST', 'MO_PCAP',      'Plan de Capacitación',            'Necesidades y ejecución de capacitación.',  8),
    ('PESV','MO_POL_VIAL',  'Planeación Vial',                 'Política y objetivos del PESV.',            1),
    ('PESV','MO_HAZ_VIAL',  'Gestión del Riesgo Vial',         'Diagnóstico y plan anual de seguridad vial.',2),
    ('PESV','MO_REV_VEH',   'Revisión Vehicular',              'Inspecciones y mantenimiento de flota.',    3),
    ('PESV','MO_MFG_VIAL',  'Indicadores Viales',              'Seguimiento e indicadores del PESV.',       4)
) AS v(system_code, code, title, description, sort_order)
INNER JOIN type_system_sst AS s ON s.code = v.system_code;

-- Plantillas: 13 SST (P:3, H:3, V:5, A:3) y 12 PESV (P:2, H:4, V:4, A:2)
INSERT INTO templates (type_system_sst_id, phva_stage_id, code, name, description, version, legal_reference, is_active, created_at)
SELECT s.id, ph.id, v.code, v.name, v.description, v.version, v.legal_reference, true, '2025-02-01 08:00-05'
FROM (VALUES
    ('SST','P','TEM_POLITICA_SST',    'Política de Seguridad y Salud en el Trabajo', 'Documento de política del SG-SST.',        '2.0', 'Decreto 1072 de 2015, art. 2.2.4.6.22'),
    ('SST','P','TEM_POLITICA_SST_V1', 'Política SG-SST (versión inicial)',           'Primera versión histórica de la política.','1.0', 'Decreto 1072 de 2015, art. 2.2.4.6.22'),
    ('SST','P','TEM_OBJETIVOS_SST',   'Programa y Objetivos del SG-SST',             'Objetivos, metas y programa anual.',       '1.0', 'Resolución 0312 de 2019'),
    ('SST','H','TEM_IDENT_PELIGROS',  'Identificación de Peligros',                  'Metodología de identificación de peligros.','1.0','GTC 45'),
    ('SST','H','TEM_MAPA_RIESGOS',    'Matriz de Riesgos',                           'Valoración y mapa de riesgos.',            '1.0', 'GTC 45'),
    ('SST','H','TEM_PLAN_EMERGENCIAS','Plan de Emergencias',                         'Brigadas, rutas y simulacros.',            '1.0', 'Decreto 1072 de 2015'),
    ('SST','V','TEM_INSP_PLANEADA',   'Inspecciones Planeadas',                      'Formatos y reportes de inspección.',       '1.0', 'Resolución 0312 de 2019'),
    ('SST','V','TEM_INVEST_ACCID',    'Investigación de Accidentes',                 'Reporte e investigación de accidentes.',   '1.0', 'Decreto 1072 de 2015'),
    ('SST','V','TEM_AUD_INTERNA',     'Auditoría Interna',                           'Plan y reporte de auditoría interna.',     '1.0', 'Decreto 1072 de 2015'),
    ('SST','V','TEM_INDICADORES',     'Indicadores del SG-SST',                      'Tablero de indicadores de gestión.',       '1.0', 'Resolución 0312 de 2019'),
    ('SST','V','TEM_REP_INSPEC_EQ',   'Inspección de Equipos',                       'Inspección de equipos y herramientas.',    '1.0', 'Resolución 0312 de 2019'),
    ('SST','A','TEM_REV_DIRECCION',   'Revisión por la Dirección',                   'Acta de revisión por la dirección.',       '1.0', 'Decreto 1072 de 2015'),
    ('SST','A','TEM_PLAN_MEJORA',     'Plan de Mejoramiento',                        'Acciones correctivas y de mejora.',        '1.0', 'Decreto 1072 de 2015'),
    ('SST','A','TEM_COMITE_VIGIA',    'Comité y Vigías SST',                         'Actas del comité y reportes de vigías.',   '1.0', 'Resolución 2346 de 2016'),
    ('PESV','P','TEM_POLITICA_PESV',  'Política de Seguridad Vial',                  'Política del PESV.',                       '1.0', 'Resolución 40595 de 2022'),
    ('PESV','P','TEM_OBJETIVOS_PESV', 'Objetivos del PESV',                          'Objetivos y metas viales.',                '1.0', 'Resolución 40595 de 2022'),
    ('PESV','H','TEM_DIAG_PESV',      'Diagnóstico de Gestión Vial',                 'Diagnóstico inicial del PESV.',            '1.0', 'Resolución 40595 de 2022'),
    ('PESV','H','TEM_PLAN_ANUAL',     'Plan Estratégico de Seguridad Vial',          'Plan anual de trabajo vial.',              '1.0', 'Resolución 40595 de 2022'),
    ('PESV','H','TEM_MANTENIMIENTO',  'Plan de Mantenimiento',                       'Mantenimiento preventivo de flota.',       '1.0', 'Resolución 40595 de 2022'),
    ('PESV','H','TEM_CAPACITACIONES', 'Plan de Capacitación Vial',                   'Capacitaciones en seguridad vial.',        '1.0', 'Resolución 40595 de 2022'),
    ('PESV','V','TEM_INSP_VEHICULAR', 'Inspección Vehicular',                        'Listas de chequeo vehicular.',             '1.0', 'Resolución 40595 de 2022'),
    ('PESV','V','TEM_HORAS_SEGURAS',  'Horas de Manejo Seguras',                     'Control de horas y descanso.',             '1.0', 'Resolución 40595 de 2022'),
    ('PESV','V','TEM_INVEST_EVENTOS', 'Investigación de Eventos Viales',             'Investigación de incidentes viales.',      '1.0', 'Resolución 40595 de 2022'),
    ('PESV','V','TEM_IND_PESV',       'Indicadores del PESV',                        'Tablero de indicadores viales.',           '1.0', 'Resolución 40595 de 2022'),
    ('PESV','A','TEM_REV_PESV',       'Revisión del PESV',                           'Revisión anual del PESV.',                 '1.0', 'Resolución 40595 de 2022'),
    ('PESV','A','TEM_MEJORA_PESV',    'Plan de Mejoramiento Vial',                   'Mejoramiento del PESV.',                   '1.0', 'Resolución 40595 de 2022')
) AS v(system_code, stage_code, code, name, description, version, legal_reference)
INNER JOIN type_system_sst AS s  ON s.code  = v.system_code
INNER JOIN phva_stages     AS ph ON ph.code = v.stage_code;

-- Formatos: 23 explícitos (módulo SIEMPRE del mismo sistema que la plantilla)
INSERT INTO formats_sst (template_id, module_id, code, name, file_url, mime_type, checksum, version, is_active, created_at)
SELECT tp.id, m.id, v.code, v.name, v.file_url, v.mime_type, md5(v.code), v.version, true, '2025-02-05 08:00-05'
FROM (VALUES
    ('SST','TEM_POLITICA_SST',    'MO_POL_PROG',  'F-POL-01',  'Formato de política firmada',            'https://files.sstplatform.co/formatos/politica/f-pol-01.pdf',  'application/pdf', '2.0'),
    ('SST','TEM_OBJETIVOS_SST',   'MO_POL_PROG',  'F-OBJ-01',  'Matriz de objetivos e indicadores',      'https://files.sstplatform.co/formatos/politica/f-obj-01.xlsx', 'application/vnd.ms-excel', '1.0'),
    ('SST','TEM_IDENT_PELIGROS',  'MO_MFG_RISK',  'F-IDEN-01', 'Reporte de identificación de peligros',  'https://files.sstplatform.co/formatos/riesgos/f-iden-01.xlsx', 'application/vnd.ms-excel', '1.0'),
    ('SST','TEM_MAPA_RIESGOS',    'MO_MFG_RISK',  'F-MAP-01',  'Matriz de riesgos GTC 45',               'https://files.sstplatform.co/formatos/riesgos/f-map-01.xlsx',  'application/vnd.ms-excel', '1.0'),
    ('SST','TEM_PLAN_EMERGENCIAS','MO_MGMT_GEN',  'F-EME-01',  'Plan de emergencias y brigadas',         'https://files.sstplatform.co/formatos/gestion/f-eme-01.pdf',   'application/pdf', '1.0'),
    ('SST','TEM_INSP_PLANEADA',   'MO_INSP_PROG', 'F-INS-01',  'Lista de chequeo de inspección',         'https://files.sstplatform.co/formatos/inspeccion/f-ins-01.xlsx','application/vnd.ms-excel', '1.0'),
    ('SST','TEM_INSP_PLANEADA',   'MO_INSP_PROG', 'F-INS-02',  'Reporte de hallazgos de inspección',     'https://files.sstplatform.co/formatos/inspeccion/f-ins-02.xlsx','application/vnd.ms-excel', '1.0'),
    ('SST','TEM_INVEST_ACCID',    'MO_INC_INV',   'F-ACC-01',  'Formato de investigación de accidentes', 'https://files.sstplatform.co/formatos/incidentes/f-acc-01.pdf','application/pdf', '1.0'),
    ('SST','TEM_AUD_INTERNA',     'MO_INT_AUD',   'F-AUD-01',  'Plan de auditoría interna',              'https://files.sstplatform.co/formatos/auditoria/f-aud-01.pdf', 'application/pdf', '1.0'),
    ('SST','TEM_INDICADORES',     'MO_INT_AUD',   'F-IND-01',  'Tablero de indicadores SG-SST',          'https://files.sstplatform.co/formatos/auditoria/f-ind-01.xlsx','application/vnd.ms-excel', '1.0'),
    ('SST','TEM_REV_DIRECCION',   'MO_MGMT_REV',  'F-REV-01',  'Acta de revisión por la dirección',      'https://files.sstplatform.co/formatos/revision/f-rev-01.pdf',  'application/pdf', '1.0'),
    ('SST','TEM_PLAN_MEJORA',     'MO_MGMT_REV',  'F-MEJ-01',  'Formato de plan de mejoramiento',        'https://files.sstplatform.co/formatos/revision/f-mej-01.xlsx', 'application/vnd.ms-excel', '1.0'),
    ('SST','TEM_COMITE_VIGIA',    'MO_MGMT_REV',  'F-COM-01',  'Acta de comité paritario SST',           'https://files.sstplatform.co/formatos/revision/f-com-01.pdf',  'application/pdf', '1.0'),
    ('SST','TEM_REP_INSPEC_EQ',   'MO_MGMT_REV',  'F-REI-01',  'Inspección de equipos y herramientas',   'https://files.sstplatform.co/formatos/revision/f-rei-01.pdf',  'application/pdf', '1.0'),
    ('PESV','TEM_POLITICA_PESV',  'MO_POL_VIAL',  'F-PES-01',  'Formato de política vial firmada',       'https://files.sstplatform.co/formatos/pesv/f-pes-01.pdf',      'application/pdf', '1.0'),
    ('PESV','TEM_OBJETIVOS_PESV', 'MO_POL_VIAL',  'F-OBJP-01', 'Matriz de objetivos viales',             'https://files.sstplatform.co/formatos/pesv/f-objp-01.xlsx',    'application/vnd.ms-excel', '1.0'),
    ('PESV','TEM_DIAG_PESV',      'MO_HAZ_VIAL',  'F-DIAG-01', 'Diagnóstico de gestión vial',            'https://files.sstplatform.co/formatos/pesv/f-diag-01.xlsx',    'application/vnd.ms-excel', '1.0'),
    ('PESV','TEM_PLAN_ANUAL',     'MO_HAZ_VIAL',  'F-PAN-01',  'Plan anual de seguridad vial',           'https://files.sstplatform.co/formatos/pesv/f-pan-01.xlsx',     'application/vnd.ms-excel', '1.0'),
    ('PESV','TEM_MANTENIMIENTO',  'MO_HAZ_VIAL',  'F-MANT-01', 'Programa de mantenimiento de flota',     'https://files.sstplatform.co/formatos/pesv/f-mant-01.xlsx',    'application/vnd.ms-excel', '1.0'),
    ('PESV','TEM_CAPACITACIONES', 'MO_HAZ_VIAL',  'F-CAP-01',  'Registro de capacitaciones viales',      'https://files.sstplatform.co/formatos/pesv/f-cap-01.xlsx',     'application/vnd.ms-excel', '1.0'),
    ('PESV','TEM_INSP_VEHICULAR', 'MO_REV_VEH',   'F-IVE-01',  'Lista de chequeo vehicular',             'https://files.sstplatform.co/formatos/pesv/f-ive-01.pdf',      'application/pdf', '1.0'),
    ('PESV','TEM_HORAS_SEGURAS',  'MO_REV_VEH',   'F-HSE-01',  'Control de horas de manejo',             'https://files.sstplatform.co/formatos/pesv/f-hse-01.xlsx',     'application/vnd.ms-excel', '1.0'),
    ('PESV','TEM_INVEST_EVENTOS', 'MO_MFG_VIAL',  'F-IEV-01',  'Investigación de eventos viales',        'https://files.sstplatform.co/formatos/pesv/f-iev-01.pdf',      'application/pdf', '1.0')
) AS v(system_code, template_code, module_code, code, name, file_url, mime_type, version)
INNER JOIN templates AS tp ON tp.code = v.template_code
INNER JOIN modules   AS m  ON m.code  = v.module_code
INNER JOIN type_system_sst AS s ON s.id = m.type_system_sst_id AND s.id = tp.type_system_sst_id
                          AND s.code = v.system_code;

-- Formatos restantes por volumen (mismo sistema que su plantilla; el módulo
-- se deduce por el número dentro de la plantilla). Deja plantilla sin formatos
-- (TEM_POLITICA_SST_V1) y módulo sin formatos (MO_PCAP).
INSERT INTO formats_sst (template_id, module_id, code, name, file_url, version, created_at)
SELECT tp.id,
       m.id,
       'F-INS-0' || (2 + n) || '-' || tp.id,
       'Formato adicional de inspección #' || n,
       'https://files.sstplatform.co/formatos/inspeccion/extra-' || n || '.xlsx',
       '1.' || (2 + n),
       '2025-02-10 08:00-05'
FROM templates AS tp
CROSS JOIN generate_series(1, 2) AS n
INNER JOIN modules AS m ON m.code = 'MO_INSP_PROG' AND m.type_system_sst_id = tp.type_system_sst_id
WHERE tp.code = 'TEM_INSP_PLANEADA';

INSERT INTO formats_sst (template_id, module_id, code, name, file_url, version, created_at)
SELECT tp.id, m.id, 'F-INDP-01', 'Tablero de indicadores del PESV',
       'https://files.sstplatform.co/formatos/pesv/f-indp-01.xlsx', '1.0', '2025-02-10 08:05-05'
FROM templates AS tp
INNER JOIN modules AS m ON m.code = 'MO_MFG_VIAL' AND m.type_system_sst_id = tp.type_system_sst_id
WHERE tp.code = 'TEM_IND_PESV';

-- =============================================================================
-- 2. ORGANIZACIONES (20)
--    t1/t2 empatadas con 15 personas; t15/t16 sin personas (t18 sin personas
--    e inactiva); t17/t18/t19 inactivas (t18 conserva módulos); misma ciudad
--    con distinto tamaño (t3/t7 en Bucaramanga) y con el mismo tamaño
--    (t4/t9 en Floridablanca); created_at 2025–2026 con frontera 30/06–01/07.
-- =============================================================================

WITH new_tenants AS (
    INSERT INTO tenants (tenant_size_id, city_id, legal_name, trade_name, tax_id,
                         check_digit, email, phone, address, contact_name, contact_email,
                         slug, is_active, created_at, updated_at)
    SELECT ts.id, c.id, v.legal_name, v.trade_name, v.tax_id, v.check_digit,
           v.email, v.phone, v.address, v.contact_name, v.contact_email,
           v.slug, v.is_active, v.created_at::timestamptz, v.created_at::timestamptz
    FROM (VALUES
        ('GRA',   'Bucaramanga',   'Andes Construcciones S.A.S.',       'Andes Construcciones',     '900123456',  '1', 'contacto@andesconstrucciones.co',   '6076854100', 'Calle 45 # 29-31', 'Laura Gómez',       'gerencia@andesconstrucciones.co', 'andes-construcciones',   true,  '2025-01-15 10:00-05'),
        ('GRA',   'Villavicencio', 'Petrolera Llanos S.A.',             'Petrolera Llanos',         '830112233',  '4', 'gerencia@petrolerallanos.com.co',   '6017442200', 'Vía Puerto López km 15', 'Pedro Ramírez', 'coordinacion@petrolerallanos.com.co', 'petrolera-llanos', true, '2025-02-20 09:30-05'),
        ('MED',   'Bucaramanga',   'Metales del Caribe S.A.S.',         'Metacaribe',               '901234567',  '8', 'info@metacaribe.co',                '6076301122', 'Zona Industrial Norte', 'Carlos Cárdenas', 'sst@metacaribe.co',      'metales-caribe',         true,  '2025-03-12 14:00-05'),
        ('MED',   'Floridablanca', 'Alimentos Santander S.A.S.',        'Alisantander',             '902345678',  '3', 'contacto@alisantander.co',          '6076789012', 'Cra 9 # 45-02', 'Martha Peña',       'calidad@alisantander.co',        'alimentos-santander',    true,  '2025-04-18 11:15-05'),
        ('MED',   'Cúcuta',        'Textiles del Norte S.A.S.',         'Texnorte',                 '903456789',  '5', 'gerencia@texnorte.co',              '6075802233', 'Av. Los Libertadores', 'Julián Ospina','sst@texnorte.co',               'textiles-norte',         true,  '2025-05-25 16:40-05'),
        ('MED',   'Bogotá D.C.',   'Transportes Andinos S.A.S.',        'Transandinos',             '904567890',  '9', 'operaciones@transandinos.co',       '6014567890', 'Zona Portuaria', 'Diana Nieto',       'pesv@transandinos.co',           'transportes-andinos',    true,  '2026-06-30 18:00-05'),
        ('GRA',   'Bucaramanga',   'Clínica Vitalis Bucaramanga S.A.',  'Clínica Vitalis',          '905678901',  '2', 'direccion@clinicavitalis.co',       '6076543210', 'Cra 33 # 48-20', 'Fernando Vargas',   'calidad@clinicavitalis.co',      'clinica-vitalis',        true,  '2026-07-01 00:00-05'),
        ('PEQ',   'Armenia',       'Agroindustrias del Café S.A.S.',    'Agrocafé',                 '906789012',  '6', 'admin@agrocafe.co',                 '6067412345', 'Vereda La Tebaida', 'Óscar Arias',  'sst@agrocafe.co',                'agroindustrias-cafe',    true,  '2026-01-10 08:20-05'),
        ('PEQ',   'Floridablanca', 'Constructora Cívica S.A.S.',        'Civica',                   '907890123',  '7', 'proyectos@civica.co',               '6076912345', 'Calle 37 # 12-40', 'Liliana Rojas', 'sst@civica.co',                  'constructora-civica',    true,  '2026-01-20 09:00-05'),
        ('PEQ',   'Bogotá D.C.',   'Distribuidora Café Soft Ltda.',     'Café Soft',                '908901234',  '0', 'ventas@cafesoft.co',                '6013216549', 'Calle 100 # 19-54', 'Andrés Villegas','sst@cafesoft.co',              'distribuidora-cafe-soft',true,  '2026-01-28 13:30-05'),
        ('PEQ',   'Medellín',      'Lácteos La Pradera S.A.S.',         'La Pradera',               '909012345',  '1', 'gerencia@lacteospradera.co',        '6042887766', 'Vereda San Cristóbal', 'Camilo Hoyos', 'sst@lacteospradera.co',        'lacteos-pradera',        true,  '2026-02-05 10:45-05'),
        ('MICRO', 'Bucaramanga',   'Comercializadora Andina Ltda.',     'Comandina',                '900112233',  '5', 'comercial@comandina.co',            '6076123456', 'Cra 27 # 36-09', 'Paola Cárdenas',    'sst@comandina.co',               'comercializadora-andina',true,  '2026-02-14 15:00-05'),
        ('MICRO', 'Medellín',      'Servicios Mineros del Alto S.A.S.', 'Sermialto',                '900223344',  '6', 'contacto@sermialto.co',             '6043221188', 'Vereda San Félix', 'Jairo Cuesta',  'sst@sermialto.co',               'servicios-mineros-alto', true,  '2026-02-22 11:20-05'),
        ('MICRO', 'Cali',          'Fríos del Valle S.A.S.',            'Friosvalle',               '900334455',  '7', 'operaciones@friosvalle.co',         '6025567890', 'Zona Industrial Acopi', 'Sandra Ibáñez','sst@friosvalle.co',            'frios-del-valle',        true,  '2026-03-03 09:50-05'),
        ('MICRO', 'Bogotá D.C.',   'Consultores SST Elite S.A.S.',      'SST Elite',                '900445566',  '8', 'contacto@sstelite.co',              '6017894561', 'Cra 11 # 93-46', 'Ricardo Franco',    'gerencia@sstelite.co',           'consultores-sst-elite',  true,  '2026-03-12 14:35-05'),
        ('MICRO', 'Bogotá D.C.',   'Logística Ferrico S.A.S.',          'Ferrico',                  '900556677',  '9', 'operaciones@ferrico.co',            '6016549873', 'Puente Aranda', 'Valeria Nieto',     'pesv@ferrico.co',                'logistica-ferrico',      true,  '2026-03-21 08:10-05'),
        ('PEQ',   'Cartagena',     'Hotel Casa Real S.A.',              'Hotel Casa Real',          '800123456',  '3', 'reservas@hotelcasareal.co',         '6056601234', 'Bocagrande', 'Elena Sáenz',           'sst@hotelcasareal.co',           'hotel-casa-real',        false, '2025-06-01 12:00-05'),
        ('MICRO', 'Medellín',      'Bodegas Interamericana Ltda.',      'Interamericana',           '900667788',  '0', 'admin@interamericana.co',           '6042554433', 'Guarne', 'Mario Botero',             'sst@interamericana.co',          'bodegas-interamericana', false, '2025-07-10 10:25-05'),
        ('MICRO', 'Palmira',       'Pollos La Finca S.A.S.',            'La Finca',                 '900778899',  '1', 'gerencia@polloslafinca.co',         '6022711223', 'Zona Rural', 'Gloria Bastidas',       'sst@polloslafinca.co',           'pollos-la-finca',        false, '2025-08-15 16:00-05'),
        ('MICRO', 'Girón',         'Torre Fashion Imports Ltda.',       'Torre Fashion',            '900889900',  '2', 'ventas@torrefashion.co',            '6076903355', 'Calle 30 # 18-55', 'Mauricio Pabón','sst@torrefashion.co',           'torre-fashion',          true,  '2026-06-15 17:45-05')
    ) AS v(size_code, city_name, legal_name, trade_name, tax_id, check_digit,
           email, phone, address, contact_name, contact_email, slug, is_active, created_at)
    INNER JOIN tenant_sizes AS ts ON ts.code = v.size_code
    INNER JOIN departments AS d  ON d.name = 'Santander'  -- solo para deducir el país
    INNER JOIN cities      AS c  ON c.name = v.city_name
    RETURNING id, legal_name AS tenant_name
)
SELECT 'Organizaciones insertadas: ' || count(*) FROM new_tenants;

-- =============================================================================
-- 3. CARGOS (por organización; los vacíos alimentan los LEFT JOIN con 0)
-- =============================================================================

WITH new_positions AS (
    INSERT INTO positions (tenant_id, name, code, risk_level, description, is_active, created_at, updated_at)
    SELECT t.id, v.name, v.code, v.risk_level, v.description, true, '2025-02-01 09:00-05', '2025-02-01 09:00-05'
    FROM (VALUES
        ('Andes Construcciones S.A.S.',       'Gerente General',           'GG',  2, 'Dirección general de la organización.'),
        ('Andes Construcciones S.A.S.',       'Gerente de Proyectos',      'GP',  3, 'Dirección de proyectos de obra.'),
        ('Andes Construcciones S.A.S.',       'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Andes Construcciones S.A.S.',       'Coordinador PESV',          'CPV', 3, 'Responsable del PESV.'),
        ('Andes Construcciones S.A.S.',       'Operario de Obra',          'OPR', 5, 'Ejecución de trabajos en obra.'),
        ('Andes Construcciones S.A.S.',       'Auxiliar Administrativo',   'AUX', 1, 'Apoyo administrativo.'),
        ('Andes Construcciones S.A.S.',       'Analista HSEQ',             'HSEQ',2, 'Análisis e indicadores HSEQ.'),
        ('Andes Construcciones S.A.S.',       'Supervisor de Obra',        'SUP', 4, 'Supervisión de frentes de obra.'),
        ('Andes Construcciones S.A.S.',       'Analista Administrativo',   'AAD', 1, NULL),   -- sin personas
        ('Petrolera Llanos S.A.',             'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Petrolera Llanos S.A.',             'Gerente de Operaciones',    'GO',  4, 'Operaciones de campo.'),
        ('Petrolera Llanos S.A.',             'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Petrolera Llanos S.A.',             'Coordinador PESV',          'CPV', 3, 'Responsable del PESV.'),
        ('Petrolera Llanos S.A.',             'Operario de Producción',    'OPR', 5, 'Operación de instalaciones.'),
        ('Petrolera Llanos S.A.',             'Supervisor de Turno',       'SUP', 4, 'Supervisión por turnos.'),
        ('Petrolera Llanos S.A.',             'Auxiliar de Campo',         'AUX', 3, 'Apoyo en campo.'),
        ('Petrolera Llanos S.A.',             'Analista Ambiental',        'AMB', 2, NULL),   -- sin personas
        ('Metales del Caribe S.A.S.',         'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Metales del Caribe S.A.S.',         'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Metales del Caribe S.A.S.',         'Operario de Planta',        'OPR', 5, 'Operación de máquinas.'),
        ('Metales del Caribe S.A.S.',         'Supervisor de Producción',  'SUP', 4, 'Supervisión de producción.'),
        ('Metales del Caribe S.A.S.',         'Auxiliar de Planta',        'AUX', 3, 'Apoyo de planta.'),
        ('Metales del Caribe S.A.S.',         'Coordinador de Logística',  'LOG', 3, NULL),   -- sin personas
        ('Alimentos Santander S.A.S.',        'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Alimentos Santander S.A.S.',        'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Alimentos Santander S.A.S.',        'Supervisor de Planta',      'SUP', 4, 'Supervisión de planta.'),
        ('Alimentos Santander S.A.S.',        'Auxiliar de Producción',    'AUX', 3, 'Producción de alimentos.'),
        ('Alimentos Santander S.A.S.',        'Auxiliar Logístico',        'ALG', 2, 'Almacén y despachos.'),
        ('Alimentos Santander S.A.S.',        'Coordinador de Calidad',    'CAL', 2, NULL),   -- sin personas
        ('Textiles del Norte S.A.S.',         'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Textiles del Norte S.A.S.',         'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Textiles del Norte S.A.S.',         'Coordinador PESV',          'CPV', 3, 'Distribución y transporte.'),
        ('Textiles del Norte S.A.S.',         'Supervisor de Confección',  'SUP', 4, 'Supervisión de confección.'),
        ('Textiles del Norte S.A.S.',         'Almacenista',               'ALM', 2, NULL),   -- sin personas
        ('Transportes Andinos S.A.S.',        'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Transportes Andinos S.A.S.',        'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Transportes Andinos S.A.S.',        'Coordinador PESV',          'CPV', 3, 'Responsable del PESV.'),
        ('Transportes Andinos S.A.S.',        'Auxiliar de Oficina',       'AUX', 1, 'Apoyo administrativo.'),
        ('Transportes Andinos S.A.S.',        'Despachador',               'DSP', 3, NULL),   -- sin personas
        ('Clínica Vitalis Bucaramanga S.A.',  'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Clínica Vitalis Bucaramanga S.A.',  'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Clínica Vitalis Bucaramanga S.A.',  'Auxiliar de Enfermería',    'AUX', 3, 'Atención al paciente.'),
        ('Clínica Vitalis Bucaramanga S.A.',  'Auxiliar Administrativo',   'AAD', 1, 'Apoyo administrativo.'),
        ('Agroindustrias del Café S.A.S.',    'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Agroindustrias del Café S.A.S.',    'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Agroindustrias del Café S.A.S.',    'Auxiliar de Beneficio',     'AUX', 4, 'Beneficio del café.'),
        ('Agroindustrias del Café S.A.S.',    'Administrador de Finca',    'AFI', 3, NULL),   -- sin personas
        ('Constructora Cívica S.A.S.',        'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Constructora Cívica S.A.S.',        'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Constructora Cívica S.A.S.',        'Auxiliar de Obra',          'AUX', 5, 'Trabajos generales de obra.'),
        ('Constructora Cívica S.A.S.',        'Maestro de Obra',           'MAE', 4, NULL),   -- sin personas
        ('Distribuidora Café Soft Ltda.',     'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Distribuidora Café Soft Ltda.',     'Coordinador PESV',          'CPV', 3, 'Rutas de distribución.'),
        ('Distribuidora Café Soft Ltda.',     'Conductor Repartidor',      'CON', 4, NULL),   -- sin personas
        ('Lácteos La Pradera S.A.S.',         'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Lácteos La Pradera S.A.S.',         'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Lácteos La Pradera S.A.S.',         'Operario de Cuajada',       'OPR', 4, NULL),   -- sin personas
        ('Comercializadora Andina Ltda.',     'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Comercializadora Andina Ltda.',     'Auxiliar de Ventas',        'AUX', 2, NULL),   -- sin personas
        ('Servicios Mineros del Alto S.A.S.', 'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Servicios Mineros del Alto S.A.S.', 'Coordinador de Campo',      'CC',  4, 'Coordinación en mina.'),
        ('Fríos del Valle S.A.S.',            'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Fríos del Valle S.A.S.',            'Operario de Cuarto Frío',   'OPR', 5, NULL),   -- sin personas
        ('Consultores SST Elite S.A.S.',      'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Consultores SST Elite S.A.S.',      'Consultor SST',             'CONS',2, 'Consultoría en SST.'),
        ('Logística Ferrico S.A.S.',          'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Logística Ferrico S.A.S.',          'Coordinador PESV',          'CPV', 3, 'Responsable del PESV.'),
        ('Logística Ferrico S.A.S.',          'Auxiliar de Bodega',        'AUX', 3, NULL),   -- sin personas
        ('Torre Fashion Imports Ltda.',       'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Torre Fashion Imports Ltda.',       'Auxiliar de Bodega',        'AUX', 3, 'Recibo y despacho de moda.'),
        ('Torre Fashion Imports Ltda.',       'Vendedor de Showroom',      'VEN', 1, NULL),   -- sin personas
        ('Hotel Casa Real S.A.',              'Gerente General',           'GG',  2, 'Dirección general.'),
        ('Hotel Casa Real S.A.',              'Jefe de SST',               'JSST',2, 'Responsable del SG-SST.'),
        ('Hotel Casa Real S.A.',              'Auxiliar de Housekeeping',  'AUX', 3, 'Aseo y alojamiento.'),
        ('Hotel Casa Real S.A.',              'Operario de Mantenimiento', 'OPR', 4, 'Mantenimiento hotelero.'),
        ('Hotel Casa Real S.A.',              'Conserje',                  'CON', 2, NULL),   -- sin personas
        ('Hotel Casa Real S.A.',              'Recepcionista',             'REC', 1, NULL)    -- sin personas
    ) AS v(tenant_name, name, code, risk_level, description)
    INNER JOIN tenants AS t ON t.legal_name = v.tenant_name
    RETURNING id, tenant_id, name AS position_name
)
SELECT 'Cargos insertados: ' || count(*) || ' (vacíos: ' ||
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM persons AS p WHERE p.position_id = np.id)) || ')'
FROM new_positions AS np;

-- =============================================================================
-- 4. PERSONAS (77)
--    t1: 15 y t2: 15 (empate en el máximo, con 2 inactivas cada una);
--    t15/t16/t18/t19: 0 personas; ~14 % sin email; ~12 % inactivas;
--    documentos CC/CE/TI/PA/PPT; hire_date 2019–2026 con repetidas.
-- =============================================================================

INSERT INTO persons (tenant_id, position_id, document_type, document_number,
                     first_name, last_name, email, phone, birth_date, hire_date,
                     termination_date, is_active, created_at, updated_at)
SELECT t.id,
       pos.id,
       v.doc_type,
       v.doc_number,
       v.first_name,
       v.last_name,
       v.email,
       v.phone,
       v.birth_date::date,
       v.hire_date::date,
       v.termination_date::date,
       v.is_active,
       v.hire_date::timestamptz + interval '9 hours',
       v.hire_date::timestamptz + interval '9 hours'
FROM (VALUES
    -- Andes Construcciones (15): Gerente 1 y 2 empate dentro del cargo; Operarios 5; Auxiliares 3; Supervisores 2 (inactivas p14 y p15)
    ('Andes Construcciones S.A.S.',      'Gerente General',         'CC',  '10102030',  'Laura',   'Gómez',        'laura.gomez@andesconstrucciones.co',   '3171234501', '1980-04-12', '2019-02-01', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Gerente de Proyectos',    'CC',  '10203040',  'Andrés',  'Rodríguez',    'andres.rodriguez@andesconstrucciones.co','3171234502','1983-09-25','2019-02-01', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Jefe de SST',             'CC',  '10304050',  'Carolina','Martínez',     'carolina.martinez@andesconstrucciones.co','3171234503','1986-01-17','2020-03-15',NULL,        true),
    ('Andes Construcciones S.A.S.',      'Coordinador PESV',        'CC',  '10405060',  'Diego',   'López',        'diego.lopez@andesconstrucciones.co',   '3171234504', '1990-06-03', '2021-06-01', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Operario de Obra',        'CC',  '10506070',  'Jorge',   'Pérez',        'jorge.perez@andesconstrucciones.co',   '3171234505', '1992-11-30', '2020-03-15', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Operario de Obra',        'CC',  '10607080',  'Miguel',  'Sánchez',      'miguel.sanchez@andesconstrucciones.co','3171234506', '1994-02-14', '2020-03-15', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Operario de Obra',        'CC',  '10708090',  'Óscar',   'Ramírez',      'oscar.ramirez@andesconstrucciones.co', '3171234507', '1996-07-21', '2021-06-01', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Operario de Obra',        'CC',  '10809010',  'Iván',    'Torres',       'ivan.torres@andesconstrucciones.co',   '3171234508', '1997-03-08', '2021-06-01', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Operario de Obra',        'CC',  '10901020',  'Rubén',   'Díaz',         'ruben.diaz@andesconstrucciones.co',    '3171234509', '1993-12-05', '2022-08-20', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Auxiliar Administrativo', 'CC',  '11002030',  'Paula',   'Herrera',      'paula.herrera@andesconstrucciones.co', '3171234510', '1998-05-19', '2022-08-20', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Auxiliar Administrativo', 'CC',  '11103040',  'Sara',    'Navarro',      'sara.navarro@andesconstrucciones.co',  '3171234511', '2000-08-02', '2023-01-10', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Auxiliar Administrativo', 'CC',  '11204050',  'Elena',   'Cruz',         NULL,                                   NULL,         '2001-10-11', '2023-01-10', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Analista HSEQ',           'CC',  '11305060',  'Natalia', 'Castro',       'natalia.castro@andesconstrucciones.co','3171234513', '1991-04-27', '2024-05-05', NULL,        true),
    ('Andes Construcciones S.A.S.',      'Supervisor de Obra',      'CC',  '11406070',  'Édgar',   'Molina',       NULL,                                   NULL,         '1988-07-09', '2024-05-05', '2025-11-30', false),
    ('Andes Construcciones S.A.S.',      'Supervisor de Obra',      'CC',  '11507080',  'Verónica','Agudelo',      NULL,                                   NULL,         '1993-01-23', '2025-09-01', '2025-11-30', false),
    -- Petrolera Llanos (15): Gerentes 2 (empate), Operarios 5, Supervisores 4, Auxiliares 2 (inactivas p29 y p30)
    ('Petrolera Llanos S.A.',            'Gerente General',         'CC',  '20102030',  'Fernando','Ramírez',      'fernando.ramirez@petrolerallanos.com.co','3182345601','1979-02-18','2019-06-10',NULL,        true),
    ('Petrolera Llanos S.A.',            'Gerente de Operaciones',  'CC',  '20203040',  'Gloria',  'Torres',       'gloria.torres@petrolerallanos.com.co', '3182345602', '1984-08-30', '2019-06-10', NULL,        true),
    ('Petrolera Llanos S.A.',            'Jefe de SST',             'CC',  '20304050',  'Héctor',  'Salazar',      'hector.salazar@petrolerallanos.com.co','3182345603', '1987-05-14', '2020-02-01', NULL,        true),
    ('Petrolera Llanos S.A.',            'Coordinador PESV',        'CC',  '20405060',  'Inés',    'Mendoza',      'ines.mendoza@petrolerallanos.com.co',  '3182345604', '1992-09-07', '2021-03-15', NULL,        true),
    ('Petrolera Llanos S.A.',            'Operario de Producción',  'CC',  '20506070',  'Julio',   'Cárdenas',     'julio.cardenas@petrolerallanos.com.co','3182345605', '1995-04-11', '2020-02-01', NULL,        true),
    ('Petrolera Llanos S.A.',            'Operario de Producción',  'CC',  '20607080',  'Kevin',   'Orobio',       'kevin.orobio@petrolerallanos.com.co',  '3182345606', '1998-12-01', '2021-03-15', NULL,        true),
    ('Petrolera Llanos S.A.',            'Operario de Producción',  'CC',  '20708090',  'Luis',    'Paz',          'luis.paz@petrolerallanos.com.co',      '3182345607', '1996-06-22', '2022-04-10', NULL,        true),
    ('Petrolera Llanos S.A.',            'Operario de Producción',  'CC',  '20809010',  'Marcela', 'Quintero',     'marcela.quintero@petrolerallanos.com.co','3182345608','1999-03-17','2022-04-10',NULL,        true),
    ('Petrolera Llanos S.A.',            'Operario de Producción',  'CC',  '20901020',  'Nicolás', 'Rentería',     'nicolas.renteria@petrolerallanos.com.co','3182345609','1997-10-26','2023-06-05',NULL,        true),
    ('Petrolera Llanos S.A.',            'Supervisor de Turno',     'CC',  '21002030',  'Óscar',   'Mosquera',     'oscar.mosquera@petrolerallanos.com.co','3182345610', '1989-01-05', '2024-02-10', NULL,        true),
    ('Petrolera Llanos S.A.',            'Supervisor de Turno',     'CC',  '21103040',  'Patricia','Valencia',     'patricia.valencia@petrolerallanos.com.co','3182345611','1990-11-28','2024-02-10',NULL,        true),
    ('Petrolera Llanos S.A.',            'Supervisor de Turno',     'CC',  '21204050',  'Ricardo','Ospino',        'ricardo.ospino@petrolerallanos.com.co','3182345612', '1985-07-03', '2024-02-10', NULL,        true),
    ('Petrolera Llanos S.A.',            'Supervisor de Turno',     'CC',  '21305060',  'Sebastián','Álvarez',     'sebastian.alvarez@petrolerallanos.com.co','3182345613','1991-09-19','2026-01-15',NULL,        true),
    ('Petrolera Llanos S.A.',            'Auxiliar de Campo',       'CC',  '21406070',  'Tatiana', 'Bermúdez',     NULL,                                   NULL,         '2000-02-13', '2026-01-15', NULL,        true),
    ('Petrolera Llanos S.A.',            'Auxiliar de Campo',       'CC',  '21507080',  'Ulises',  'Riascos',      NULL,                                   NULL,         '2002-06-30', '2025-12-01', '2026-03-31', false),
    -- Metales del Caribe (8)
    ('Metales del Caribe S.A.S.',        'Gerente General',         'CC',  '30102030',  'Carlos',  'Cárdenas',     'carlos.cardenas@metacaribe.co',        '3193456701', '1978-10-05', '2025-03-12', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Jefe de SST',             'CC',  '30203040',  'Diana',   'Rueda',        'diana.rueda@metacaribe.co',            '3193456702', '1988-03-22', '2025-04-01', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Operario de Planta',      'CC',  '30304050',  'Esteban', 'Galvis',       'esteban.galvis@metacaribe.co',         '3193456703', '1994-08-16', '2025-04-01', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Operario de Planta',      'CC',  '30405060',  'Fabiana', 'Serpa',        'fabiana.serpa@metacaribe.co',          '3193456704', '1996-02-27', '2025-05-15', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Supervisor de Producción','CE',  '405060',    'Gustavo', 'Petronio',     'gustavo.petronio@metacaribe.co',       '3193456705', '1985-05-09', '2025-06-01', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Supervisor de Producción','CC',  '30506070',  'Helena',  'Mantilla',     'helena.mantilla@metacaribe.co',        '3193456706', '1990-12-13', '2025-06-01', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Auxiliar de Planta',      'CC',  '30607080',  'Ignacio', 'Vélez',        'ignacio.velez@metacaribe.co',          '3193456707', '1999-07-08', '2026-01-20', NULL,        true),
    ('Metales del Caribe S.A.S.',        'Auxiliar de Planta',      'CC',  '30708090',  'Julieta', 'Sarmiento',    NULL,                                   NULL,         '2001-01-19', '2026-01-20', NULL,        true),
    -- Alimentos Santander (6)
    ('Alimentos Santander S.A.S.',       'Gerente General',         'CC',  '40102030',  'Martha',  'Peña',         'martha.pena@alisantander.co',          '3104567801', '1977-04-03', '2025-04-18', NULL,        true),
    ('Alimentos Santander S.A.S.',       'Jefe de SST',             'CC',  '40203040',  'Néstor',  'Quintero',     'nestor.quintero@alisantander.co',      '3104567802', '1986-11-11', '2025-05-02', NULL,        true),
    ('Alimentos Santander S.A.S.',       'Supervisor de Planta',    'CC',  '40304050',  'Olga',    'Lucumi',       'olga.lucumi@alisantander.co',          '3104567803', '1991-06-24', '2025-05-02', NULL,        true),
    ('Alimentos Santander S.A.S.',       'Auxiliar de Producción',  'TI',  '1088776655','Pablo',   'Céspedes',     'pablo.cespedes@alisantander.co',       '3104567804', '2007-03-15', '2026-02-02', NULL,        true),
    ('Alimentos Santander S.A.S.',       'Auxiliar de Producción',  'CC',  '40405060',  'Queen',   'Zapata',       'queen.zapata@alisantander.co',         '3104567805', '1998-09-09', '2026-02-02', NULL,        true),
    ('Alimentos Santander S.A.S.',       'Auxiliar Logístico',      'CC',  '40506070',  'Camila',  'Ortiz',        NULL,                                   NULL,         '2000-12-04', '2026-03-10', NULL,        true),
    -- Textiles del Norte (5)
    ('Textiles del Norte S.A.S.',        'Gerente General',         'PA',  'PA880122',  'Julián',  'Ospina',       'julian.ospina@texnorte.co',            '3115678901', '1981-07-29', '2025-05-25', NULL,        true),
    ('Textiles del Norte S.A.S.',        'Jefe de SST',             'CC',  '50102030',  'Karina',  'Betancur',     'karina.betancur@texnorte.co',          '3115678902', '1989-02-08', '2025-06-15', NULL,        true),
    ('Textiles del Norte S.A.S.',        'Coordinador PESV',        'CC',  '50203040',  'Leonardo','Usme',         'leonardo.usme@texnorte.co',            '3115678903', '1993-10-17', '2025-07-01', NULL,        true),
    ('Textiles del Norte S.A.S.',        'Supervisor de Confección','CC',  '50304050',  'Mónica',  'Rueda',        'monica.rueda@texnorte.co',             '3115678904', '1992-04-26', '2025-07-01', NULL,        true),
    ('Textiles del Norte S.A.S.',        'Supervisor de Confección','CC',  '50405060',  'Wilson',  'Chinchilla',   NULL,                                   NULL,         '1997-08-14', '2026-01-12', NULL,        true),
    -- Transportes Andinos (4)
    ('Transportes Andinos S.A.S.',       'Gerente General',         'CC',  '60102030',  'Diana',   'Nieto',        'diana.nieto@transandinos.co',          '3126789001', '1982-12-01', '2026-06-30', NULL,        true),
    ('Transportes Andinos S.A.S.',       'Jefe de SST',             'CC',  '60203040',  'Emilio',  'Franco',       'emilio.franco@transandinos.co',        '3126789002', '1987-06-06', '2026-07-01', NULL,        true),
    ('Transportes Andinos S.A.S.',       'Coordinador PESV',        'CC',  '60304050',  'Fabio',   'Zambrano',     'fabio.zambrano@transandinos.co',       '3126789003', '1994-01-25', '2026-07-01', NULL,        true),
    ('Transportes Andinos S.A.S.',       'Auxiliar de Oficina',     'CC',  '60405060',  'Yesica',  'Ariza',        NULL,                                   NULL,         '2002-04-19', '2026-07-01', NULL,        true),
    -- Clínica Vitalis (4) — misma ciudad que Metales del Caribe con distinto tamaño (GRA vs MED)
    ('Clínica Vitalis Bucaramanga S.A.', 'Gerente General',         'PA',  'PA771233',  'Fernando','Vargas',       'fernando.vargas@clinicavitalis.co',    '3137890101', '1975-09-12', '2026-07-01', NULL,        true),
    ('Clínica Vitalis Bucaramanga S.A.', 'Jefe de SST',             'CC',  '70102030',  'Gisela',  'Rojas',        'gisela.rojas@clinicavitalis.co',       '3137890102', '1990-03-03', '2026-07-05', NULL,        true),
    ('Clínica Vitalis Bucaramanga S.A.', 'Auxiliar de Enfermería',  'CC',  '70203040',  'Hernán',  'Camacho',      'hernan.camacho@clinicavitalis.co',     '3137890103', '1996-11-21', '2026-07-05', NULL,        true),
    ('Clínica Vitalis Bucaramanga S.A.', 'Auxiliar Administrativo', 'CC',  '70304050',  'Irene',   'Solano',       'irene.solano@clinicavitalis.co',       '3137890104', '2000-05-07', '2026-07-06', NULL,        true),
    -- Agroindustrias del Café (3)
    ('Agroindustrias del Café S.A.S.',   'Gerente General',         'CC',  '80102030',  'Óscar',   'Arias',        'oscar.arias@agrocafe.co',              '3148901201', '1979-05-16', '2026-01-10', NULL,        true),
    ('Agroindustrias del Café S.A.S.',   'Jefe de SST',             'CC',  '80203040',  'Yolanda', 'Plata',        'yolanda.plata@agrocafe.co',            '3148901202', '1988-08-08', '2026-01-12', NULL,        true),
    ('Agroindustrias del Café S.A.S.',   'Auxiliar de Beneficio',   'CC',  '80304050',  'Estefanía','Ocampo',       NULL,                                   NULL,         '1999-02-24', '2026-01-12', NULL,        true),
    -- Constructora Cívica (3)
    ('Constructora Cívica S.A.S.',       'Gerente General',         'CC',  '90102030',  'Liliana', 'Rojas',        'liliana.rojas@civica.co',              '3159012301', '1983-11-30', '2026-01-20', NULL,        true),
    ('Constructora Cívica S.A.S.',       'Jefe de SST',             'CC',  '90203040',  'Álvaro',  'Ulloa',        'alvaro.ulloa@civica.co',               '3159012302', '1991-07-18', '2026-02-01', NULL,        true),
    ('Constructora Cívica S.A.S.',       'Auxiliar de Obra',        'TI',  '1099887766','Brayan',  'Conde',        'brayan.conde@civica.co',               '3159012303', '2006-09-03', '2026-02-01', NULL,        true),
    -- Distribuidora Café Soft (2)
    ('Distribuidora Café Soft Ltda.',    'Gerente General',         'CE',  '501122',    'Andrés',  'Villegas',     'andres.villegas@cafesoft.co',          '3160123401', '1985-01-26', '2026-01-28', NULL,        true),
    ('Distribuidora Café Soft Ltda.',    'Coordinador PESV',        'CC',  '1102030',   'Carla',   'Cadena',       'carla.cadena@cafesoft.co',             '3160123402', '1995-10-12', '2026-02-03', NULL,        true),
    -- Lácteos La Pradera (2)
    ('Lácteos La Pradera S.A.S.',        'Gerente General',         'PPT', 'PPT441122', 'Camilo',  'Hoyos',        'camilo.hoyos@lacteospradera.co',       '3171234001', '1986-04-14', '2026-02-05', NULL,        true),
    ('Lácteos La Pradera S.A.S.',        'Jefe de SST',             'CC',  '1203040',   'Doris',   'Restrepo',     'doris.restrepo@lacteospradera.co',     '3171234002', '1992-12-08', '2026-02-06', NULL,        true),
    -- Comercializadora Andina (1)
    ('Comercializadora Andina Ltda.',    'Gerente General',         'TI',  '1099665544','Efraín',  'Zuluaga',      'efrain.zuluaga@comandina.co',          '3182344001', '2005-06-21', '2026-02-14', NULL,        true),
    -- Servicios Mineros del Alto (1)
    ('Servicios Mineros del Alto S.A.S.','Gerente General',         'CE',  '602233',    'Jairo',   'Cuesta',       'jairo.cuesta@sermialto.co',            '3193454001', '1980-08-27', '2026-02-22', NULL,        true),
    -- Fríos del Valle (1)
    ('Fríos del Valle S.A.S.',           'Gerente General',         'PA',  'PA660199',  'Sandra',  'Ibáñez',       'sandra.ibanez@friosvalle.co',          '3104564001', '1984-02-11', '2026-03-03', NULL,        true),
    -- Torre Fashion (2) — sin sistemas SST/PESV
    ('Torre Fashion Imports Ltda.',      'Gerente General',         'PPT', 'PPT552211', 'Mauricio','Pabón',        'mauricio.pabon@torrefashion.co',       '3115674001', '1983-06-19', '2026-06-15', NULL,        true),
    ('Torre Fashion Imports Ltda.',      'Auxiliar de Bodega',      'CC',  '1304050',   'Nidia',   'Leal',         'nidia.leal@torrefashion.co',           '3115674002', '1998-11-02', '2026-06-16', NULL,        true),
    -- Hotel Casa Real (5, TODAS inactivas: la organización se desvinculó)
    ('Hotel Casa Real S.A.',             'Gerente General',         'CC',  '1405060',   'Elena',   'Sáenz',        'elena.saenz@hotelcasareal.co',         '3156784001', '1976-10-08', '2025-06-01', '2025-11-30', false),
    ('Hotel Casa Real S.A.',             'Jefe de SST',             'CC',  '1506070',   'Fernando','Fajardo',      'fernando.fajardo@hotelcasareal.co',    '3156784002', '1989-05-25', '2025-06-01', '2025-11-30', false),
    ('Hotel Casa Real S.A.',             'Auxiliar de Housekeeping','CC',  '1607080',   'Gabriela','Madera',       NULL,                                   NULL,         '1997-09-15', '2025-06-01', '2025-11-30', false),
    ('Hotel Casa Real S.A.',             'Auxiliar de Housekeeping','CC',  '1708090',   'Hugo',    'Pertuz',       'hugo.pertuz@hotelcasareal.co',         '3156784004', '2001-03-28', '2025-06-01', '2025-11-30', false),
    ('Hotel Casa Real S.A.',             'Operario de Mantenimiento','CC', '1809010',   'Iván',    'Pinzón',       'ivan.pinzon@hotelcasareal.co',         '3156784005', '1994-07-06', '2025-06-01', '2025-11-30', false)
) AS v(tenant_name, position_name, doc_type, doc_number, first_name, last_name,
       email, phone, birth_date, hire_date, termination_date, is_active)
INNER JOIN tenants   AS t   ON t.legal_name = v.tenant_name
INNER JOIN positions AS pos ON pos.tenant_id = t.id AND pos.name = v.position_name;

-- =============================================================================
-- 5. SISTEMAS Y MÓDULOS POR ORGANIZACIÓN
--    t1: TODOS los módulos SST + 2 de PESV; t2: TODOS los PESV + 2 SST;
--    t6: TODOS los PESV; t13 y t16: con una habilitación INACTIVA;
--    t18: inactiva CON módulos aún habilitados; t17/t19/t20 sin nada.
-- =============================================================================

WITH new_systems AS (
    INSERT INTO tenantsystems (tenant_id, type_system_sst_id, activated_at, deactivated_at, notes, is_active, created_at, updated_at)
    SELECT t.id, s.id, v.activated_at::timestamptz, v.deactivated_at::timestamptz, v.notes,
           v.is_active, v.activated_at::timestamptz, v.activated_at::timestamptz
    FROM (VALUES
        ('Andes Construcciones S.A.S.',       'SST',  '2025-01-20 09:00-05', NULL,                 'Implementación completa del SG-SST.',          true),
        ('Andes Construcciones S.A.S.',       'PESV', '2025-03-01 09:00-05', NULL,                 'Flota propia de volquetas.',                   true),
        ('Petrolera Llanos S.A.',             'SST',  '2025-02-25 09:00-05', NULL,                 'SG-SST certificado ISO 45001.',                true),
        ('Petrolera Llanos S.A.',             'PESV', '2025-04-01 09:00-05', NULL,                 'Transporte de personal a campo.',              true),
        ('Metales del Caribe S.A.S.',         'SST',  '2025-03-20 09:00-05', NULL,                 NULL,                                           true),
        ('Alimentos Santander S.A.S.',        'SST',  '2025-05-01 09:00-05', NULL,                 NULL,                                           true),
        ('Textiles del Norte S.A.S.',         'SST',  '2025-06-01 09:00-05', NULL,                 NULL,                                           true),
        ('Textiles del Norte S.A.S.',         'PESV', '2025-08-01 09:00-05', NULL,                 'Distribución nacional.',                       true),
        ('Transportes Andinos S.A.S.',        'SST',  '2026-07-01 09:00-05', NULL,                 'Cliente nuevo de 2026.',                       true),
        ('Transportes Andinos S.A.S.',        'PESV', '2026-07-01 09:05-05', NULL,                 'Actividad principal de transporte.',           true),
        ('Clínica Vitalis Bucaramanga S.A.',  'SST',  '2026-07-02 09:00-05', NULL,                 'Cliente nuevo de 2026.',                       true),
        ('Agroindustrias del Café S.A.S.',    'SST',  '2026-01-15 09:00-05', NULL,                 NULL,                                           true),
        ('Constructora Cívica S.A.S.',        'SST',  '2026-01-25 09:00-05', NULL,                 NULL,                                           true),
        ('Distribuidora Café Soft Ltda.',     'PESV', '2026-02-01 09:00-05', NULL,                 'Solo distribución vial.',                      true),
        ('Lácteos La Pradera S.A.S.',         'SST',  '2026-02-10 09:00-05', NULL,                 NULL,                                           true),
        ('Comercializadora Andina Ltda.',     'SST',  '2026-02-20 09:00-05', NULL,                 NULL,                                           true),
        ('Servicios Mineros del Alto S.A.S.', 'SST',  '2026-03-01 09:00-05', NULL,                 NULL,                                           true),
        ('Servicios Mineros del Alto S.A.S.', 'PESV', '2026-03-01 09:05-05', '2026-05-31 17:00-05','Se desactivó: tercerizó el transporte.',       false),
        ('Fríos del Valle S.A.S.',            'SST',  '2026-03-10 09:00-05', NULL,                 NULL,                                           true),
        ('Consultores SST Elite S.A.S.',      'SST',  '2026-03-15 09:00-05', NULL,                 'Consultores: aún sin plantillas asignadas.',   true),
        ('Logística Ferrico S.A.S.',          'PESV', '2026-03-25 09:00-05', NULL,                 'Módulos habilitados, plantillas pendientes.',  true),
        ('Hotel Casa Real S.A.',              'SST',  '2025-06-05 09:00-05', '2025-11-30 17:00-05','Desactivado al retirarse de la plataforma.',   false),
        ('Bodegas Interamericana Ltda.',      'SST',  '2025-07-15 09:00-05', NULL,                 'Inactiva pero conserva módulos habilitados.',  false)
    ) AS v(tenant_name, system_code, activated_at, deactivated_at, notes, is_active)
    INNER JOIN tenants         AS t ON t.legal_name = v.tenant_name
    INNER JOIN type_system_sst AS s ON s.code = v.system_code
    RETURNING 1
)
SELECT 'Habilitaciones de sistema insertadas: ' || count(*) FROM new_systems;

WITH new_modules AS (
    INSERT INTO tenant_modules (tenant_id, module_id, enabled_at, disabled_at, is_active, created_at, updated_at)
    SELECT t.id, m.id, v.enabled_at::timestamptz, v.disabled_at::timestamptz,
           v.is_active, v.enabled_at::timestamptz, v.enabled_at::timestamptz
    FROM (VALUES
        -- t1: los 8 módulos SST + 2 PESV
        ('Andes Construcciones S.A.S.', 'MO_POL_PROG',  '2025-01-20 09:10-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_MFG_RISK',  '2025-01-20 09:11-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_MGMT_GEN',  '2025-01-20 09:12-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_INSP_PROG', '2025-01-20 09:13-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_INC_INV',   '2025-01-20 09:14-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_INT_AUD',   '2025-01-20 09:15-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_MGMT_REV',  '2025-01-20 09:16-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_PCAP',      '2025-01-20 09:17-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_POL_VIAL',  '2025-03-01 09:10-05', NULL, true),
        ('Andes Construcciones S.A.S.', 'MO_HAZ_VIAL',  '2025-03-01 09:11-05', NULL, true),
        -- t2: los 4 módulos PESV + 2 SST
        ('Petrolera Llanos S.A.',       'MO_POL_VIAL',  '2025-04-01 09:10-05', NULL, true),
        ('Petrolera Llanos S.A.',       'MO_HAZ_VIAL',  '2025-04-01 09:11-05', NULL, true),
        ('Petrolera Llanos S.A.',       'MO_REV_VEH',   '2025-04-01 09:12-05', NULL, true),
        ('Petrolera Llanos S.A.',       'MO_MFG_VIAL',  '2025-04-01 09:13-05', NULL, true),
        ('Petrolera Llanos S.A.',       'MO_POL_PROG',  '2025-02-25 09:10-05', NULL, true),
        ('Petrolera Llanos S.A.',       'MO_MFG_RISK',  '2025-02-25 09:11-05', NULL, true),
        -- El resto: asignaciones parciales
        ('Metales del Caribe S.A.S.',   'MO_POL_PROG',  '2025-03-20 09:10-05', NULL, true),
        ('Metales del Caribe S.A.S.',   'MO_MFG_RISK',  '2025-03-20 09:11-05', NULL, true),
        ('Metales del Caribe S.A.S.',   'MO_INC_INV',   '2025-03-20 09:12-05', NULL, true),
        ('Alimentos Santander S.A.S.',  'MO_POL_PROG',  '2025-05-01 09:10-05', NULL, true),
        ('Alimentos Santander S.A.S.',  'MO_MFG_RISK',  '2025-05-01 09:11-05', NULL, true),
        ('Alimentos Santander S.A.S.',  'MO_INT_AUD',   '2025-05-01 09:12-05', NULL, true),
        ('Textiles del Norte S.A.S.',   'MO_POL_PROG',  '2025-06-01 09:10-05', NULL, true),
        ('Textiles del Norte S.A.S.',   'MO_MGMT_GEN',  '2025-06-01 09:11-05', NULL, true),
        ('Textiles del Norte S.A.S.',   'MO_POL_VIAL',  '2025-08-01 09:10-05', NULL, true),
        ('Transportes Andinos S.A.S.',  'MO_POL_VIAL',  '2026-07-01 09:10-05', NULL, true),
        ('Transportes Andinos S.A.S.',  'MO_HAZ_VIAL',  '2026-07-01 09:11-05', NULL, true),
        ('Transportes Andinos S.A.S.',  'MO_REV_VEH',   '2026-07-01 09:12-05', NULL, true),
        ('Transportes Andinos S.A.S.',  'MO_MFG_VIAL',  '2026-07-01 09:13-05', NULL, true),
        ('Transportes Andinos S.A.S.',  'MO_POL_PROG',  '2026-07-01 09:14-05', NULL, true),
        ('Clínica Vitalis Bucaramanga S.A.','MO_POL_PROG','2026-07-02 09:10-05',NULL, true),
        ('Clínica Vitalis Bucaramanga S.A.','MO_MFG_RISK','2026-07-02 09:11-05',NULL, true),
        ('Agroindustrias del Café S.A.S.','MO_POL_PROG', '2026-01-15 09:10-05', NULL, true),
        ('Agroindustrias del Café S.A.S.','MO_MGMT_GEN', '2026-01-15 09:11-05', NULL, true),
        ('Constructora Cívica S.A.S.',  'MO_POL_PROG',  '2026-01-25 09:10-05', NULL, true),
        ('Constructora Cívica S.A.S.',  'MO_INT_AUD',   '2026-01-25 09:11-05', NULL, true),
        ('Distribuidora Café Soft Ltda.','MO_POL_VIAL', '2026-02-01 09:10-05', NULL, true),
        ('Distribuidora Café Soft Ltda.','MO_HAZ_VIAL', '2026-02-01 09:11-05', NULL, true),
        ('Lácteos La Pradera S.A.S.',   'MO_INSP_PROG', '2026-02-10 09:10-05', NULL, true),
        ('Lácteos La Pradera S.A.S.',   'MO_INT_AUD',   '2026-02-10 09:11-05', NULL, true),
        ('Comercializadora Andina Ltda.','MO_POL_PROG', '2026-02-20 09:10-05', NULL, true),
        ('Servicios Mineros del Alto S.A.S.','MO_INT_AUD',  '2026-03-01 09:10-05', NULL, true),
        ('Servicios Mineros del Alto S.A.S.','MO_MFG_VIAL', '2026-03-01 09:11-05', '2026-05-31 17:00-05', false),
        ('Fríos del Valle S.A.S.',      'MO_MFG_RISK',  '2026-03-10 09:10-05', NULL, true),
        ('Consultores SST Elite S.A.S.','MO_POL_PROG',  '2026-03-15 09:10-05', NULL, true),
        ('Consultores SST Elite S.A.S.','MO_INT_AUD',   '2026-03-15 09:11-05', NULL, true),
        ('Logística Ferrico S.A.S.',    'MO_POL_VIAL',  '2026-03-25 09:10-05', NULL, true),
        ('Logística Ferrico S.A.S.',    'MO_MFG_VIAL',  '2026-03-25 09:11-05', '2026-06-30 17:00-05', false),
        ('Bodegas Interamericana Ltda.','MO_POL_PROG',  '2025-07-15 09:10-05', NULL, true),
        ('Bodegas Interamericana Ltda.','MO_MFG_RISK',  '2025-07-15 09:11-05', NULL, true),
        ('Bodegas Interamericana Ltda.','MO_INT_AUD',   '2025-07-15 09:12-05', NULL, true)
    ) AS v(tenant_name, module_code, enabled_at, disabled_at, is_active)
    INNER JOIN tenants AS t ON t.legal_name = v.tenant_name
    INNER JOIN modules AS m ON m.code = v.module_code
    RETURNING 1
)
SELECT 'Habilitaciones de módulo insertadas: ' || count(*) FROM new_modules;

-- =============================================================================
-- 6. ASIGNACIONES DE PLANTILLAS (45)
--    Dos organizaciones con módulos pero SIN plantillas (Consultores SST Elite
--    y Logística Ferrico); una asignación inactiva; responsables siempre de la
--    misma organización (FK compuesta).
-- =============================================================================

WITH new_tt AS (
    INSERT INTO tenanttemplates (tenant_id, template_id, assigned_at, due_date,
                                 responsible_person_id, assigned_by_person_id,
                                 notes, is_active, created_at, updated_at)
    SELECT t.id,
           tp.id,
           v.assigned_at::timestamptz,
           v.due_date::date,
           resp.id,
           asg.id,
           v.notes,
           v.is_active,
           v.assigned_at::timestamptz,
           v.assigned_at::timestamptz
    FROM (VALUES
        ('Andes Construcciones S.A.S.',      'TEM_POLITICA_SST',    '2025-03-10 10:00-05', '2025-12-20', 'Jefe de SST',    'Gerente General', 'Aprobada por comité.',        true),
        ('Andes Construcciones S.A.S.',      'TEM_OBJETIVOS_SST',   '2025-03-12 10:00-05', '2025-12-20', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Andes Construcciones S.A.S.',      'TEM_IDENT_PELIGROS',  '2025-03-15 10:00-05', '2025-12-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Andes Construcciones S.A.S.',      'TEM_MAPA_RIESGOS',    '2025-03-15 10:05-05', '2025-12-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Andes Construcciones S.A.S.',      'TEM_INSP_PLANEADA',   '2025-04-01 10:00-05', '2026-06-30', 'Jefe de SST',    'Gerente General', 'Mensual.',                    true),
        ('Andes Construcciones S.A.S.',      'TEM_AUD_INTERNA',     '2025-06-01 10:00-05', '2026-04-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Andes Construcciones S.A.S.',      'TEM_REV_DIRECCION',   '2025-09-01 10:00-05', '2026-09-30', 'Jefe de SST',    'Gerente General', 'Semiannal.',                  true),
        ('Andes Construcciones S.A.S.',      'TEM_COMITE_VIGIA',    '2025-09-10 10:00-05', '2026-09-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Andes Construcciones S.A.S.',      'TEM_POLITICA_PESV',   '2025-03-20 10:00-05', '2026-03-31', 'Coordinador PESV','Gerente General','PESV de flota propia.',       true),
        ('Andes Construcciones S.A.S.',      'TEM_PLAN_ANUAL',      '2025-04-05 10:00-05', '2026-04-30', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_POLITICA_SST',    '2025-05-01 09:00-05', '2026-05-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_POLITICA_SST_V1', '2025-05-01 09:05-05', '2025-12-31', 'Jefe de SST',    'Gerente General', 'Versión histórica v1.',       true),
        ('Petrolera Llanos S.A.',            'TEM_IDENT_PELIGROS',  '2025-05-10 09:00-05', '2026-05-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_MAPA_RIESGOS',    '2025-05-10 09:05-05', '2026-05-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_INSP_PLANEADA',   '2025-06-01 09:00-05', '2026-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_INDICADORES',     '2025-06-15 09:00-05', '2026-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_POLITICA_PESV',   '2025-04-10 09:00-05', '2026-04-30', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_DIAG_PESV',       '2025-04-12 09:00-05', '2025-12-31', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_PLAN_ANUAL',      '2025-04-15 09:00-05', '2026-04-30', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_REV_PESV',        '2025-11-01 09:00-05', '2026-11-30', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_IND_PESV',        '2025-11-10 09:00-05', '2026-11-30', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Petrolera Llanos S.A.',            'TEM_INVEST_EVENTOS',  '2026-02-01 09:00-05', '2027-01-31', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Metales del Caribe S.A.S.',        'TEM_MAPA_RIESGOS',    '2025-07-01 09:00-05', '2026-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Metales del Caribe S.A.S.',        'TEM_IDENT_PELIGROS',  '2025-07-01 09:05-05', '2026-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Alimentos Santander S.A.S.',       'TEM_POLITICA_SST',    '2025-08-01 09:00-05', '2026-07-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Textiles del Norte S.A.S.',        'TEM_IDENT_PELIGROS',  '2025-09-15 09:00-05', '2026-09-14', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Transportes Andinos S.A.S.',       'TEM_POLITICA_PESV',   '2026-07-02 09:00-05', '2027-06-30', 'Coordinador PESV','Gerente General','Asignación de 2026.',         true),
        ('Transportes Andinos S.A.S.',       'TEM_MAPA_RIESGOS',    '2026-07-02 09:05-05', '2027-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Clínica Vitalis Bucaramanga S.A.', 'TEM_MAPA_RIESGOS',    '2026-07-10 09:00-05', '2027-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Agroindustrias del Café S.A.S.',   'TEM_IDENT_PELIGROS',  '2026-02-01 09:00-05', '2027-01-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Constructora Cívica S.A.S.',       'TEM_POLITICA_SST',    '2026-02-05 09:00-05', '2027-01-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Distribuidora Café Soft Ltda.',    'TEM_PLAN_ANUAL',      '2026-02-10 09:00-05', '2027-01-31', 'Coordinador PESV','Gerente General',NULL,                          true),
        ('Lácteos La Pradera S.A.S.',        'TEM_POLITICA_SST',    '2026-02-15 09:00-05', '2027-02-14', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Comercializadora Andina Ltda.',    'TEM_POLITICA_SST',    '2026-03-01 09:00-05', '2027-02-28', 'Gerente General','Gerente General', NULL,                          true),
        ('Servicios Mineros del Alto S.A.S.','TEM_MAPA_RIESGOS',    '2026-03-05 09:00-05', '2027-03-04', 'Coordinador de Campo','Gerente General',NULL,                    true),
        ('Fríos del Valle S.A.S.',           'TEM_POLITICA_SST',    '2026-03-12 09:00-05', '2027-03-11', 'Gerente General','Gerente General', NULL,                          true),
        ('Logística Ferrico S.A.S.',         'TEM_POLITICA_PESV',   '2026-04-01 09:00-05', '2027-03-31', 'Coordinador PESV','Gerente General','Asignación inicial',            true),
        ('Hotel Casa Real S.A.',             'TEM_POLITICA_SST',    '2025-06-10 09:00-05', '2026-05-31', 'Jefe de SST',    'Gerente General', 'Retirada con la organización.',true),
        ('Hotel Casa Real S.A.',             'TEM_MAPA_RIESGOS',    '2025-06-12 09:00-05', '2026-05-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Hotel Casa Real S.A.',             'TEM_IDENT_PELIGROS',  '2025-06-12 09:05-05', '2026-05-31', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Hotel Casa Real S.A.',             'TEM_INVEST_ACCID',    '2025-07-01 09:00-05', '2026-06-30', 'Jefe de SST',    'Gerente General', NULL,                          true),
        ('Hotel Casa Real S.A.',             'TEM_REP_INSPEC_EQ',   '2025-07-01 09:05-05', '2026-06-30', 'Jefe de SST',    'Gerente General', 'Descontinuada.',              false),
        ('Bodegas Interamericana Ltda.',     'TEM_POLITICA_SST',    '2025-08-01 09:00-05', '2026-07-31', 'Gerente General','Gerente General', NULL,                          true),
        ('Torre Fashion Imports Ltda.',      'TEM_POLITICA_SST',    '2026-06-20 09:00-05', '2027-06-19', 'Gerente General','Gerente General', 'Sin sistema habilitado.',     true)
    ) AS v(tenant_name, template_code, assigned_at, due_date,
           resp_position, asg_position, notes, is_active)
    INNER JOIN tenants   AS t   ON t.legal_name  = v.tenant_name
    INNER JOIN templates AS tp  ON tp.code = v.template_code
    INNER JOIN LATERAL (SELECT p.id FROM persons AS p
                        INNER JOIN positions AS pos ON pos.id = p.position_id
                        WHERE p.tenant_id = t.id AND pos.name = v.resp_position
                        LIMIT 1) AS resp ON true
    INNER JOIN LATERAL (SELECT p.id FROM persons AS p
                        INNER JOIN positions AS pos ON pos.id = p.position_id
                        WHERE p.tenant_id = t.id AND pos.name = v.asg_position
                        LIMIT 1) AS asg ON true
    RETURNING id, tenant_id
)
SELECT 'Asignaciones insertadas: ' || count(*) FROM new_tt;

-- =============================================================================
-- 7. DOCUMENTOS (46 filas; 43 vigentes: 19 finalizados, 13 borrador,
--    11 no iniciado; 3 versiones históricas en tt1 y tt5 de t1)
-- =============================================================================

INSERT INTO documents (tenanttemplate_id, version, title, state, content,
                       started_at, finished_at, is_active, created_at, updated_at)
SELECT tt.id,
       v.doc_version,
       v.doc_title,
       v.doc_state,
       CASE WHEN v.doc_content IS NULL OR btrim(v.doc_content) = '' THEN NULL
            ELSE v.doc_content::jsonb END,
       v.started_at::timestamptz,
       v.finished_at::timestamptz,
       v.doc_active,
       COALESCE(v.started_at::timestamptz, v.row_created::timestamptz), 
       COALESCE(v.finished_at::timestamptz, COALESCE(v.started_at::timestamptz, v.row_created::timestamptz))
FROM (VALUES
    -- t1: Política SST v1 (fin, histórica) y v2 (fin, histórica) y v3 (borrador, vigente)
    ('Andes Construcciones S.A.S.', 'TEM_POLITICA_SST',  1, 'Política de SST',                'finalizado',  '{"aprobada": true, "comite": "2025-05-20", "version": 1}', '2025-03-11 08:00-05', '2025-06-15 16:00-05', false, '2025-03-10 10:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_POLITICA_SST',  2, 'Política de SST (revisión 2026)','finalizado',  '{"aprobada": true, "comite": "2026-02-28", "version": 2}', '2026-01-15 08:00-05', '2026-03-10 15:30-05', false, '2026-01-10 10:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_POLITICA_SST',  3, 'Política de SST (revisión 2027)','borrador',    NULL,                                                        '2026-07-05 08:00-05', NULL,                  true,  '2026-07-05 08:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_OBJETIVOS_SST', 1, 'Objetivos del SG-SST',           'borrador',    NULL,                                                        '2026-08-01 09:00-05', NULL,                  true,  '2026-08-01 09:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_IDENT_PELIGROS',1, 'Identificación de peligros',     'finalizado',  '{"peligros": 42, "tareas": 18, "metodo": "GTC 45"}',        '2025-04-02 08:00-05', '2025-08-30 17:00-05', true,  '2025-04-02 08:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_MAPA_RIESGOS',  1, 'Matriz de riesgos',              'no_iniciado', NULL,                                                        NULL,                  NULL,                  true,  '2026-08-15 09:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_INSP_PLANEADA', 1, 'Inspecciones planeadas',         'finalizado',  '{"inspecciones": 12, "hallazgos": 7}',                      '2025-04-03 08:00-05', '2025-09-20 14:00-05', false, '2025-04-03 08:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_INSP_PLANEADA', 2, 'Inspecciones planeadas (revisión)','borrador',  NULL,                                                        '2026-05-11 08:30-05', NULL,                  true,  '2026-05-11 08:30-05'),
    ('Andes Construcciones S.A.S.', 'TEM_AUD_INTERNA',   1, 'Auditoría interna',              'finalizado',  '{"hallazgos_mayores": 1, "hallazgos_menores": 4}',          '2025-07-01 08:00-05', '2025-11-15 12:00-05', true,  '2025-07-01 08:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_REV_DIRECCION', 1, 'Revisión por la dirección',      'no_iniciado', NULL,                                                        NULL,                  NULL,                  true,  '2026-08-20 09:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_COMITE_VIGIA',  1, 'Actas de comité y vigías',       'borrador',    NULL,                                                        '2026-09-01 08:00-05', NULL,                  true,  '2026-09-01 08:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_POLITICA_PESV', 1, 'Política de seguridad vial',     'finalizado',  '{"flota": 18, "conductores": 12}',                          '2025-03-25 08:00-05', '2025-10-10 11:00-05', true,  '2025-03-25 08:00-05'),
    ('Andes Construcciones S.A.S.', 'TEM_PLAN_ANUAL',    1, 'Plan anual de seguridad vial',   'borrador',    NULL,                                                        '2026-06-20 08:00-05', NULL,                  true,  '2026-06-20 08:00-05'),
    -- t2: 9 finalizados, 1 borrador, 1 no iniciado (90 % de cumplimiento)
    ('Petrolera Llanos S.A.', 'TEM_POLITICA_SST',    1, 'Política de SST',             'finalizado',  '{"aprobada": true, "iso_45001": true}',               '2025-05-02 08:00-05', '2025-10-05 16:00-05', true, '2025-05-02 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_POLITICA_SST_V1', 1, 'Política SG-SST (v1 histórica)','no_iniciado',NULL,                                                   NULL,                  NULL,                  true, '2026-08-25 09:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_IDENT_PELIGROS',  1, 'Identificación de peligros',  'finalizado',  '{"peligros": 61, "tareas": 25, "metodo": "GTC 45"}',  '2025-05-11 08:00-05', '2025-12-20 15:00-05', true, '2025-05-11 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_MAPA_RIESGOS',    1, 'Matriz de riesgos',           'borrador',    NULL,                                                   '2026-09-05 08:00-05', NULL,                  true, '2026-09-05 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_INSP_PLANEADA',   1, 'Inspecciones planeadas',      'finalizado',  '{"inspecciones": 24, "hallazgos": 9}',                '2025-06-02 08:00-05', '2026-01-30 14:00-05', true, '2025-06-02 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_INDICADORES',     1, 'Indicadores del SG-SST',      'finalizado',  '{"ausentismo": 1.2, "accidentalidad": 0.8}',          '2025-06-16 08:00-05', '2026-02-28 12:00-05', true, '2025-06-16 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_POLITICA_PESV',   1, 'Política de seguridad vial',  'finalizado',  '{"flota": 35, "conductores": 40}',                    '2025-04-11 08:00-05', '2025-09-15 11:00-05', true, '2025-04-11 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_DIAG_PESV',       1, 'Diagnóstico de gestión vial', 'finalizado',  '{"nivel": 3, "puntaje": 78}',                         '2025-04-13 08:00-05', '2025-11-20 12:00-05', true, '2025-04-13 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_PLAN_ANUAL',      1, 'Plan anual de seguridad vial','finalizado',  '{"actividades": 22}',                                 '2025-04-16 08:00-05', '2026-03-15 10:00-05', true, '2025-04-16 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_REV_PESV',        1, 'Revisión del PESV',           'finalizado',  '{"conclusiones": "avance satisfactorio"}',            '2025-11-02 08:00-05', '2026-04-10 13:00-05', true, '2025-11-02 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_IND_PESV',        1, 'Indicadores del PESV',        'finalizado',  '{"obs": "sin vencimientos"}',                     '2025-11-11 08:00-05', '2026-05-12 10:30-05', true, '2025-11-11 08:00-05'),
    ('Petrolera Llanos S.A.', 'TEM_INVEST_EVENTOS',  1, 'Investigación de eventos viales','no_iniciado',NULL,                                                 NULL,                  NULL,                  true, '2026-08-28 09:00-05'),
    -- t3: mapa con 2 versiones (v1 no iniciado histórico, v2 borrador vigente) + ident finalizado
    ('Metales del Caribe S.A.S.', 'TEM_MAPA_RIESGOS',   1, 'Matriz de riesgos',          'no_iniciado', NULL, NULL,                  NULL,                  false, '2025-07-01 09:00-05'),
    ('Metales del Caribe S.A.S.', 'TEM_MAPA_RIESGOS',   2, 'Matriz de riesgos (v2)',     'borrador',    NULL, '2026-08-10 08:00-05', NULL,                  true,  '2026-08-10 08:00-05'),
    ('Metales del Caribe S.A.S.', 'TEM_IDENT_PELIGROS', 1, 'Identificación de peligros', 'finalizado',  '{"peligros": 25, "metodo": "GTC 45"}', '2025-07-02 08:00-05', '2025-12-18 14:00-05', true, '2025-07-02 08:00-05'),
    -- t4: política v1 no iniciado e inactiva + v2 borrador vigente
    ('Alimentos Santander S.A.S.', 'TEM_POLITICA_SST', 1, 'Política de SST',          'no_iniciado', NULL, NULL,                  NULL,                  false, '2025-08-01 09:00-05'),
    ('Alimentos Santander S.A.S.', 'TEM_POLITICA_SST', 2, 'Política de SST (v2)',     'borrador',    NULL, '2026-09-02 08:00-05', NULL,                  true,  '2026-09-02 08:00-05'),
    ('Textiles del Norte S.A.S.', 'TEM_IDENT_PELIGROS', 1, 'Identificación de peligros', 'finalizado', '{"peligros": 31, "metodo": "GTC 45"}', '2025-09-16 08:00-05', '2026-02-27 16:00-05', true, '2025-09-16 08:00-05'),
    ('Transportes Andinos S.A.S.', 'TEM_POLITICA_PESV', 1, 'Política de seguridad vial', 'finalizado', '{"flota": 12, "conductores": 15}', '2026-07-03 08:00-05', '2026-08-25 15:00-05', true, '2026-07-03 08:00-05'),
    ('Transportes Andinos S.A.S.', 'TEM_MAPA_RIESGOS',  1, 'Matriz de riesgos',          'borrador',   NULL, '2026-08-12 08:00-05', NULL,                  true,  '2026-08-12 08:00-05'),
    ('Clínica Vitalis Bucaramanga S.A.', 'TEM_MAPA_RIESGOS', 1, 'Matriz de riesgos', 'no_iniciado', NULL, NULL, NULL, true, '2026-07-10 09:00-05'),
    ('Agroindustrias del Café S.A.S.', 'TEM_IDENT_PELIGROS', 1, 'Identificación de peligros', 'finalizado', '{"peligros": 14, "metodo": "GTC 45"}', '2026-02-02 08:00-05', '2026-06-18 13:00-05', true, '2026-02-02 08:00-05'),
    ('Constructora Cívica S.A.S.', 'TEM_POLITICA_SST', 1, 'Política de SST', 'no_iniciado', NULL, NULL, NULL, true, '2026-09-06 09:00-05'),
    ('Distribuidora Café Soft Ltda.', 'TEM_PLAN_ANUAL', 1, 'Plan anual de seguridad vial', 'borrador', NULL, '2026-09-08 08:00-05', NULL, true, '2026-09-08 08:00-05'),
    ('Lácteos La Pradera S.A.S.', 'TEM_POLITICA_SST', 1, 'Política de SST', 'finalizado', '{"aprobada": true}', '2026-02-16 08:00-05', '2026-05-20 11:00-05', true, '2026-02-16 08:00-05'),
    ('Comercializadora Andina Ltda.', 'TEM_POLITICA_SST', 1, 'Política de SST', 'no_iniciado', NULL, NULL, NULL, true, '2026-09-10 09:00-05'),
    ('Servicios Mineros del Alto S.A.S.', 'TEM_MAPA_RIESGOS', 1, 'Matriz de riesgos', 'finalizado', '{"peligros": 19, "metodo": "GTC 45"}', '2026-03-06 08:00-05', '2026-07-22 14:00-05', true, '2026-03-06 08:00-05'),
    ('Fríos del Valle S.A.S.', 'TEM_POLITICA_SST', 1, 'Política de SST', 'borrador', NULL, '2026-09-12 08:00-05', NULL, true, '2026-09-12 08:00-05'),
    ('Logística Ferrico S.A.S.', 'TEM_POLITICA_PESV', 1, 'Política de seguridad vial', 'no_iniciado', NULL, NULL, NULL, true, '2026-09-14 09:00-05'),
    ('Hotel Casa Real S.A.', 'TEM_POLITICA_SST',   1, 'Política de SST',              'finalizado',  '{"aprobada": true}', '2025-06-11 08:00-05', '2025-10-25 12:00-05', true, '2025-06-11 08:00-05'),
    ('Hotel Casa Real S.A.', 'TEM_MAPA_RIESGOS',   1, 'Matriz de riesgos',            'borrador',    NULL, '2025-06-13 08:00-05', NULL,                  true, '2025-06-13 08:00-05'),
    ('Hotel Casa Real S.A.', 'TEM_IDENT_PELIGROS', 1, 'Identificación de peligros',   'no_iniciado', NULL, NULL,                  NULL,                  true, '2025-12-01 09:00-05'),
    ('Bodegas Interamericana Ltda.', 'TEM_POLITICA_SST', 1, 'Política de SST', 'borrador', NULL, '2025-08-02 08:00-05', NULL, true, '2025-08-02 08:00-05'),
    ('Torre Fashion Imports Ltda.', 'TEM_POLITICA_SST', 1, 'Política de SST', 'no_iniciado', NULL, NULL, NULL, true, '2026-09-15 09:00-05')
) AS v(tenant_name, template_code, doc_version, doc_title, doc_state, doc_content,
       started_at, finished_at, doc_active, row_created)
INNER JOIN tenants         AS t  ON t.legal_name = v.tenant_name
INNER JOIN templates       AS tp ON tp.code = v.template_code
INNER JOIN tenanttemplates AS tt ON tt.tenant_id = t.id AND tt.template_id = tp.id;

-- =============================================================================
-- 8. EVALUACIONES (13; uq por tenant+template+fecha; score 0–max_score)
-- =============================================================================

INSERT INTO evaluations (tenant_id, template_id, evaluation_date, score, max_score,
                         evaluator_person_id, observations, is_active, created_at, updated_at)
SELECT t.id, tp.id, v.evaluation_date::date, v.score, v.max_score,
       ev.id, v.observations, true, v.evaluation_date::timestamptz + interval '17 hours',
       v.evaluation_date::timestamptz + interval '17 hours'
FROM (VALUES
    ('Andes Construcciones S.A.S.',      'TEM_POLITICA_SST',    '2026-02-10', 92.50, 100, 'Jefe de SST', 'Cumplimiento alto; política socializada.'),
    ('Andes Construcciones S.A.S.',      'TEM_IDENT_PELIGROS',  '2026-02-15', 88.00, 100, 'Jefe de SST', 'Metodología GTC 45 completa.'),
    ('Andes Construcciones S.A.S.',      'TEM_MAPA_RIESGOS',    '2026-04-20', 75.50, 100, 'Jefe de SST', 'Falta actualizar riesgos de bodega.'),
    ('Andes Construcciones S.A.S.',      'TEM_IDENT_PELIGROS',  '2025-11-10', 78.00, 100, 'Jefe de SST', 'Medición del segundo semestre 2025.'),
    ('Petrolera Llanos S.A.',            'TEM_POLITICA_PESV',   '2026-03-05', 95.00, 100, 'Jefe de SST', 'Excelente gestión vial.'),
    ('Petrolera Llanos S.A.',            'TEM_IDENT_PELIGROS',  '2026-02-15', 82.00, 100, 'Jefe de SST', NULL),
    ('Petrolera Llanos S.A.',            'TEM_MAPA_RIESGOS',    '2026-06-15', 15.00, 100, 'Jefe de SST', 'Matriz sin cerrar; prioridad 2026-II.'),
    ('Metales del Caribe S.A.S.',        'TEM_MAPA_RIESGOS',    '2026-04-20', 60.00, 100, 'Jefe de SST', 'Medio: pendientes de valoración.'),
    ('Textiles del Norte S.A.S.',        'TEM_IDENT_PELIGROS',  '2026-06-01', 45.00, 100, 'Jefe de SST', 'Requiere plan de mejora.'),
    ('Clínica Vitalis Bucaramanga S.A.', 'TEM_MAPA_RIESGOS',    '2026-05-30', 35.00, 100, 'Jefe de SST', 'Cliente nuevo; nivel bajo.'),
    ('Agroindustrias del Café S.A.S.',   'TEM_IDENT_PELIGROS',  '2026-02-15', 70.00, 100, 'Jefe de SST', 'Aceptable.'),
    ('Lácteos La Pradera S.A.S.',        'TEM_POLITICA_SST',    '2026-02-10', 55.00, 100, 'Jefe de SST', 'Medio.'),
    ('Constructora Cívica S.A.S.',       'TEM_POLITICA_SST',    '2026-05-18', 20.00, 100, 'Jefe de SST', 'Documento sin iniciar; medición temprana.')
) AS v(tenant_name, template_code, evaluation_date, score, max_score, resp_position, observations)
INNER JOIN tenants   AS t  ON t.legal_name  = v.tenant_name
INNER JOIN templates AS tp ON tp.code = v.template_code
INNER JOIN LATERAL (SELECT p.id FROM persons AS p
                    INNER JOIN positions AS pos ON pos.id = p.position_id
                    WHERE p.tenant_id = t.id AND pos.name = v.resp_position
                    LIMIT 1) AS ev ON true;

-- =============================================================================
-- 9. BLOQUEOS DE EDICIÓN (4 vigentes, 4 liberados, 1 vencido sin liberar)
-- =============================================================================

INSERT INTO editing_locks (document_id, locked_by_person_id, lock_token, locked_at,
                           expires_at, released_at, created_at, updated_at)
SELECT d.id, p.id, v.lock_token::uuid, v.locked_at::timestamptz, v.expires_at::timestamptz,
       v.released_at::timestamptz, v.locked_at::timestamptz,
       COALESCE(v.released_at::timestamptz, v.locked_at::timestamptz)
FROM (VALUES
    -- Vigentes (released_at NULL; el índice parcial permite uno por documento)
    ('Andes Construcciones S.A.S.', 'TEM_OBJETIVOS_SST',  1, 'Operario de Obra',           '0e111111-1111-4111-8111-111111111111', '2026-09-21 07:30-05', '2026-09-21 09:30-05', NULL),
    ('Petrolera Llanos S.A.',       'TEM_PLAN_ANUAL',     1, 'Operario de Producción',     '0e222222-2222-4222-8222-222222222222', '2026-09-21 08:00-05', '2026-09-21 10:00-05', NULL),
    ('Alimentos Santander S.A.S.',  'TEM_POLITICA_SST',   2, 'Auxiliar de Producción',     '0e333333-3333-4333-8333-333333333333', '2026-09-21 08:15-05', '2026-09-21 10:15-05', NULL),
    ('Petrolera Llanos S.A.',       'TEM_DIAG_PESV',      1, 'Auxiliar de Campo',          '0e444444-4444-4444-8444-444444444444', '2026-09-21 08:30-05', '2026-09-21 10:30-05', NULL),
    -- Liberados (histórico)
    ('Andes Construcciones S.A.S.', 'TEM_INSP_PLANEADA',  1, 'Operario de Obra',           '0e555555-5555-4555-8555-555555555555', '2026-05-11 08:00-05', '2026-05-11 10:00-05', '2026-05-11 09:40-05'),
    ('Metales del Caribe S.A.S.',   'TEM_IDENT_PELIGROS', 1, 'Operario de Planta',         '0e666666-6666-4666-8666-666666666666', '2025-07-03 08:00-05', '2025-07-03 10:00-05', '2025-07-03 09:50-05'),
    ('Petrolera Llanos S.A.',       'TEM_POLITICA_SST',   1, 'Supervisor de Turno',        '0e777777-7777-4777-8777-777777777777', '2025-05-03 08:00-05', '2025-05-03 11:00-05', '2025-05-03 10:30-05'),
    ('Hotel Casa Real S.A.',        'TEM_IDENT_PELIGROS', 1, 'Auxiliar de Housekeeping',   '0e888888-8888-4888-8888-888888888888', '2025-09-20 08:00-05', '2025-09-20 10:00-05', '2025-09-20 09:15-05'),
    -- Vencido SIN liberar (lo toma el trigger/fn_release_expired_locks)
    ('Metales del Caribe S.A.S.',   'TEM_MAPA_RIESGOS',   2, 'Operario de Planta',         '0e999999-9999-4999-8999-999999999999', '2026-08-15 07:00-05', '2026-08-15 09:00-05', NULL)
) AS v(tenant_name, template_code, doc_version, resp_position, lock_token,
       locked_at, expires_at, released_at)
INNER JOIN tenants         AS t  ON t.legal_name = v.tenant_name
INNER JOIN templates       AS tp ON tp.code = v.template_code
INNER JOIN tenanttemplates AS tt ON tt.tenant_id = t.id AND tt.template_id = tp.id
INNER JOIN documents       AS d  ON d.tenanttemplate_id = tt.id AND d.version = v.doc_version
INNER JOIN LATERAL (SELECT p.id FROM persons AS p
                    INNER JOIN positions AS pos ON pos.id = p.position_id
                    WHERE p.tenant_id = t.id AND pos.name = v.resp_position
                    LIMIT 1) AS p ON true;

-- =============================================================================
-- 10. AUDITORÍA (7 filas: I/U/D en tenants, U en templates)
-- =============================================================================

INSERT INTO audit_log (tenant_id, table_name, record_pk, operation, changed_at,
                       changed_by_person_id, db_user, application_name, client_addr,
                       changed_columns, old_values, new_values, extra_context)
SELECT t.id, v.table_name, COALESCE(v.record_pk, t.id::text), v.operation, v.changed_at::timestamptz,
       ch.id, 'sst_admin', 'portal-sst', '192.168.1.10'::inet,
       v.changed_columns::text[], v.old_values::jsonb, v.new_values::jsonb, v.extra_context::jsonb
FROM (VALUES
    ('Andes Construcciones S.A.S.', 'tenants', NULL, 'I', '2025-01-15 10:00:05-05',
     'Gerente General', NULL, NULL, '{"legal_name": "Andes Construcciones S.A.S.", "tax_id": "900123456"}', '{"evento": "alta_tenant"}'),
    ('Andes Construcciones S.A.S.', 'tenants', NULL, 'U', '2026-03-04 11:20:00-05',
     'Gerente General', '{email,phone}', NULL, '{"email": "contacto@andesconstrucciones.co", "phone": "6076854100"}',
     '{"evento": "cambio_datos"}'),
    ('Andes Construcciones S.A.S.', 'tenants', NULL, 'U', '2026-06-01 09:00:00-05',
     'Gerente General', '{is_active}', '{"is_active": false}', '{"is_active": true}', '{"evento": "cambio_estado"}'),
    -- NOTA: se omite la fila de auditoría sobre 'tenants' de Hotel Casa Real:
    -- esa organización no llegó a crearse (ver bug de la ciudad Cartagena).
    (NULL, 'templates', (SELECT id::text FROM templates WHERE code = 'TEM_POLITICA_SST'), 'U', '2026-01-20 10:30:00-05',
     NULL, '{name,version}', NULL, '{"name": "Política de Seguridad y Salud en el Trabajo", "version": "2.0"}',
     '{"evento": "plantilla_modificada"}'),
    (NULL, 'templates', (SELECT id::text FROM templates WHERE code = 'TEM_POLITICA_PESV'), 'U', '2026-02-11 12:00:00-05',
     NULL, '{legal_reference}', NULL, '{"legal_reference": "Resolución 40595 de 2022"}',
     '{"evento": "plantilla_modificada"}')
    -- NOTA: se omite la fila de auditoría sobre 'persons' de Hotel Casa Real:
    -- esa organización no llegó a crearse (ver bug de la ciudad Cartagena).
) AS v(tenant_name, table_name, record_pk, operation, changed_at,
       resp_position, changed_columns, old_values, new_values, extra_context)
LEFT JOIN tenants  AS t  ON t.legal_name = v.tenant_name
LEFT JOIN LATERAL (SELECT p.id FROM persons AS p
                   INNER JOIN positions AS pos ON pos.id = p.position_id
                   WHERE p.tenant_id = t.id AND pos.name = v.resp_position
                   LIMIT 1) AS ch ON true;

-- Recordatorio: la fila de auditoría sobre templates usa changed_columns como
-- array JSON; la convertimos con comillas simples (ver arriba).

COMMIT;

-- =============================================================================
-- VERIFICACIÓN (fuera de la transacción): conteo de filas por tabla
-- =============================================================================
SELECT 'type_system_sst' AS tabla, count(*) AS filas FROM type_system_sst
UNION ALL SELECT 'phva_stages',     count(*) FROM phva_stages
UNION ALL SELECT 'tenant_sizes',    count(*) FROM tenant_sizes
UNION ALL SELECT 'countries',       count(*) FROM countries
UNION ALL SELECT 'departments',     count(*) FROM departments
UNION ALL SELECT 'cities',          count(*) FROM cities
UNION ALL SELECT 'modules',         count(*) FROM modules
UNION ALL SELECT 'tenants',         count(*) FROM tenants
UNION ALL SELECT 'positions',       count(*) FROM positions
UNION ALL SELECT 'persons',         count(*) FROM persons
UNION ALL SELECT 'tenantsystems',   count(*) FROM tenantsystems
UNION ALL SELECT 'tenant_modules',  count(*) FROM tenant_modules
UNION ALL SELECT 'templates',       count(*) FROM templates
UNION ALL SELECT 'formats_sst',     count(*) FROM formats_sst
UNION ALL SELECT 'tenanttemplates', count(*) FROM tenanttemplates
UNION ALL SELECT 'documents',       count(*) FROM documents
UNION ALL SELECT 'evaluations',     count(*) FROM evaluations
UNION ALL SELECT 'editing_locks',   count(*) FROM editing_locks
UNION ALL SELECT 'audit_log',       count(*) FROM audit_log
ORDER BY tabla;
