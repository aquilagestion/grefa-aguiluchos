-- =============================================================================
-- Tiempo real para el panel web (Supabase Realtime).
-- Ejecutar UNA vez en: Supabase Dashboard > SQL Editor. Es idempotente.
--
-- Añade public.nidos_grefa a la publicación `supabase_realtime`: así el panel
-- (https://grefa-aguiluchos.vercel.app) recibe al instante cada nido que la app
-- de campo sube al sincronizar, sin recargar. Realtime respeta las políticas
-- RLS: con login solo reciben cambios los usuarios `authenticated`.
-- =============================================================================

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

-- Comprobación: debe devolver una fila.
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime' and tablename = 'nidos_grefa';
