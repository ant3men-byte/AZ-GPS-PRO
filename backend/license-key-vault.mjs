const enc=new TextEncoder(),dec=new TextDecoder();
const context=enc.encode('AZ-GPS-PRO/license-key-vault/v1');
async function vaultKey(pepper){
 if(typeof pepper!=='string'||!pepper)throw Error('Missing license pepper');
 const material=await crypto.subtle.importKey('raw',enc.encode(pepper),'HKDF',false,['deriveKey']);
 return crypto.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:context,info:enc.encode('AES-256-GCM')},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
const encode=bytes=>btoa(String.fromCharCode(...new Uint8Array(bytes)));
const decode=value=>Uint8Array.from(atob(value),c=>c.charCodeAt(0));
export async function encryptLicenseKey(key,keyHash,pepper){
 const iv=crypto.getRandomValues(new Uint8Array(12));
 const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:enc.encode(keyHash)},await vaultKey(pepper),enc.encode(key));
 return `v1.${encode(iv)}.${encode(ciphertext)}`;
}
export async function decryptLicenseKey(value,keyHash,pepper){
 const [version,iv,ciphertext,...extra]=value.split('.');
 if(version!=='v1'||!iv||!ciphertext||extra.length||decode(iv).length!==12)throw Error('Invalid encrypted license key');
 return dec.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:decode(iv),additionalData:enc.encode(keyHash)},await vaultKey(pepper),decode(ciphertext)));
}
