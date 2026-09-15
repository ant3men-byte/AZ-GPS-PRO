import {createClient} from '@supabase/supabase-js';
import {SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY} from '../public/public-config.mjs';
const supabase=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:true,detectSessionInUrl:false}});
let token='',selected='';const $=id=>document.getElementById(id);
const labels={unused:'غير مستخدم',active:'فعال',expired:'منتهي',suspended:'موقوف',revoked:'ملغى'};
const events={create:'إصدار كود',activation:'أول تفعيل',binding:'ربط تثبيت',verification:'تحقق',extend:'تمديد',suspend:'إيقاف مؤقت',reactivate:'إعادة تفعيل',revoke:'إلغاء نهائي','reset-device':'إعادة ربط',transfer:'نقل',invalid_signature:'توقيع غير صالح'};
const fmt=d=>d?new Date(d).toLocaleString('ar',{dateStyle:'short',timeStyle:'short'}):'—';
const text=(tag,value)=>{const e=document.createElement(tag);e.textContent=value;return e;};
async function api(path,body,extraHeaders={}){const res=await fetch(path,{method:body===undefined?'GET':'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',...extraHeaders},...(body===undefined?{}:{body:JSON.stringify(body)}),cache:'no-store'});const data=await res.json();if(!res.ok||data.error)throw Error(data.error||'تعذر إكمال الطلب');return data;}
async function run(fn){$('notice').textContent='';const buttons=[...document.querySelectorAll('button:not(#mfaSubmit)')];buttons.forEach(b=>b.disabled=true);try{await fn();}catch(e){$('notice').textContent=`تعذر إكمال العملية: ${e.message}`;}finally{buttons.forEach(b=>b.disabled=false);}}
async function load(){const items=await api('/admin/licenses?search='+encodeURIComponent($('search').value));$('licenses').replaceChildren();$('empty').hidden=items.length>0;for(const l of items){const tr=document.createElement('tr'),key=text('td',l.masked_key);key.append(text('small',l.bundle_id||'لم يرتبط بتطبيق'));tr.append(key);const status=text('span',labels[l.status]||l.status);status.className='status '+l.status;const cell=document.createElement('td');cell.append(status);tr.append(cell);for(const value of [fmt(l.activated_at),fmt(l.expires_at),l.expires_at?Math.max(0,Math.ceil((new Date(l.expires_at)-Date.now())/86400000))+' يوم':'لم تبدأ',l.device_count,fmt(l.last_seen),l.transfers_remaining])tr.append(text('td',value));const more=document.createElement('td'),button=text('button','التفاصيل');button.onclick=()=>run(()=>detail(l.id));more.append(button);tr.append(more);$('licenses').append(tr);}}
async function detail(id){selected=id;const l=await api('/admin/licenses/'+id);$('detailSummary').replaceChildren(text('div',`رقم الترخيص: ${l.id}`),text('div',`الحالة: ${labels[l.status]||l.status} | المراجعة: ${l.revision}`),text('div',`أول تفعيل: ${fmt(l.activated_at)} | الانتهاء: ${fmt(l.expires_at)}`),text('div',`التطبيق: ${l.bundle_id||'لم يُربط'} | مرات النقل المتبقية: ${l.transfers_remaining}`));$('installations').replaceChildren(...l.installations.map(i=>text('div',`${i.id} — ${i.bound?'مرتبط':'ارتباط سابق'} — آخر تحقق: ${fmt(i.last_seen)}`)));if(!l.installations.length)$('installations').append(text('div','لا يوجد تثبيت مرتبط.'));$('audit').replaceChildren(...l.audit.map(a=>{const tr=document.createElement('tr');[events[a.event]||a.event,a.actor,fmt(a.created_at)].forEach(v=>tr.append(text('td',v)));return tr;}));if(!$('detail').open)$('detail').showModal();}
async function requireMfa(session){
 const factors=await supabase.auth.mfa.listFactors();if(factors.error)throw factors.error;
 let factor=factors.data.totp.find(x=>x.status==='verified');
 if(!factor){
  for(const stale of factors.data.totp.filter(x=>x.status!=='verified')){const removed=await supabase.auth.mfa.unenroll({factorId:stale.id});if(removed.error)throw removed.error;}
  const enrolled=await supabase.auth.mfa.enroll({factorType:'totp',friendlyName:'AZ GPS PRO Admin'});if(enrolled.error)throw enrolled.error;
  factor=enrolled.data;$('mfaQr').src=enrolled.data.totp.qr_code;$('mfaSetup').hidden=false;
 }else{$('mfaQr').removeAttribute('src');$('mfaSetup').hidden=false;}
 const challenge=await supabase.auth.mfa.challenge({factorId:factor.id});if(challenge.error)throw challenge.error;
 const code=await new Promise(resolve=>{
  $('mfaCode').value='';$('mfaCode').focus();
  const submit=()=>{const value=$('mfaCode').value.trim();if(!/^\\d{6}$/.test(value)){$('notice').textContent='أدخل رمزًا مكونًا من 6 أرقام.';return;}$('mfaSubmit').onclick=null;resolve(value);};
  $('mfaSubmit').onclick=submit;$('mfaCode').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();submit();}};
 });
 const verified=await supabase.auth.mfa.verify({factorId:factor.id,challengeId:challenge.data.id,code});if(verified.error)throw verified.error;
 $('mfaSetup').hidden=true;return verified.data.session?.access_token||verified.data.access_token;
}
$('loginForm').onsubmit=e=>{e.preventDefault();run(async()=>{
 const email=$('email').value.trim(),password=$('password').value,legacy=$('migrationToken').value.trim();
 const signed=await supabase.auth.signInWithPassword({email,password});if(signed.error)throw signed.error;
 token=await requireMfa(signed.data.session);
 if(legacy)await api('/admin/auth/bootstrap',{}, {'X-Admin-Migration':legacy});
 await api('/admin/auth/session',{});await load();$('password').value='';$('migrationToken').value='';$('login').hidden=true;$('workspace').hidden=false;$('logout').hidden=false;
});};
$('logout').onclick=()=>run(async()=>{try{await api('/admin/auth/logout',{});}finally{await supabase.auth.signOut();}token='';selected='';$('workspace').hidden=true;$('login').hidden=false;$('logout').hidden=true;$('newKey').hidden=true;$('keyValue').value='';$('detail').close();$('licenses').replaceChildren();});
$('createForm').onsubmit=e=>{e.preventDefault();const form=new FormData(e.target);run(async()=>{const l=await api('/admin/licenses',{duration_days:Number(form.get('duration_days')),transfer_limit:Number(form.get('transfer_limit'))});$('keyValue').value=l.key;$('newKey').hidden=false;await load();});};
$('searchForm').onsubmit=e=>{e.preventDefault();run(load);};$('copyKey').onclick=()=>run(()=>navigator.clipboard.writeText($('keyValue').value));$('dismissKey').onclick=()=>{$('newKey').hidden=true;$('keyValue').value='';};$('closeDetail').onclick=()=>$('detail').close();
document.querySelectorAll('[data-action]').forEach(button=>button.onclick=()=>{const action=button.dataset.action;if(!selected)return;const warnings={revoke:'الإلغاء نهائي ولا يمكن التراجع عنه. هل تتابع؟','reset-device':'سيُلغى ارتباط التثبيت الحالي وتُستهلك مرة نقل. التثبيت الجديد يجب أن يكون لنفس التطبيق. هل تتابع؟',suspend:'هل توقف هذا الاشتراك مؤقتًا؟'};if(warnings[action]&&!confirm(warnings[action]))return;run(async()=>{await api(`/admin/licenses/${selected}/${action}`,action==='extend'?{days:Number($('extendDays').value)}:{});await detail(selected);await load();});});
