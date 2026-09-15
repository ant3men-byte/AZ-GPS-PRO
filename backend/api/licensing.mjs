import worker from '../worker.mjs';
export default async function handler(req,res){
 const route=typeof req.query?.route==='string'?req.query.route:'';
 if(!/^(license|admin\/(?:licenses|auth))(\/[-a-zA-Z0-9]+)*$/.test(route)){res.statusCode=404;res.end('Not found');return;}
 const params=new URLSearchParams();if(typeof req.query?.search==='string')params.set('search',req.query.search.slice(0,80));
 const headers=new Headers();for(const name of ['authorization','content-type','content-length','x-admin-migration','x-forwarded-for','x-real-ip']){const value=req.headers[name];if(typeof value==='string')headers.set(name,value);}
 const body=['GET','HEAD'].includes(req.method)?undefined:typeof req.body==='string'?req.body:JSON.stringify(req.body??{});
 const request=new Request(`https://licensing.internal/${route}?${params}`,{method:req.method,headers,...(body===undefined?{}:{body})});
 const response=await worker.fetch(request,process.env);res.statusCode=response.status;response.headers.forEach((value,key)=>res.setHeader(key,value));res.end(Buffer.from(await response.arrayBuffer()));
}
