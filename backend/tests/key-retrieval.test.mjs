import test from 'node:test';
import assert from 'node:assert/strict';
import {encryptLicenseKey,decryptLicenseKey} from '../license-key-vault.mjs';
import worker,{hashLicense} from '../worker.mjs';

test('vault authenticates ciphertext, license hash and secret with a fresh nonce',async()=>{
 const key='az-2345-6789-ABCD',hash=await hashLicense(key,'secret');
 const encrypted=await encryptLicenseKey(key,hash,'secret');
 assert.equal(await decryptLicenseKey(encrypted,hash,'secret'),key);
 assert.notEqual(encrypted,await encryptLicenseKey(key,hash,'secret'));
 assert.ok(!encrypted.includes(key));
 await assert.rejects(decryptLicenseKey(encrypted,hash,'wrong-secret'));
 await assert.rejects(decryptLicenseKey(encrypted,'different-license','secret'));
 const parts=encrypted.split('.');const bytes=Buffer.from(parts[2],'base64');bytes[0]^=1;parts[2]=bytes.toString('base64');
 await assert.rejects(decryptLicenseKey(parts.join('.'),hash,'secret'));
});

test('only approved admins can retrieve new keys; lists stay masked and legacy licenses remain usable',async()=>{
 const id='12345678-1234-1234-1234-123456789abc';
 const token='test.'+Buffer.from(JSON.stringify({sub:id,aal:'aal1'})).toString('base64url')+'.test';
 const env={SUPABASE_URL:'https://database.test',SUPABASE_SERVICE_ROLE_KEY:'service-test',SUPABASE_PUBLISHABLE_KEY:'public-test',LICENSE_KEY_PEPPER:'test-secret',LEASE_PRIVATE_KEY_PKCS8_B64:'unused'};
 let approved=true,stored=null,details={id,installations:[],audit:[]},revealCalls=0;
 const original=globalThis.fetch;
 globalThis.fetch=async(url,options)=>{
  if(url.endsWith('/auth/v1/user'))return Response.json({id});
  const args=JSON.parse(options.body);
  if(url.endsWith('/az_rate_limit'))return Response.json(true);
  if(url.endsWith('/az_admin_security'))return Response.json({admin:approved});
  if(url.endsWith('/az_create_license')){
   assert.ok(!JSON.stringify(args).includes('"key":'));
   stored={encrypted_key:args.p_data.encrypted_key,key_hash:args.p_data.key_hash};
   details={...details,masked_key:args.p_data.masked_key};
   return Response.json(details);
  }
  if(url.endsWith('/az_read_license_key')){revealCalls++;assert.equal(args.p_actor,id);return Response.json(stored);}
  if(url.endsWith('/az_admin'))return Response.json(args.p_action==='list'?[details]:details);
  throw Error('Unexpected request');
 };
 const request=(path,body,authorized=true)=>new Request('https://api.test/admin/licenses'+path,{method:body?'POST':'GET',headers:authorized?{Authorization:'Bearer '+token}:{},...(body?{body:JSON.stringify(body)}:{})});
 try{
  let res=await worker.fetch(request('',{duration_days:30,transfer_limit:2}),env);
  assert.equal(res.status,201);const issued=await res.json();assert.ok(issued.key);
  assert.ok(!JSON.stringify(stored).includes(issued.key));
  res=await worker.fetch(request('/'+id),env);assert.equal(res.status,200);
  assert.equal((await res.json()).key,issued.key);
  res=await worker.fetch(request(''),env);const list=await res.json();
  assert.equal(list[0].key,undefined);assert.equal(list[0].encrypted_key,undefined);
  const before=revealCalls;
  res=await worker.fetch(request('/'+id,undefined,false),env);assert.equal(res.status,401);
  approved=false;res=await worker.fetch(request('/'+id),env);assert.equal(res.status,401);assert.equal(revealCalls,before);
  approved=true;stored=null;res=await worker.fetch(request('/'+id),env);
  assert.equal(res.status,200);assert.equal((await res.json()).key,null);
  stored={encrypted_key:'corrupt',key_hash:'test'};res=await worker.fetch(request('/'+id),env);
  assert.equal(res.status,503);assert.deepEqual(await res.json(),{error:'verification_unavailable'});
 }finally{globalThis.fetch=original;}
});
