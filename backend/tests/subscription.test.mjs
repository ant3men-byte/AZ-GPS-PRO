import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,verify} from 'node:crypto';
import {handle} from '../worker.mjs';
test('verified lease includes activation date without exposing admin details',async()=>{
 const rsa=generateKeyPairSync('rsa',{modulusLength:2048});
 const ec=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 const publicKey=ec.publicKey.export({type:'spki',format:'der'}).subarray(-65).toString('base64');
 const signature=sign('sha256',Buffer.from('proof'),ec.privateKey).toString('base64');
 const id='12345678-1234-1234-1234-123456789abc';
 const original=globalThis.fetch;
 globalThis.fetch=async(url,options)=>{
  const args=JSON.parse(options.body);
  if(url.endsWith('/az_rate_limit'))return Response.json(true);
  if(url.endsWith('/az_challenge'))return Response.json({purpose:'verify',public_key:publicKey,message:'proof'});
  if(url.endsWith('/az_complete')){assert.equal(args.p_signature_ok,true);return Response.json({challenge_id:id,license_id:id,installation_id:id,bundle_id:'com.test.app',status:'active',server_time:1000,expires_at:2000,revision:1});}
  if(url.endsWith('/az_admin')){assert.equal(args.p_action,'detail');assert.equal(args.p_id,id);return Response.json({activated_at:'1970-01-01T00:10:00Z',audit:[{secret:'hidden'}],key_hash:'hidden'});}
  throw Error('unexpected RPC');
 };
 try{
  const env={SUPABASE_URL:'https://database.test',SUPABASE_SERVICE_ROLE_KEY:'test',LICENSE_KEY_PEPPER:'test',LEASE_PRIVATE_KEY_PKCS8_B64:rsa.privateKey.export({type:'pkcs8',format:'der'}).toString('base64')};
  const response=await handle(new Request('https://api.test/license/verify',{method:'POST',body:JSON.stringify({challenge_id:id,signature})}),env);
  assert.equal(response.status,200);const envelope=await response.json();
  const bytes=Buffer.from(envelope.payload,'base64');const lease=JSON.parse(bytes);
  assert.equal(lease.activated_at,600);assert.equal(lease.expires_at,2000);
  assert.equal(lease.audit,undefined);assert.equal(lease.key_hash,undefined);
  assert.equal(verify('sha256',bytes,rsa.publicKey,Buffer.from(envelope.signature,'base64')),true);
 }finally{globalThis.fetch=original;}
});
