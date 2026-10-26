-- Run after schema.sql and 002_security_hardening.sql, before deploying the new server.
-- Existing licenses remain valid; their plaintext keys cannot be recovered.
begin;
create table if not exists public.license_key_vault (
 license_id uuid primary key references public.licenses(id) on delete cascade,
 encrypted_key text not null check (encrypted_key like 'v1.%'),
 created_at timestamptz not null default now()
);
alter table public.license_key_vault enable row level security;
revoke all on public.license_key_vault from public,anon,authenticated;

-- License issuance and encrypted storage commit together. Never pass ciphertext to audit logs.
create or replace function public.az_create_license(p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if coalesce(p_data->>'encrypted_key','') not like 'v1.%' then
  raise exception 'encrypted license key required';
 end if;
 result=az_admin('create',null,p_data-'encrypted_key');
 if result ? 'error' then return result;end if;
 insert into license_key_vault(license_id,encrypted_key)
 values((result->>'id')::uuid,p_data->>'encrypted_key');
 return result;
end $$;

create or replace function public.az_read_license_key(p_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if not exists(select 1 from admin_accounts where user_id=p_actor and enabled) then
  raise exception 'unauthorized';
 end if;
 select jsonb_build_object('encrypted_key',v.encrypted_key,'key_hash',l.key_hash)
 into result from license_key_vault v join licenses l on l.id=v.license_id where v.license_id=p_id;
 if result is not null then
  insert into audit_logs(license_id,event,actor) values(p_id,'key_reveal',p_actor::text);
 end if;
 return result;
end $$;
revoke all on function public.az_create_license(jsonb),public.az_read_license_key(uuid,uuid) from public,anon,authenticated;
grant execute on function public.az_create_license(jsonb),public.az_read_license_key(uuid,uuid) to service_role;
notify pgrst, 'reload schema';
commit;
