import {generateKeyPairSync,randomBytes} from 'node:crypto';
import fs from 'node:fs/promises';
const out=process.argv[2];if(!out)throw Error('Pass a PRIVATE output directory outside the repository.');
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:3072});
await fs.mkdir(out,{recursive:true});
await fs.writeFile(`${out}/lease-private-key.txt`,privateKey.export({type:'pkcs8',format:'der'}).toString('base64'),{mode:0o600,flag:'wx'});
await fs.writeFile(`${out}/lease-public-key.txt`,publicKey.export({type:'pkcs1',format:'der'}).toString('base64'),{flag:'wx'});
await fs.writeFile(`${out}/server-secrets.txt`,`LICENSE_KEY_PEPPER=${randomBytes(32).toString('hex')}\nADMIN_TOKEN=${randomBytes(32).toString('hex')}\n`,{mode:0o600,flag:'wx'});
console.log('Keys saved privately. Only lease-public-key.txt belongs in the dylib configuration.');
