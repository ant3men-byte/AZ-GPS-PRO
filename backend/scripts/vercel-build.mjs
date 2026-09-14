import fs from 'node:fs/promises';
await fs.mkdir('public',{recursive:true});for(const name of ['index.html','style.css','app.mjs'])await fs.copyFile(`admin/${name}`,`public/${name}`);
console.log('Admin static assets prepared. Backend secrets are excluded from public output.');
