const enc=new TextEncoder();
export function generateLicenseKey(){
 const alphabet='23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
 const chars=[...crypto.getRandomValues(new Uint8Array(12))].map(x=>alphabet[x&31]).join('');
 return 'az-'+chars.match(/.{4}/g).join('-');
}
export const validLicenseKey=key=>typeof key==='string'&&/^(?:AZP-[0-9A-F]{48}|az-(?:[2-9A-HJ-NP-Z]{4}-){2}[2-9A-HJ-NP-Z]{4})$/i.test(key.trim());
export const b64=b=>btoa(String.fromCharCode(...new Uint8Array(b)));
export const unb64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const uuid=s=>typeof s==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export function derToRaw(bytes){
 const b=new Uint8Array(bytes);let i=0;
 const len=()=>{let n=b[i++];if(n&128){let count=n&127;n=0;while(count--)n=(n<<8)|b[i++];}return n;};
 if(b[i++]!==48)throw Error('DER sequence');const size=len();if(i+size!==b.length)throw Error('DER length');const out=new Uint8Array(64);
 for(let k=0;k<2;k++){if(b[i++]!==2)throw Error('DER integer');const n=len();let x=b.slice(i,i+n);i+=n;while(x.length>32&&x[0]===0)x=x.slice(1);if(x.length>32)throw Error('DER size');out.set(x,k*32+32-x.length);}
 if(i!==b.length)throw Error('DER trailing');return out;
}
export async function verifyInstallation(publicKey,signature,message){
 try {const raw=unb64(publicKey);if(raw.length!==65||raw[0]!==4)return false;
 const key=await crypto.subtle.importKey('raw',raw,{name:'ECDSA',namedCurve:'P-256'},false,['verify']);
 return await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},key,derToRaw(unb64(signature)),enc.encode(message));}catch{return false;}
}
export async function hashLicense(key,pepper){
 const k=await crypto.subtle.importKey('raw',enc.encode(pepper),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',k,enc.encode(key.trim().toUpperCase())))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
export async function signLease(data,env){
 const ttl=Math.max(30,Math.min(300,Number(env.LEASE_SECONDS)||120));
 const payload=b64(enc.encode(JSON.stringify({...data,lease_expires_at:Math.min(data.expires_at,data.server_time+ttl)})));
 const key=await crypto.subtle.importKey('pkcs8',unb64(env.LEASE_PRIVATE_KEY_PKCS8_B64),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 return {payload,signature:b64(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,unb64(payload))),algorithm:'RS256'};
}
async function rpc(env,name,args){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),8000);
 try {const res=await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,'Content-Type':'application/json'},body:JSON.stringify(args),signal:controller.signal});if(!res.ok)throw Error('Database unavailable');return await res.json();}finally{clearTimeout(timer);}
}
async function adminAuthorized(request,env){
 const supplied=request.headers.get('Authorization')||'';if(!env.ADMIN_TOKEN||env.ADMIN_TOKEN.length<32)return false;
 const a=new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(supplied))),b=new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(`Bearer ${env.ADMIN_TOKEN}`)));let diff=0;for(let i=0;i<a.length;i++)diff|=a[i]^b[i];return diff===0;
}
export async function handle(request,env){
 const url=new URL(request.url),path=url.pathname;
 if(!path.startsWith('/license/')&&!path.startsWith('/admin/licenses'))return env.ASSETS?env.ASSETS.fetch(request):new Response('Not found',{status:404});
 if(url.protocol!=='https:'&&url.hostname!=='localhost'&&url.hostname!=='127.0.0.1')return json({error:'https_required'},400);
 if(!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||!env.LICENSE_KEY_PEPPER||!env.LEASE_PRIVATE_KEY_PKCS8_B64)return json({error:'server_not_configured'},503);
 const admin=path.startsWith('/admin/');if(admin&&!await adminAuthorized(request,env))return json({error:'unauthorized'},401);
 if(!['GET','POST'].includes(request.method))return json({error:'method_not_allowed'},405);
 let data={};if(request.method==='POST'){
  if(Number(request.headers.get('Content-Length'))>16384)return json({error:'request_too_large'},413);
  const text=await request.text();if(text.length>16384)return json({error:'request_too_large'},413);
  try{data=JSON.parse(text);}catch{return json({error:'invalid_json'},400);}
  if(!data||typeof data!=='object'||Array.isArray(data))return json({error:'invalid_json'},400);
 }
 if(admin){
  if(path==='/admin/licenses'){
   if(request.method==='GET')return json(await rpc(env,'az_admin',{p_action:'list',p_data:{search:(url.searchParams.get('search')||'').slice(0,80)||null}}));
   const duration=Number(data.duration_days),limit=Number(data.transfer_limit??2);if(!Number.isInteger(duration)||duration<1||duration>36500||!Number.isInteger(limit)||limit<0||limit>100)return json({error:'invalid_input'},400);
   const key=generateLicenseKey();
   const result=await rpc(env,'az_admin',{p_action:'create',p_data:{key_hash:await hashLicense(key,env.LICENSE_KEY_PEPPER),masked_key:`az-…${key.slice(-4)}`,duration_days:duration,transfer_limit:limit}});
   return json({...result,key},201);
  }
  const m=path.match(/^\/admin\/licenses\/([^/]+)(?:\/([^/]+))?$/);if(!m||!uuid(m[1]))return json({error:'not_found'},404);
  const action=m[2]||'detail';if((action==='detail')!==(request.method==='GET'))return json({error:'method_not_allowed'},405);
  if(!['detail','extend','suspend','reactivate','revoke','reset-device'].includes(action))return json({error:'not_found'},404);
  if(action==='extend'&&(!Number.isInteger(data.days)||data.days<1||data.days>36500))return json({error:'invalid_days'},400);
  const result=await rpc(env,'az_admin',{p_action:action,p_id:m[1],p_data:action==='extend'?{days:data.days}:{}});return json(result,result?.error?409:200);
 }
 if(request.method!=='POST')return json({error:'method_not_allowed'},405);
 if(['/license/activate','/license/challenge','/license/transfer/challenge'].includes(path)){
  if(!validLicenseKey(data.key)||!uuid(data.installation_id)||typeof data.bundle_id!=='string'||!/^[-a-zA-Z0-9._]{1,200}$/.test(data.bundle_id)||typeof data.public_key!=='string')return json({error:'invalid_input'},400);
  try{const key=unb64(data.public_key);if(key.length!==65||key[0]!==4)throw Error();await crypto.subtle.importKey('raw',key,{name:'ECDSA',namedCurve:'P-256'},false,['verify']);}catch{return json({error:'invalid_public_key'},400);}
  let target=null;const transfer=path.includes('/transfer/');if(transfer){target=data.target;if(!target||!uuid(target.installation_id)||typeof target.public_key!=='string')return json({error:'invalid_target'},400);try{await crypto.subtle.importKey('raw',unb64(target.public_key),{name:'ECDSA',namedCurve:'P-256'},false,['verify']);}catch{return json({error:'invalid_target'},400);}}
  const result=await rpc(env,'az_issue',{p_hash:await hashLicense(data.key,env.LICENSE_KEY_PEPPER),p_installation:data.installation_id,p_bundle:data.bundle_id,p_public:data.public_key,p_purpose:transfer?'transfer':'verify',p_target:target});return json(result,result?.error?403:200);
 }
 if(['/license/verify','/license/refresh','/license/transfer/complete','/license/status'].includes(path)){
  if(!uuid(data.challenge_id)||typeof data.signature!=='string'||data.signature.length>200)return json({error:'invalid_input'},400);
  const c=await rpc(env,'az_challenge',{p_id:data.challenge_id});if(!c)return json({error:'invalid_challenge'},403);
  if((c.purpose==='transfer')!==path.includes('/transfer/'))return json({error:'wrong_purpose'},403);
  const ok=await verifyInstallation(c.public_key,data.signature,c.message);
  const result=await rpc(env,'az_complete',{p_id:data.challenge_id,p_signature_ok:ok});
  if(result?.error)return json(result,403);
  if(c.purpose==='transfer')return json(result);
  const details=await rpc(env,'az_admin',{p_action:'detail',p_id:result.license_id,p_data:{}});
  const activated=Date.parse(details?.activated_at)/1000;
  if(!Number.isFinite(activated))throw Error('Missing subscription activation date');
  return json(await signLease({...result,activated_at:activated},env));
 }
 return json({error:'not_found'},404);
}
export default {async fetch(request,env){try{return await handle(request,env);}catch{return json({error:'verification_unavailable'},503);}}};
