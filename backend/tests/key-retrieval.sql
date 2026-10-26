-- Run in a test database after migrations 002 and 003. Rolls back all test data.
begin;
do $$
declare issued jsonb; stored jsonb; actor_id uuid; bad_actor uuid=gen_random_uuid();
begin
 select user_id into actor_id from public.admin_accounts where enabled limit 1;
 if actor_id is null then raise exception 'Test requires an approved admin account';end if;
 issued=public.az_create_license(jsonb_build_object('key_hash',gen_random_uuid()::text,'encrypted_key','v1.test.ciphertext','masked_key','az-…TEST','duration_days',30,'transfer_limit',2));
 stored=public.az_read_license_key((issued->>'id')::uuid,actor_id);
 if stored->>'encrypted_key'<>'v1.test.ciphertext' then raise exception 'Stored ciphertext missing';end if;
 if issued ? 'encrypted_key' or issued ? 'key_hash' then raise exception 'Issuance leaked storage fields';end if;
 if exists(select 1 from public.audit_logs where license_id=(issued->>'id')::uuid and (detail ? 'encrypted_key' or detail ? 'key_hash')) then raise exception 'Audit leaked secrets';end if;
 begin
  perform public.az_read_license_key((issued->>'id')::uuid,bad_actor);
  raise exception 'Unapproved admin was accepted';
 exception when raise_exception then
  if sqlerrm<>'unauthorized' then raise;end if;
 end;
 if has_table_privilege('anon','public.license_key_vault','SELECT') or has_table_privilege('authenticated','public.license_key_vault','SELECT') then raise exception 'Vault exposed to client roles';end if;
 if has_function_privilege('anon','public.az_read_license_key(uuid,uuid)','EXECUTE') or has_function_privilege('authenticated','public.az_read_license_key(uuid,uuid)','EXECUTE') then raise exception 'Retrieval exposed to client roles';end if;
end $$;
rollback;
