import fs from 'node:fs/promises';import {build} from 'esbuild';
const url=process.env.SUPABASE_URL||'',key=process.env.SUPABASE_PUBLISHABLE_KEY||'';
if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)||!key.startsWith('sb_publishable_'))throw Error('Missing public Supabase Auth configuration');
await fs.mkdir('public',{recursive:true});
await fs.copyFile('admin/index.html','public/index.html');await fs.copyFile('admin/style.css','public/style.css');
await fs.writeFile('public/public-config.mjs',`export const SUPABASE_URL=${JSON.stringify(url)};export const SUPABASE_PUBLISHABLE_KEY=${JSON.stringify(key)};\n`);
await build({entryPoints:['admin/app.mjs'],bundle:true,format:'esm',minify:true,outfile:'public/app.mjs',platform:'browser',target:['es2020']});
console.log('Admin assets bundled with public Auth configuration; server secrets excluded.');
