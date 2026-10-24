import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import webpush from 'npm:web-push@3.6.7';

// No credentials in source. Supabase supplies the service key to this backend.
const url=Deno.env.get('SUPABASE_URL')!;
const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const origins=new Set(['https://penzidor.github.io','http://127.0.0.1:5175']);
const allowedEndpoint=(value:string)=>{
 try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&
 /^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)$/.test(u.hostname);}catch{return false;}
};
async function server(action:string,payload:object={}){
 const {data,error}=await service.rpc('cv_push_server',{action,payload});if(error)throw new Error('Push backend unavailable');return data;
}
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Cache-Control':'no-store',...(origins.has(origin)?{'Access-Control-Allow-Origin':origin,'Vary':'Origin'}:{}),
 'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
 const reply=(body:object,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 try{
  let config=await server('config');
  const dispatch=req.headers.get('x-cadrivolt-dispatch');
  if(dispatch){
   if(dispatch!==config.dispatch_secret)return reply({error:'Unauthorized'},401);
   if(!config.public_key)return reply({sent:0,pendingSetup:true});
   const jobs=await server('claim');let sent=0;
   // Bound both parallelism and batch size. Leases prevent concurrent workers claiming the same jobs.
   for(let offset=0;offset<jobs.length;offset+=5)await Promise.all(jobs.slice(offset,offset+5).map(async(job:any)=>{
    let status=400;
    try{
     if(!allowedEndpoint(job.endpoint))status=410;
     else{
      const target=new URL(config.site_url);if(job.applicationId)target.searchParams.set('conversation',job.applicationId);
      const titles:Record<string,string>={application:'Nouvelle demande',accepted:'Participation confirmée',declined:'Une réponse à ta demande',message:'Nouveau message',session:'Session mise à jour',test:'Les notifications sont activées'};
      const payload=JSON.stringify({title:titles[job.kind]||'Du nouveau sur Cadrivolt',body:job.kind==='test'?'Cet appareil peut recevoir les alertes Cadrivolt.':'Ouvre Cadrivolt pour consulter les détails.',url:target.href,tag:'cadrivolt-'+job.id});
      const request=webpush.generateRequestDetails({endpoint:job.endpoint,keys:job.keys},payload,{TTL:3600,urgency:'normal',vapidDetails:{subject:config.site_url,publicKey:config.public_key,privateKey:config.private_key}});
      const response=await fetch(request.endpoint,{method:request.method,headers:request.headers,body:request.body,redirect:'error',signal:AbortSignal.timeout(10000)});
      status=response.status;if(response.ok)sent++;
     }
    }catch{status=503;}
    await server('finish',{id:job.id,lease:job.lease,status});
   }));
   return reply({processed:jobs.length,sent});
  }
  // Configuration is available only to a valid, active app member.
  const token=req.headers.get('authorization')?.replace(/^Bearer /i,'');
  if(!token)return reply({error:'Connexion requise.'},401);
  const {data,error}=await service.auth.getUser(token);if(error||!data.user)return reply({error:'Connexion requise.'},401);
  const member=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:'Bearer '+token}},auth:{persistSession:false}});
  const active=await member.rpc('cv_active');if(active.error||!active.data)return reply({error:'Compte indisponible.'},403);
  if(!config.public_key)config=await server('initialize',webpush.generateVAPIDKeys());
  return reply({publicKey:config.public_key});
 }catch{return reply({error:'Le service de notifications est momentanément indisponible.'},503);}
});
