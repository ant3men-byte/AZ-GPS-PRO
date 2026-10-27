import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,verify} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import worker from '../worker.mjs';

const id='12345678-1234-1234-1234-123456789abc';
const rsa=generateKeyPairSync('rsa',{modulusLength:2048});
const ec=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const publicKey=ec.publicKey.export({type:'spki',format:'der'}).subarray(-65).toString('base64');
const signature=sign('sha256',Buffer.from('proof'),ec.privateKey).toString('base64');
const env={SUPABASE_URL:'https://database.test',SUPABASE_SERVICE_ROLE_KEY:'test',LICENSE_KEY_PEPPER:'test',LEASE_PRIVATE_KEY_PKCS8_B64:rsa.privateKey.export({type:'pkcs8',format:'der'}).toString('base64')};
const verified={challenge_id:id,license_id:id,installation_id:id,bundle_id:'com.test.app',status:'active',server_time:1000,expires_at:2000,revision:1};

async function requestLease(result,route='/license/verify'){
 const original=globalThis.fetch,calls=[];
 globalThis.fetch=async(url,options)=>{
  const name=url.split('/').pop();calls.push(name);const args=JSON.parse(options.body);
  if(name==='az_rate_limit')return Response.json(true);
  if(name==='az_challenge')return Response.json({purpose:'verify',public_key:publicKey,message:'proof'});
  if(name==='az_complete'){assert.equal(args.p_signature_ok,true);return Response.json(result);}
  if(name==='az_admin'){
   assert.equal(args.p_action,'detail');assert.equal(args.p_id,id);
   return Response.json({activated_at:'1970-01-01T00:10:00Z',audit:[{secret:'hidden'}],key_hash:'hidden'});
  }
  throw Error('Unexpected RPC');
 };
 try{
  const response=await worker.fetch(new Request('https://api.test'+route,{method:'POST',body:JSON.stringify({challenge_id:id,signature})}),env);
  return {response,body:await response.json(),calls};
 }finally{globalThis.fetch=original;}
}

for(const route of ['/license/verify','/license/refresh','/license/status'])test(route+' signs the unchanged lease with three database requests and no admin lookup',async()=>{
 const {response,body,calls}=await requestLease({...verified,activated_at:600},route);
 assert.equal(response.status,200);
 assert.deepEqual(calls,['az_rate_limit','az_challenge','az_complete']);
 const bytes=Buffer.from(body.payload,'base64');const lease=JSON.parse(bytes);
 assert.equal(lease.activated_at,600);assert.equal(lease.expires_at,2000);assert.equal(lease.lease_expires_at,1120);
 assert.equal(lease.revision,1);assert.equal(lease.audit,undefined);assert.equal(lease.key_hash,undefined);
 assert.equal(verify('sha256',bytes,rsa.publicKey,Buffer.from(body.signature,'base64')),true);
});

test('older databases remain compatible during rollout or rollback',async()=>{
 const {response,body,calls}=await requestLease(verified);
 assert.equal(response.status,200);
 assert.deepEqual(calls,['az_rate_limit','az_challenge','az_complete','az_admin']);
 const lease=JSON.parse(Buffer.from(body.payload,'base64'));
 assert.equal(lease.activated_at,600);assert.equal(lease.audit,undefined);assert.equal(lease.key_hash,undefined);
});

test('a rejected verification does not fetch admin data or sign a lease',async()=>{
 const {response,body,calls}=await requestLease({error:'suspended'});
 assert.equal(response.status,403);assert.deepEqual(body,{error:'suspended'});
 assert.deepEqual(calls,['az_rate_limit','az_challenge','az_complete']);
});

for(const activated_at of [null,'600'])test('invalid activation timestamp fails closed: '+JSON.stringify(activated_at),async()=>{
 const {response,body,calls}=await requestLease({...verified,activated_at});
 assert.equal(response.status,503);assert.equal(body.payload,undefined);
 assert.deepEqual(calls,['az_rate_limit','az_challenge','az_complete']);
});

test('fresh installs and existing-database migration use the same verifier',async()=>{
 const migration=await readFile(new URL('../migrations/004_verification_activation_time.sql',import.meta.url),'utf8');
 const schema=await readFile(new URL('../schema.sql',import.meta.url),'utf8');
 const extract=s=>s.replace(/\r/g,'').match(/create (?:or replace )?function public\.az_complete\([\s\S]*?end \$\$;/)[0].replace('create or replace function','create function');
 assert.equal(extract(migration),extract(schema));
});
