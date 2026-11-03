-- =============================================================================
-- Parcelas, propietarios y convenios (contratos) de Aguiluchos. UN SOLO PASO.
--
-- Ejecutar una vez en: Supabase Dashboard > SQL Editor (proyecto compartido con
-- grefa-proyectos). Es idempotente. Requiere haber ejecutado antes
-- `activar_acceso_grefa.sql` (usa sus funciones es_usuario_grefa() y
-- es_admin_aguiluchos()). Solo crea tablas nuevas `*_grefa` y el bucket privado
-- `contratos`: no toca nidos_grefa ni nada de grefa-proyectos.
--
-- Modelo:
--   * Un convenio es por PROPIETARIO (titular) y CAMPAÑA y puede cubrir varias
--     parcelas (una línea por parcela, con sus códigos de ayuda).
--   * Una parcela solo puede estar en un convenio por campaña.
--   * Permisos: hoy todos los usuarios @grefa.org leen y escriben; solo el
--     administrador borra. Para introducir roles más adelante basta con cambiar
--     la función public.puede_gestionar_contratos().
--   * IBAN: NUNCA se guarda completo; solo `iban_enmascarado` (últimos 4 dígitos).
-- =============================================================================

-- Punto único de permisos (cambiar aquí cuando haya roles) -------------------
create or replace function public.puede_gestionar_contratos()
returns boolean
language sql stable
as $$ select public.es_usuario_grefa() $$;

create or replace function public.contratos_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 1) Propietarios --------------------------------------------------------------
create table if not exists public.propietarios_grefa (
  id               uuid primary key default gen_random_uuid(),
  nombre           text not null,
  tipo             text not null default 'particular'
                     check (tipo in ('particular', 'representante', 'entidad')),
  entidad          text,            -- C.B. / SAT / ayuntamiento que representa
  nif              text,
  regepa           text,
  telefono         text,
  email            text,
  direccion        text,
  iban_enmascarado text check (iban_enmascarado is null or iban_enmascarado ~ '^[• ]+[A-Za-z0-9]{4}$'),  -- p. ej. •••• •••• •••• •••• •••• 2447 (la BD rechaza un IBAN completo)
  rgpd_firmado     boolean not null default false,
  rgpd_fecha       date,
  notas            text,
  created_by       text default (auth.jwt() ->> 'email'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists propietarios_grefa_nif_uq
  on public.propietarios_grefa (upper(regexp_replace(nif, '[^A-Za-z0-9]', '', 'g')))
  where nif is not null and nif <> '';

-- 2) Parcelas ------------------------------------------------------------------
create table if not exists public.parcelas_grefa (
  id                    uuid primary key default gen_random_uuid(),
  pais                  text not null default 'España',
  provincia             text,
  municipio             text,
  sigpac_provincia      text,
  sigpac_municipio      text,       -- código de municipio (MUN)
  sigpac_agregado       text,       -- AGR
  sigpac_zona           text,       -- ZONA
  sigpac_poligono       text,       -- POL
  sigpac_parcela        text,       -- PAR
  sigpac_recinto        text,       -- REC
  referencia_catastral  text,       -- texto libre: admite también referencias de Portugal
  superficie_ha         numeric(12, 4),
  uso                   text,
  lat                   double precision,
  lon                   double precision,
  zona_programa         text,       -- p. ej. «Zona 4 - La Sagra Madrileña»
  notas                 text,
  created_by            text default (auth.jwt() ->> 'email'),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create unique index if not exists parcelas_grefa_sigpac_uq
  on public.parcelas_grefa (
    pais, coalesce(sigpac_provincia, ''), coalesce(sigpac_municipio, ''), coalesce(sigpac_agregado, ''),
    coalesce(sigpac_zona, ''), coalesce(sigpac_poligono, ''), coalesce(sigpac_parcela, ''),
    coalesce(sigpac_recinto, ''))
  where sigpac_poligono is not null and sigpac_parcela is not null;
create index if not exists parcelas_grefa_refcat_ix
  on public.parcelas_grefa (upper(regexp_replace(referencia_catastral, '[^A-Za-z0-9]', '', 'g')))
  where referencia_catastral is not null;

-- Titularidad (una parcela puede tener varios propietarios)
create table if not exists public.parcela_propietarios_grefa (
  parcela_id     uuid not null references public.parcelas_grefa (id) on delete cascade,
  propietario_id uuid not null references public.propietarios_grefa (id) on delete cascade,
  porcentaje     numeric(5, 2) check (porcentaje is null or (porcentaje > 0 and porcentaje <= 100)),
  primary key (parcela_id, propietario_id)
);

-- Vínculo nido -> parcela (si no basta con la referencia catastral del nido)
create table if not exists public.nido_parcela_grefa (
  nido_id    uuid primary key references public.nidos_grefa (id) on delete cascade,
  parcela_id uuid not null references public.parcelas_grefa (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- 3) Catálogo de ayudas (códigos 1-9 del convenio) ------------------------------
create table if not exists public.ayudas_grefa (
  id          uuid primary key default gen_random_uuid(),
  programa    text not null,
  campana     integer not null,
  codigo      integer not null check (codigo between 1 and 99),
  descripcion text,
  unidad      text not null default 'fijo' check (unidad in ('ha', 'anual', 'fijo', 'variable')),
  importe     numeric(12, 2),            -- null en las variables (p. ej. lonja)
  nota        text,
  unique (programa, campana, codigo)
);

-- 4) Convenios -----------------------------------------------------------------
create table if not exists public.contratos_grefa (
  id                 uuid primary key default gen_random_uuid(),
  propietario_id     uuid not null references public.propietarios_grefa (id),
  campana            integer not null check (campana between 2000 and 2100),
  programa           text,
  zona_programa      text,
  estado             text not null default 'borrador'
                       check (estado in ('borrador', 'enviado', 'firmado', 'caducado', 'rechazado')),
  fecha_firma        date,
  vigencia_desde     date,
  vigencia_hasta     date,
  importe_total      numeric(12, 2),
  pct_firma          integer not null default 60 check (pct_firma between 0 and 100),
  lugar_firma        text,
  firmante_grefa     text,
  cargo_firmante     text,
  observaciones      text,
  created_by         text default (auth.jwt() ->> 'email'),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists contratos_grefa_prop_ix on public.contratos_grefa (propietario_id);
create index if not exists contratos_grefa_campana_ix on public.contratos_grefa (campana);

create table if not exists public.contrato_parcelas_grefa (
  id            uuid primary key default gen_random_uuid(),
  contrato_id   uuid not null references public.contratos_grefa (id) on delete cascade,
  parcela_id    uuid not null references public.parcelas_grefa (id),
  campana       integer not null,                 -- copia de contratos_grefa.campana (la rellena un trigger)
  superficie_ha numeric(12, 4),
  uso           text,
  ayudas        integer[] not null default '{}',  -- códigos de ayuda aplicados
  importe       numeric(12, 2)
);
-- Una parcela solo puede estar en un convenio por campaña.
create unique index if not exists contrato_parcelas_grefa_uq
  on public.contrato_parcelas_grefa (parcela_id, campana);
create index if not exists contrato_parcelas_grefa_contrato_ix
  on public.contrato_parcelas_grefa (contrato_id);

create or replace function public.contrato_parcelas_set_campana()
returns trigger language plpgsql as $$
begin
  select campana into new.campana from public.contratos_grefa where id = new.contrato_id;
  return new;
end;
$$;
drop trigger if exists contrato_parcelas_set_campana on public.contrato_parcelas_grefa;
create trigger contrato_parcelas_set_campana
  before insert or update of contrato_id on public.contrato_parcelas_grefa
  for each row execute function public.contrato_parcelas_set_campana();

create or replace function public.contratos_propagar_campana()
returns trigger language plpgsql as $$
begin
  if new.campana is distinct from old.campana then
    update public.contrato_parcelas_grefa set campana = new.campana where contrato_id = new.id;
  end if;
  return new;
end;
$$;
drop trigger if exists contratos_propagar_campana on public.contratos_grefa;
create trigger contratos_propagar_campana
  after update of campana on public.contratos_grefa
  for each row execute function public.contratos_propagar_campana();

-- Pagos / compensación económica del convenio
create table if not exists public.contrato_pagos_grefa (
  id              uuid primary key default gen_random_uuid(),
  contrato_id     uuid not null references public.contratos_grefa (id) on delete cascade,
  concepto        text not null,
  importe         numeric(12, 2) not null,
  fecha_prevista  date,
  fecha_pago      date,
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'pagado')),
  notas           text,
  created_at      timestamptz not null default now()
);
create index if not exists contrato_pagos_grefa_contrato_ix on public.contrato_pagos_grefa (contrato_id);

-- Documentos subidos (el archivo vive en el bucket privado `contratos`)
create table if not exists public.contrato_documentos_grefa (
  id             uuid primary key default gen_random_uuid(),
  contrato_id    uuid references public.contratos_grefa (id) on delete cascade,
  propietario_id uuid references public.propietarios_grefa (id) on delete cascade,
  tipo           text not null default 'convenio_firmado'
                   check (tipo in ('convenio_firmado', 'consentimiento_rgpd', 'dni', 'titularidad_cuenta',
                                   'hoja_catastral', 'croquis_sigpac', 'otro')),
  nombre         text not null,
  storage_path   text not null unique,
  mime           text,
  tamano         bigint,
  sha256         text,
  extraccion     jsonb,                 -- datos leídos con OCR local (IBAN ya enmascarado)
  subido_por     text default (auth.jwt() ->> 'email'),
  created_at     timestamptz not null default now()
);
create index if not exists contrato_documentos_grefa_contrato_ix on public.contrato_documentos_grefa (contrato_id);

-- Triggers de updated_at
drop trigger if exists propietarios_touch on public.propietarios_grefa;
create trigger propietarios_touch before update on public.propietarios_grefa
  for each row execute function public.contratos_touch_updated_at();
drop trigger if exists parcelas_touch on public.parcelas_grefa;
create trigger parcelas_touch before update on public.parcelas_grefa
  for each row execute function public.contratos_touch_updated_at();
drop trigger if exists contratos_touch on public.contratos_grefa;
create trigger contratos_touch before update on public.contratos_grefa
  for each row execute function public.contratos_touch_updated_at();

-- 5) RLS: leer/escribir con puede_gestionar_contratos(); borrar solo el admin ---
do $$
declare
  t text;
  libres text[] := array['contrato_parcelas_grefa', 'contrato_pagos_grefa', 'nido_parcela_grefa', 'parcela_propietarios_grefa'];
begin
  foreach t in array array[
    'propietarios_grefa', 'parcelas_grefa', 'parcela_propietarios_grefa', 'nido_parcela_grefa',
    'ayudas_grefa', 'contratos_grefa', 'contrato_parcelas_grefa', 'contrato_pagos_grefa',
    'contrato_documentos_grefa'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('drop policy if exists %I on public.%I', t || '_ins', t);
    execute format('drop policy if exists %I on public.%I', t || '_upd', t);
    execute format('drop policy if exists %I on public.%I', t || '_del', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.puede_gestionar_contratos())', t || '_sel', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.puede_gestionar_contratos())', t || '_ins', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.puede_gestionar_contratos()) with check (public.puede_gestionar_contratos())', t || '_upd', t);
    if t = any (libres) then
      -- líneas, pagos y vínculos se editan al preparar el convenio
      execute format('create policy %I on public.%I for delete to authenticated using (public.puede_gestionar_contratos())', t || '_del', t);
    else
      execute format('create policy %I on public.%I for delete to authenticated using (public.es_admin_aguiluchos())', t || '_del', t);
    end if;
    execute format('revoke all on public.%I from anon', t);
  end loop;
end
$$;

-- 6) Bucket privado `contratos` -------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contratos', 'contratos', false, 26214400,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/webp',
              'application/msword',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "contratos_sel" on storage.objects;
drop policy if exists "contratos_ins" on storage.objects;
drop policy if exists "contratos_upd" on storage.objects;
drop policy if exists "contratos_del" on storage.objects;
create policy "contratos_sel" on storage.objects for select to authenticated
  using (bucket_id = 'contratos' and public.puede_gestionar_contratos());
create policy "contratos_ins" on storage.objects for insert to authenticated
  with check (bucket_id = 'contratos' and public.puede_gestionar_contratos());
create policy "contratos_upd" on storage.objects for update to authenticated
  using (bucket_id = 'contratos' and public.puede_gestionar_contratos())
  with check (bucket_id = 'contratos' and public.puede_gestionar_contratos());
create policy "contratos_del" on storage.objects for delete to authenticated
  using (bucket_id = 'contratos' and public.es_admin_aguiluchos());

-- 7) Catálogo inicial de ayudas (modelo «Compensatorias esteparias», CAM, 2025) ---
-- Las descripciones salen del Anexo I del convenio: editar en el panel (Contratos >
-- Catálogo de ayudas) cuando se disponga de ellas.
insert into public.ayudas_grefa (programa, campana, codigo, descripcion, unidad, importe, nota) values
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 1, 'Ayuda 1 (descripción pendiente: Anexo I)', 'ha',       300, null),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 2, 'Ayuda 2 (descripción pendiente: Anexo I)', 'anual',    400, null),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 3, 'Ayuda 3 (descripción pendiente: Anexo I)', 'anual',    375, null),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 4, 'Ayuda 4 (descripción pendiente: Anexo I)', 'fijo',     400, null),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 5, 'Ayuda 5 (descripción pendiente: Anexo I)', 'fijo',     100, null),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 6, 'Ayuda 6 (descripción pendiente: Anexo I)', 'fijo',     250, null),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 7, 'Ayuda 7 (descripción pendiente: Anexo I)', 'variable', null, 'Lonja a 07/07'),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 8, 'Ayuda 8 (descripción pendiente: Anexo I)', 'ha',       150, 'o 200 €/ha según el supuesto'),
  ('Compensatorias esteparias · Comunidad de Madrid', 2025, 9, 'Ayuda 9 (descripción pendiente: Anexo I)', 'variable', null, 'Sin importe en el modelo')
on conflict (programa, campana, codigo) do nothing;

-- Comprobación (esperado: 9 tablas con RLS, bucket privado, 9 ayudas) -----------
select
  (select count(*) from pg_tables
    where schemaname = 'public' and tablename like '%\_grefa' and rowsecurity
      and tablename in ('propietarios_grefa', 'parcelas_grefa', 'parcela_propietarios_grefa', 'nido_parcela_grefa',
                        'ayudas_grefa', 'contratos_grefa', 'contrato_parcelas_grefa', 'contrato_pagos_grefa',
                        'contrato_documentos_grefa')) as tablas_con_rls,
  (select count(*) from storage.buckets where id = 'contratos' and not public) as bucket_privado,
  (select count(*) from public.ayudas_grefa) as ayudas;
