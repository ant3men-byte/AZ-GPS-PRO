import fs from 'node:fs/promises';
const url=process.env.AZ_LICENSE_API_URL||'',key=process.env.AZ_LICENSE_PUBLIC_KEY_B64||'';
if(url&&(!url.startsWith('https://')||new URL(url).pathname!=='/'))throw Error('API URL must be an HTTPS origin, ending /');
if(key&&!/^[A-Za-z0-9+/]+={0,2}$/.test(key))throw Error('Invalid public key base64');
await fs.mkdir('build',{recursive:true});
await fs.writeFile('build/LicenseBuildConfig.h',`#define AZ_LICENSE_API_URL ${JSON.stringify(url)}\n#define AZ_LICENSE_PUBLIC_KEY_B64 ${JSON.stringify(key)}\n`);
console.log(url&&key?'Licensing public configuration applied':'UNCONFIGURED BUILD: licensing fails closed; set public configuration before distribution.');
