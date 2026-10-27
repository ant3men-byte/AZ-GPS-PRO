-- Security hardening: run after schema.sql. Safe to re-run.
create table if not exists public.admin_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 last_login_at timestamptz
);
create table if not exists public.api_rate_limits (
 bucket text primary key, window_started_at timestamptz not null, hits integer not null
);
alter table public.admin_accounts enable row level security;
alter table public.api_rate_limits enable row level security;
revoke all on public.admin_accounts,public.api_rate_limits from public,anon,authenticated;

create or replace function public.az_rate_limit(p_bucket text,p_limit integer,p_window_seconds integer)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare r api_rate_limits;
begin
 if length(p_bucket)>160 or p_limit not between 1 and 10000 or p_window_seconds not between 1 and 86400 then return false;end if;
 insert into api_rate_limits(bucket,window_started_at,hits) values(p_bucket,now(),1)
 on conflict(bucket) do update set
  window_started_at=case when api_rate_limits.window_started_at<=now()-make_interval(secs=>p_window_seconds) then now() else api_rate_limits.window_started_at end,
  hits=case when api_rate_limits.window_started_at<=now()-make_interval(secs=>p_window_seconds) then 1 else api_rate_limits.hits+1 end
 returning * into r;
 if r.hits=p_limit+1 then insert into audit_logs(event,actor,detail) values('rate_limit','server',jsonb_build_object('bucket',split_part(p_bucket,':',1)));end if;
 return r.hits<=p_limit;
end $$;

create or replace function public.az_admin_security(p_action text,p_user uuid,p_detail jsonb default '{}')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare allowed boolean;
begin
 if p_action='authorize' then
  select enabled into allowed from admin_accounts where user_id=p_user;
  return jsonb_build_object('admin',coalesce(allowed,false));
 elsif p_action='login' then
  select enabled into allowed from admin_accounts where user_id=p_user;
  if coalesce(allowed,false) then
   update admin_accounts set last_login_at=now() where user_id=p_user;
   insert into audit_logs(event,actor,detail) values('admin_login',p_user::text,p_detail);
  else insert into audit_logs(event,actor,detail) values('admin_login_rejected',p_user::text,p_detail);end if;
  return jsonb_build_object('admin',coalesce(allowed,false));
 elsif p_action='logout' then
  insert into audit_logs(event,actor,detail) values('admin_logout',p_user::text,p_detail);
  return jsonb_build_object('ok',true);
 end if;
 return jsonb_build_object('error','invalid_action');
end $$;
revoke all on function public.az_rate_limit(text,integer,integer),public.az_admin_security(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.az_rate_limit(text,integer,integer),public.az_admin_security(text,uuid,jsonb) to service_role;

create or replace function public.az_cleanup_licensing(p_audit_days integer default 365)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare challenges_deleted bigint;logs_deleted bigint;
begin
 if p_audit_days<30 then raise exception 'audit retention must be at least 30 days';end if;
 delete from license_challenges where expires_at<now()-interval '24 hours';get diagnostics challenges_deleted=row_count;
 delete from api_rate_limits where window_started_at<now()-interval '2 days';
 delete from audit_logs where created_at<now()-make_interval(days=>p_audit_days)
  and event not in ('create','activation','extend','suspend','reactivate','revoke','reset-device','transfer','admin_bootstrap');
 get diagnostics logs_deleted=row_count;
 return jsonb_build_object('challenges_deleted',challenges_deleted,'audit_deleted',logs_deleted);
end $$;
revoke all on function public.az_cleanup_licensing(integer) from public,anon,authenticated;
grant execute on function public.az_cleanup_licensing(integer) to service_role;

create or replace function public.az_health()
returns jsonb language sql security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('database','ok','checked_at',extract(epoch from now()));
$$;
revoke all on function public.az_health() from public,anon,authenticated;
grant execute on function public.az_health() to service_role;

create or replace function public.az_audit_expiration() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.status='expired' and old.status is distinct from 'expired' then
  insert into audit_logs(license_id,event,actor) values(new.id,'expiration','server');
 end if;return new;
end $$;
drop trigger if exists az_license_expiration_audit on public.licenses;
create trigger az_license_expiration_audit after update of status on public.licenses
for each row execute function public.az_audit_expiration();
