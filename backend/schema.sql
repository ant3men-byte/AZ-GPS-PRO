create extension if not exists pgcrypto;
create table public.licenses (
 id uuid primary key default gen_random_uuid(), key_hash text not null unique,
 masked_key text not null, duration_days integer not null check(duration_days between 1 and 36500),
 status text not null default 'unused' check(status in ('unused','active','expired','suspended','revoked')),
 activated_at timestamptz, expires_at timestamptz, bundle_id text,
 allowed_installations integer not null default 1 check(allowed_installations between 1 and 10),
 transfer_limit integer not null default 2 check(transfer_limit between 0 and 100),
 transfer_count integer not null default 0 check(transfer_count>=0), revision integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((activated_at is null and expires_at is null) or (activated_at is not null and expires_at is not null))
);
create table public.installations (
 id uuid primary key, license_id uuid not null references public.licenses(id), bundle_id text not null,
 public_key text not null, bound boolean not null default true,
 created_at timestamptz not null default now(), last_seen timestamptz not null default now()
);
create index installations_license_idx on public.installations(license_id,bound);
create table public.license_challenges (
 id uuid primary key default gen_random_uuid(), license_id uuid not null references public.licenses(id),
 installation_id uuid not null, bundle_id text not null, public_key text not null,
 nonce text not null default encode(gen_random_bytes(32),'hex'),
 purpose text not null default 'verify' check(purpose in ('verify','transfer')),
 target jsonb, created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '60 seconds'), consumed_at timestamptz
);
create index challenges_expiry_idx on public.license_challenges(expires_at);
create table public.license_transfers (
 id uuid primary key default gen_random_uuid(), license_id uuid not null references public.licenses(id),
 old_installation_id uuid references public.installations(id), new_installation_id uuid references public.installations(id),
 actor text not null, created_at timestamptz not null default now()
);
create table public.audit_logs (
 id bigint generated always as identity primary key, license_id uuid references public.licenses(id),
 event text not null, actor text not null, detail jsonb not null default '{}', created_at timestamptz not null default now()
);
create index audit_license_time_idx on public.audit_logs(license_id,created_at desc);
alter table public.licenses enable row level security;
alter table public.installations enable row level security;
alter table public.license_challenges enable row level security;
alter table public.license_transfers enable row level security;
alter table public.audit_logs enable row level security;
revoke all on public.licenses,public.installations,public.license_challenges,public.license_transfers,public.audit_logs from anon,authenticated;

create function public.az_failure(p_license uuid,p_code text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into audit_logs(license_id,event,actor,detail) values(p_license,'verification_rejected','client',jsonb_build_object('reason',p_code));
 return jsonb_build_object('error',p_code);
end $$;
revoke all on function public.az_failure(uuid,text) from public,anon,authenticated;

create function public.az_issue(p_hash text,p_installation uuid,p_bundle text,p_public text,p_purpose text default 'verify',p_target jsonb default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare l licenses; c license_challenges; msg text;
begin
 select * into l from licenses where key_hash=p_hash for update;
 if not found then
  insert into audit_logs(event,actor) values('invalid_key','client');
  return az_failure(l.id,'invalid');
 end if;
 if l.status in ('revoked','suspended') then return az_failure(l.id,l.status); end if;
 if l.expires_at is not null and l.expires_at<=now() then
  update licenses set status='expired',updated_at=now() where id=l.id;
  return az_failure(l.id,'expired');
 end if;
 if l.bundle_id is not null and l.bundle_id<>p_bundle then return az_failure(l.id,'wrong_app'); end if;
 if (select count(*) from license_challenges where license_id=l.id and created_at>now()-interval '1 minute')>=20 then
  return az_failure(l.id,'rate_limited');
 end if;
 if p_purpose='transfer' and not exists(select 1 from installations where id=p_installation and license_id=l.id and bound and public_key=p_public and bundle_id=p_bundle) then
  return az_failure(l.id,'device_limit');
 end if;
 insert into license_challenges(license_id,installation_id,bundle_id,public_key,purpose,target)
 values(l.id,p_installation,p_bundle,p_public,p_purpose,p_target) returning * into c;
 msg='AZGPS-LICENSE-1'||chr(10)||c.id||chr(10)||c.nonce||chr(10)||c.installation_id||chr(10)||c.bundle_id||chr(10)||c.purpose||chr(10)||coalesce(c.target::text,'');
 return jsonb_build_object('challenge_id',c.id,'nonce',c.nonce,'timestamp',extract(epoch from now()),'expiration',extract(epoch from c.expires_at),'message',msg);
end $$;

create function public.az_challenge(p_id uuid) returns jsonb language sql security definer set search_path=public,pg_temp as $$
 select to_jsonb(c)||jsonb_build_object('message','AZGPS-LICENSE-1'||chr(10)||c.id||chr(10)||c.nonce||chr(10)||c.installation_id||chr(10)||c.bundle_id||chr(10)||c.purpose||chr(10)||coalesce(c.target::text,'')) from license_challenges c where id=p_id;
$$;
create function public.az_complete(p_id uuid,p_signature_ok boolean)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c license_challenges; l licenses; inst installations; dest uuid; dest_public text;
begin
 -- Challenge and license row locks serialize nonce consumption and device limits.
 select * into c from license_challenges where id=p_id for update;
 if not found then return az_failure(c.license_id,'invalid_challenge'); end if;
 if c.consumed_at is not null or c.expires_at<=now() then return az_failure(c.license_id,'replayed_or_expired_challenge'); end if;
 update license_challenges set consumed_at=now() where id=c.id;
 if not p_signature_ok then
  insert into audit_logs(license_id,event,actor) values(c.license_id,'invalid_signature','client');
  return az_failure(c.license_id,'invalid_signature');
 end if;
 select * into l from licenses where id=c.license_id for update;
 if l.status in ('revoked','suspended') then return az_failure(c.license_id,l.status); end if;
 if l.expires_at is not null and l.expires_at<=now() then
  update licenses set status='expired',updated_at=now() where id=l.id;
  return az_failure(c.license_id,'expired');
 end if;
 if l.bundle_id is not null and l.bundle_id<>c.bundle_id then return az_failure(c.license_id,'wrong_app'); end if;
 select * into inst from installations where id=c.installation_id;
 if c.purpose='transfer' then
  if inst.id is null or not inst.bound or inst.license_id<>l.id or inst.public_key<>c.public_key then return az_failure(c.license_id,'device_limit'); end if;
  if l.transfer_count>=l.transfer_limit then return az_failure(c.license_id,'transfer_limit'); end if;
  dest=(c.target->>'installation_id')::uuid;dest_public=c.target->>'public_key';
  if dest=inst.id or exists(select 1 from installations where id=dest) then return az_failure(c.license_id,'invalid_target'); end if;
  insert into installations(id,license_id,bundle_id,public_key) values(dest,l.id,c.bundle_id,dest_public);
  update installations set bound=false where id=inst.id;
  update licenses set transfer_count=transfer_count+1,revision=revision+1,updated_at=now() where id=l.id returning * into l;
  insert into license_transfers(license_id,old_installation_id,new_installation_id,actor) values(l.id,inst.id,dest,'client');
  insert into audit_logs(license_id,event,actor) values(l.id,'transfer','client');
  return jsonb_build_object('transferred',true,'revision',l.revision);
 end if;
 if inst.id is not null then
  if inst.license_id<>l.id or inst.bundle_id<>c.bundle_id or inst.public_key<>c.public_key or not inst.bound then return az_failure(c.license_id,'device_limit'); end if;
 else
  if (select count(*) from installations where license_id=l.id and bound)>=l.allowed_installations then return az_failure(c.license_id,'device_limit'); end if;
  insert into installations(id,license_id,bundle_id,public_key) values(c.installation_id,l.id,c.bundle_id,c.public_key);
  insert into audit_logs(license_id,event,actor) values(l.id,'binding','client');
 end if;
 if l.activated_at is null then
  update licenses set activated_at=now(),expires_at=now()+make_interval(days=>duration_days),bundle_id=c.bundle_id,status='active',updated_at=now() where id=l.id returning * into l;
  insert into audit_logs(license_id,event,actor) values(l.id,'activation','client');
 end if;
 update installations set last_seen=now() where id=c.installation_id;
 insert into audit_logs(license_id,event,actor) values(l.id,'verification','client');
 return jsonb_build_object('challenge_id',c.id,'license_id',l.id,'installation_id',c.installation_id,'bundle_id',c.bundle_id,'status','active','expires_at',extract(epoch from l.expires_at),'server_time',extract(epoch from now()),'revision',l.revision);
end $$;

create function public.az_admin(p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare l licenses; days integer; old_id uuid; result jsonb;
begin
 if p_action='create' then
  insert into licenses(key_hash,masked_key,duration_days,transfer_limit)
  values(p_data->>'key_hash',p_data->>'masked_key',(p_data->>'duration_days')::integer,(p_data->>'transfer_limit')::integer) returning * into l;
 elsif p_action='list' then
  select coalesce(jsonb_agg(x),'[]') into result from (
   select id,masked_key,duration_days,case when status='active' and expires_at<=now() then 'expired' else status end status,
    activated_at,expires_at,bundle_id,created_at,revision,transfer_limit,transfer_count,
    transfer_limit-transfer_count transfers_remaining,
    (select count(*) from installations i where i.license_id=a.id and bound) device_count,
    (select max(last_seen) from installations i where i.license_id=a.id) last_seen
   from licenses a where p_data->>'search' is null or id::text ilike '%'||(p_data->>'search')||'%' or masked_key ilike '%'||(p_data->>'search')||'%'
   order by created_at desc limit 200
  ) x;return result;
 else
  select * into l from licenses where id=p_id for update;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if p_action='detail' then
   if l.status='active' and l.expires_at<=now() then update licenses set status='expired',updated_at=now() where id=l.id returning * into l;end if;
   return (to_jsonb(l)-'key_hash')||jsonb_build_object('transfers_remaining',l.transfer_limit-l.transfer_count,'installations',(select coalesce(jsonb_agg(to_jsonb(i)-'public_key'),'[]') from installations i where license_id=l.id),'audit',(select coalesce(jsonb_agg(x),'[]') from (select event,actor,detail,created_at from audit_logs where license_id=l.id order by created_at desc limit 100) x));
  end if;
  if l.status='revoked' then return jsonb_build_object('error','revoked'); end if;
  if p_action='extend' then
   days=(p_data->>'days')::integer;
   if days not between 1 and 36500 then return jsonb_build_object('error','invalid_days'); end if;
   if l.activated_at is null then update licenses set duration_days=duration_days+days where id=l.id;
   else update licenses set expires_at=greatest(expires_at,now())+make_interval(days=>days),status=case when status='expired' then 'active' else status end where id=l.id;end if;
  elsif p_action='suspend' then update licenses set status='suspended' where id=l.id;
  elsif p_action='reactivate' then
   if l.status<>'suspended' then return jsonb_build_object('error','not_suspended'); end if;
   update licenses set status=case when activated_at is null then 'unused' when expires_at<=now() then 'expired' else 'active' end where id=l.id;
  elsif p_action='revoke' then update licenses set status='revoked' where id=l.id;
  elsif p_action='reset-device' then
   if l.transfer_count>=l.transfer_limit then return jsonb_build_object('error','transfer_limit');end if;
   for old_id in select id from installations where license_id=l.id and bound loop
    insert into license_transfers(license_id,old_installation_id,actor) values(l.id,old_id,'admin');
   end loop;
   update installations set bound=false where license_id=l.id;
   update licenses set transfer_count=transfer_count+1 where id=l.id;
   -- Old installation cannot rebind; new installation may activate, same app only.
  else return jsonb_build_object('error','invalid_action');end if;
  update licenses set revision=revision+1,updated_at=now() where id=l.id returning * into l;
 end if;
 insert into audit_logs(license_id,event,actor,detail) values(l.id,p_action,'admin',p_data-'key_hash');
 return to_jsonb(l)-'key_hash';
end $$;
revoke all on function public.az_issue(text,uuid,text,text,text,jsonb),public.az_challenge(uuid),public.az_complete(uuid,boolean),public.az_admin(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.az_issue(text,uuid,text,text,text,jsonb),public.az_challenge(uuid),public.az_complete(uuid,boolean),public.az_admin(text,uuid,jsonb) to service_role;
