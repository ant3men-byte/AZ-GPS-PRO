-- Return activation time with verification; no client update required.
-- Safe to rerun. Existing rows, checks and response fields are preserved.
begin;
create or replace function public.az_complete(p_id uuid,p_signature_ok boolean)
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
 return jsonb_build_object('challenge_id',c.id,'license_id',l.id,'installation_id',c.installation_id,'bundle_id',c.bundle_id,'status','active','activated_at',extract(epoch from l.activated_at),'expires_at',extract(epoch from l.expires_at),'server_time',extract(epoch from now()),'revision',l.revision);
end $$;
revoke all on function public.az_complete(uuid,boolean) from public,anon,authenticated;
grant execute on function public.az_complete(uuid,boolean) to service_role;
notify pgrst, 'reload schema';
commit;
