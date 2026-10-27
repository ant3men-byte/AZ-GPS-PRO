import test from 'node:test';
import assert from 'node:assert/strict';
import {generateLicenseKey,validLicenseKey,hashLicense} from '../worker.mjs';
test('short az codes use twelve unambiguous random symbols',()=>{
 const keys=new Set();
 for(let i=0;i<1000;i++){const k=generateLicenseKey();assert.equal(k.length,17);assert.equal(validLicenseKey(k),true);keys.add(k);}
 assert.equal(keys.size,1000);
 assert.equal(validLicenseKey('az-OOOO-1111-0000'),false);
 assert.equal(validLicenseKey('az-2345-6789-ABCDx'),false);
 assert.equal(validLicenseKey('AZP-'+'A'.repeat(48)),true);
});
test('short codes accept case-insensitive entry',async()=>{
 const k=generateLicenseKey();assert.equal(validLicenseKey(k.toUpperCase()),true);
 assert.equal(await hashLicense(k,'test'),await hashLicense(k.toUpperCase(),'test'));
});
