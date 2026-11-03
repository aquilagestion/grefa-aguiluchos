-- =============================================================================
-- Acceso a Aguiluchos: SOLO usuarios @grefa.org, un único administrador y
-- tiempo real. UN SOLO PASO.
--
-- Ejecutar una vez en: Supabase Dashboard > SQL Editor (proyecto compartido con
-- grefa-proyectos). Es idempotente y solo toca public.nidos_grefa y el bucket
-- `nidos-fotos`: no afecta a las tablas ni a los usuarios de grefa-proyectos.
--
--   1) Retira el acceso con la clave anónima (fin del piloto sin login).
--   2) Solo pueden leer/escribir nidos los usuarios con sesión cuyo correo
--      sea @grefa.org. Quien se registre con otro dominio no ve nada.
--   3) Solo aquilagestion@grefa.org (administrador) puede eliminar nidos.
--   4) Activa Realtime: el panel web recibe los cambios de la app al instante.
-- =============================================================================

-- Funciones de identidad (leen el correo del token de sesión) -----------------
create or replace function public.es_usuario_grefa()
returns boolean
language sql stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) ~ '^[^@[:space:]]+@grefa\.org$'
$$;

create or replace function public.es_admin_aguiluchos()
returns boolean
language sql stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'aquilagestion@grefa.org'
$$;

-- 1) Fuera las políticas del piloto (rol anon) ---------------------------------
drop policy if exists "nidos_grefa_select_anon" on public.nidos_grefa;
drop policy if exists "nidos_grefa_insert_anon" on public.nidos_grefa;
drop policy if exists "nidos_grefa_update_anon" on public.nidos_grefa;
drop policy if exists "nidos_fotos_insert_anon" on storage.objects;
drop policy if exists "nidos_fotos_update_anon" on storage.objects;

-- 2) Políticas RLS: usuarios @grefa.org ----------------------------------------
alter table public.nidos_grefa enable row level security;

drop policy if exists "nidos_grefa_select_auth"  on public.nidos_grefa;
drop policy if exists "nidos_grefa_insert_auth"  on public.nidos_grefa;
drop policy if exists "nidos_grefa_update_auth"  on public.nidos_grefa;
drop policy if exists "nidos_grefa_select_grefa" on public.nidos_grefa;
drop policy if exists "nidos_grefa_insert_grefa" on public.nidos_grefa;
drop policy if exists "nidos_grefa_update_grefa" on public.nidos_grefa;

create policy "nidos_grefa_select_grefa" on public.nidos_grefa
  for select to authenticated using (public.es_usuario_grefa());
create policy "nidos_grefa_insert_grefa" on public.nidos_grefa
  for insert to authenticated with check (public.es_usuario_grefa());
create policy "nidos_grefa_update_grefa" on public.nidos_grefa
  for update to authenticated
  using (public.es_usuario_grefa()) with check (public.es_usuario_grefa());
-- No hay DELETE: los borrados son lógicos (is_deleted = true), ver el trigger.

-- Fotos (bucket nidos-fotos): la lectura sigue siendo pública por URL (nombres
-- con UUID no adivinables); subir/modificar exige @grefa.org; borrar, admin.
drop policy if exists "nidos_fotos_insert_auth"  on storage.objects;
drop policy if exists "nidos_fotos_update_auth"  on storage.objects;
drop policy if exists "nidos_fotos_delete_auth"  on storage.objects;
drop policy if exists "nidos_fotos_insert_grefa" on storage.objects;
drop policy if exists "nidos_fotos_update_grefa" on storage.objects;
drop policy if exists "nidos_fotos_delete_admin" on storage.objects;

create policy "nidos_fotos_insert_grefa" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'nidos-fotos' and public.es_usuario_grefa());
create policy "nidos_fotos_update_grefa" on storage.objects
  for update to authenticated
  using (bucket_id = 'nidos-fotos' and public.es_usuario_grefa())
  with check (bucket_id = 'nidos-fotos' and public.es_usuario_grefa());
create policy "nidos_fotos_delete_admin" on storage.objects
  for delete to authenticated
  using (bucket_id = 'nidos-fotos' and public.es_admin_aguiluchos());

-- 3) Trigger: Last-Write-Wins + solo el administrador elimina ------------------
-- (SQL Editor y service_role no llevan rol `authenticated`: no se restringen.)
create or replace function public.nidos_grefa_before_write()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_at < old.updated_at then
      return old;
    end if;
    if new.is_deleted and not old.is_deleted
       and coalesce(auth.jwt() ->> 'role', '') = 'authenticated'
       and not public.es_admin_aguiluchos() then
      raise exception 'Solo el administrador puede eliminar nidos'
        using errcode = '42501';
    end if;
  end if;
  new.server_updated_at := now();
  return new;
end;
$$;

drop trigger if exists nidos_grefa_before_write on public.nidos_grefa;
create trigger nidos_grefa_before_write
  before insert or update on public.nidos_grefa
  for each row execute function public.nidos_grefa_before_write();

-- 4) Realtime ------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'nidos_grefa'
  ) then
    alter publication supabase_realtime add table public.nidos_grefa;
  end if;
end
$$;

-- Comprobación (resultado esperado: 0, 1, 3) -----------------------------------
select
  (select count(*) from pg_policies
    where (schemaname = 'public' and tablename = 'nidos_grefa' and 'anon' = any(roles))
       or (schemaname = 'storage' and tablename = 'objects' and policyname like 'nidos_fotos%anon'))
    as politicas_anon_restantes,
  (select count(*) from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'nidos_grefa')
    as realtime_activo,
  (select count(*) from pg_policies
    where schemaname = 'public' and tablename = 'nidos_grefa' and policyname like '%_grefa')
    as politicas_grefa;
