-- Cadrivolt / Supabase. Run once in a NEW project's SQL Editor.
-- No passwords, service keys or administrator are created by this script.
begin;
create schema if not exists cadrivolt;
revoke all on schema cadrivolt from public, anon, authenticated;

create table cadrivolt.accounts (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null, role text not null default 'member' check(role in ('member','admin')),
 status text not null default 'active' check(status in ('active','suspended')),
 "createdAt" timestamptz not null default now()
);
create table cadrivolt.profiles (
 id uuid primary key references cadrivolt.accounts(id) on delete cascade,
 name text not null check(length(name) between 2 and 100),
 role text not null check(role in ('Carspotter','Propriétaire','Les deux')),
 city text not null check(length(city) between 2 and 100),
 bio text not null default '' check(length(bio)<=1000), car text not null default '' check(length(car)<=100)
);
create table cadrivolt.sessions (
 id uuid primary key default gen_random_uuid(), "ownerId" uuid not null references cadrivolt.accounts(id),
 title text not null check(length(title) between 2 and 100),
 category text not null check(category in ('Shooting','Rolling','Rassemblement','Vidéo','Road trip')),
 city text not null check(length(city) between 2 and 100), date date not null,
 time text not null check(time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
 car text not null check(length(car) between 2 and 100),
 description text not null check(length(description) between 20 and 2000),
 spots integer not null check(spots between 1 and 50), price integer not null check(price between 0 and 10000),
 image text not null, status text not null default 'published' check(status in ('published','archived'))
);
create table cadrivolt.applications (
 id uuid primary key default gen_random_uuid(), "sessionId" uuid not null references cadrivolt.sessions(id),
 "userId" uuid not null references cadrivolt.accounts(id), message text not null check(length(message) between 10 and 1500),
 status text not null default 'pending' check(status in ('pending','accepted','declined')),
 "createdAt" timestamptz not null default now(), unique("sessionId","userId")
);
create table cadrivolt.messages (
 id uuid primary key default gen_random_uuid(), "applicationId" uuid not null references cadrivolt.applications(id),
 "senderId" uuid not null references cadrivolt.accounts(id), body text not null check(length(body) between 1 and 2000),
 "createdAt" timestamptz not null default now()
);
create table cadrivolt.favorites (
 "userId" uuid not null references cadrivolt.accounts(id), "sessionId" uuid not null references cadrivolt.sessions(id),
 primary key("userId","sessionId")
);
create table cadrivolt.settings (key text primary key, value jsonb not null);
create table cadrivolt.audit_log (
 id uuid primary key default gen_random_uuid(), "actorId" uuid not null references cadrivolt.accounts(id),
 action text not null, "targetId" text not null, "createdAt" timestamptz not null default now()
);
create table cadrivolt.rate_limits (id uuid primary key, count integer not null, expires timestamptz not null);
create index on cadrivolt.sessions("ownerId");
create index on cadrivolt.sessions(status,date);
create index on cadrivolt.applications("userId");
create index on cadrivolt.messages("applicationId","createdAt");
create index on cadrivolt.audit_log("createdAt" desc);

insert into cadrivolt.settings values
 ('siteName','"Cadrivolt"'),('heroTitle','"De belles autos."'),('heroAccent','"De belles rencontres."'),
 ('heroDescription','"Un regard. Une voiture. Un projet.\nConnecte avec les passionnés qui partagent ta vision."'),
 ('heroImage','"porsche"'),('accentColor','"#ed652b"'),('footerText','"La passion se partage. Le reste se crée."'),
 ('aboutText','"Cadrivolt est le point de rencontre entre celles et ceux qui aiment les belles automobiles et celles et ceux qui savent les mettre en image."'),
 ('contactEmail','""'),('showExamples','false'),('registrationOpen','true');

-- These tables cannot be queried directly by a public browser key. Access uses
-- the narrowly scoped RPCs below; every private operation checks auth.uid().
alter table cadrivolt.accounts enable row level security;
alter table cadrivolt.profiles enable row level security;
alter table cadrivolt.sessions enable row level security;
alter table cadrivolt.applications enable row level security;
alter table cadrivolt.messages enable row level security;
alter table cadrivolt.favorites enable row level security;
alter table cadrivolt.settings enable row level security;
alter table cadrivolt.audit_log enable row level security;
alter table cadrivolt.rate_limits enable row level security;
revoke all on all tables in schema cadrivolt from public,anon,authenticated;

create function cadrivolt.new_user() returns trigger language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
begin
 if (select value from cadrivolt.settings where key='registrationOpen') <> 'true'::jsonb then
   raise exception 'Les inscriptions sont momentanément fermées.';
 end if;
 insert into cadrivolt.accounts(id,email) values(new.id,new.email);
 insert into cadrivolt.profiles(id,name,role,city) values(new.id,
 coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''),'Membre'),
 case when new.raw_user_meta_data->>'role' in ('Carspotter','Propriétaire','Les deux') then new.raw_user_meta_data->>'role' else 'Carspotter' end,
 coalesce(nullif(trim(new.raw_user_meta_data->>'city'),''),'France'));
 return new;
end $$;
create trigger cadrivolt_new_user after insert on auth.users for each row execute function cadrivolt.new_user();

create function cadrivolt.require_user(admin_only boolean default false) returns uuid language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare a cadrivolt.accounts;
begin
 select * into a from cadrivolt.accounts where id=auth.uid();
 if a.id is null or a.status<>'active' then raise exception 'Connexion requise ou compte suspendu.' using errcode='28000'; end if;
 if admin_only and a.role<>'admin' then raise exception 'Accès réservé à l’administration.' using errcode='42501'; end if;
 return a.id;
end $$;
create function public.cv_active() returns boolean language sql stable security definer set search_path=pg_catalog,cadrivolt as $$
 select exists(select 1 from cadrivolt.accounts where id=auth.uid() and status='active')
$$;
create function cadrivolt.throttle(uid uuid) returns void language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare n integer;
begin
 insert into cadrivolt.rate_limits values(uid,1,now()+interval '1 minute')
 on conflict(id) do update set count=case when rate_limits.expires<now() then 1 else rate_limits.count+1 end,
 expires=case when rate_limits.expires<now() then now()+interval '1 minute' else rate_limits.expires end returning count into n;
 if n>120 then raise exception 'Trop d’actions. Réessaie dans une minute.'; end if;
end $$;
create function cadrivolt.check_image(value text, uid uuid, as_admin boolean default false) returns void language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
begin
 if value in ('porsche','camaro','bmw') then return; end if;
 if value is null or value !~ '^storage:[a-f0-9-]{36}/[a-f0-9-]{36}\.(jpg|png|webp)$'
 or (not as_admin and split_part(substr(value,9),'/',1)<>uid::text)
 or not exists(select 1 from storage.objects where bucket_id='cadrivolt-photos' and name=substr(value,9))
 then raise exception 'Photo invalide ou non autorisée.'; end if;
end $$;

create function public.cv_community_data() returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid; result jsonb; own_apps uuid[];
begin
 if auth.uid() is not null then uid:=cadrivolt.require_user(); end if;
 select coalesce(array_agg(a.id),'{}') into own_apps from cadrivolt.applications a join cadrivolt.sessions s on s.id=a."sessionId"
 where a."userId"=uid or s."ownerId"=uid;
 select jsonb_build_object(
 'user',(select jsonb_build_object('id',a.id,'name',p.name,'role',a.role,'email',a.email) from cadrivolt.accounts a join cadrivolt.profiles p using(id) where a.id=uid),
 'settings',(select jsonb_object_agg(key,value) from cadrivolt.settings),
 'sessions',coalesce((select jsonb_agg(to_jsonb(s) order by s.date) from cadrivolt.sessions s join cadrivolt.accounts a on a.id=s."ownerId"
 where (a.status='active' and s.status='published') or s."ownerId"=uid
 or exists(select 1 from cadrivolt.applications ap where ap.id=any(own_apps) and ap."sessionId"=s.id)),'[]'),
 'profiles',coalesce((select jsonb_agg(to_jsonb(p)) from cadrivolt.profiles p join cadrivolt.accounts a using(id) where a.status='active'),'[]'),
 'favorites',coalesce((select jsonb_agg("sessionId") from cadrivolt.favorites where "userId"=uid),'[]'),
 'applications',coalesce((select jsonb_agg(to_jsonb(a)) from cadrivolt.applications a where id=any(own_apps)),'[]'),
 'messages',coalesce((select jsonb_agg(to_jsonb(m) order by m."createdAt") from cadrivolt.messages m where "applicationId"=any(own_apps)),'[]')) into result;
 return result;
end $$;

-- All writes are transactions; locking the session serializes capacity changes.
create function public.cv_community_action(payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(); action text:=payload->>'action'; d jsonb:=payload->'data'; sid uuid;
 s cadrivolt.sessions; a cadrivolt.applications; n integer;
begin
 perform cadrivolt.throttle(uid);
 if action='profile' then
   update cadrivolt.profiles set name=trim(d->>'name'),role=d->>'role',city=trim(d->>'city'),bio=coalesce(trim(d->>'bio'),''),car=coalesce(trim(d->>'car'),'') where id=uid;
 elsif action in ('create','edit') then
   if action='edit' then
     select * into s from cadrivolt.sessions where id=(payload->>'id')::uuid for update;
     if s.id is null or s."ownerId"<>uid then raise exception 'Modification non autorisée.' using errcode='42501'; end if;
     select count(*) into n from cadrivolt.applications where "sessionId"=s.id and status='accepted';
     if (d->>'spots')::integer<n then raise exception 'Des places sont déjà confirmées.'; end if;
   end if;
   if (d->>'date')::date < (now() at time zone 'Europe/Paris')::date and (action='create' or (d->>'date')::date<>s.date) then raise exception 'Choisis une date à venir.'; end if;
   perform cadrivolt.check_image(d->>'image',uid);
   if action='create' then
     insert into cadrivolt.sessions("ownerId",title,category,city,date,time,car,description,spots,price,image)
     values(uid,trim(d->>'title'),d->>'category',trim(d->>'city'),(d->>'date')::date,d->>'time',trim(d->>'car'),trim(d->>'description'),(d->>'spots')::integer,(d->>'price')::integer,d->>'image');
   else
     update cadrivolt.sessions set title=trim(d->>'title'),category=d->>'category',city=trim(d->>'city'),date=(d->>'date')::date,time=d->>'time',car=trim(d->>'car'),description=trim(d->>'description'),spots=(d->>'spots')::integer,price=(d->>'price')::integer,image=d->>'image' where id=s.id;
   end if;
 elsif action in ('archive','restore','favorite','apply') then
   select * into s from cadrivolt.sessions where id=(payload->>'id')::uuid for update;
   if s.id is null then raise exception 'Session introuvable.'; end if;
   if action in ('archive','restore') then
     if s."ownerId"<>uid then raise exception 'Action non autorisée.' using errcode='42501'; end if;
     update cadrivolt.sessions set status=case when action='archive' then 'archived' else 'published' end where id=s.id;
   elsif action='favorite' then
     if exists(select 1 from cadrivolt.favorites where "userId"=uid and "sessionId"=s.id) then delete from cadrivolt.favorites where "userId"=uid and "sessionId"=s.id;
     else
       if s.status<>'published' or not exists(select 1 from cadrivolt.accounts where id=s."ownerId" and status='active') then raise exception 'Session indisponible.'; end if;
       insert into cadrivolt.favorites values(uid,s.id);
     end if;
   else
     if s."ownerId"=uid then raise exception 'Tu organises déjà cette session.'; end if;
     if s.status<>'published' or s.date<(now() at time zone 'Europe/Paris')::date or not exists(select 1 from cadrivolt.accounts where id=s."ownerId" and status='active') then raise exception 'Session indisponible.'; end if;
     if exists(select 1 from cadrivolt.applications where "userId"=uid and "sessionId"=s.id) then raise exception 'Ta demande existe déjà.'; end if;
     insert into cadrivolt.applications("sessionId","userId",message) values(s.id,uid,trim(payload->>'message'));
   end if;
 elsif action in ('respond','message') then
   select * into a from cadrivolt.applications where id=(payload->>'id')::uuid;
   select * into s from cadrivolt.sessions where id=a."sessionId" for update;
   if a.id is null or (s."ownerId"<>uid and a."userId"<>uid) then raise exception 'Conversation privée.' using errcode='42501'; end if;
   if action='message' then
     insert into cadrivolt.messages("applicationId","senderId",body) values(a.id,uid,trim(payload->>'body'));
   else
     if s."ownerId"<>uid then raise exception 'Seul l’organisateur peut répondre.' using errcode='42501'; end if;
     if payload->>'status' not in ('accepted','declined') or payload->>'status' is null then raise exception 'Réponse invalide.'; end if;
     select count(*) into n from cadrivolt.applications where "sessionId"=s.id and status='accepted' and id<>a.id;
     if payload->>'status'='accepted' and n>=s.spots then raise exception 'Toutes les places sont prises.'; end if;
     update cadrivolt.applications set status=payload->>'status' where id=a.id;
   end if;
 else raise exception 'Action inconnue.';
 end if;
 return '{"ok":true}'::jsonb;
end $$;

create function public.cv_admin_data(table_name text default null, page_number integer default 0, export_data boolean default false) returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(true); data jsonb; rows jsonb; counts jsonb; k text; p integer:=greatest(0,least(100000,coalesce(page_number,0)));
begin
 data:=jsonb_build_object(
 'accounts',coalesce((select jsonb_agg(to_jsonb(t) order by t."createdAt" desc) from cadrivolt.accounts t),'[]'),
 'profiles',coalesce((select jsonb_agg(to_jsonb(t)) from cadrivolt.profiles t),'[]'),
 'sessions',coalesce((select jsonb_agg(to_jsonb(t) order by date desc) from cadrivolt.sessions t),'[]'),
 'applications',coalesce((select jsonb_agg(to_jsonb(t)) from cadrivolt.applications t),'[]'),
 'messages',coalesce((select jsonb_agg(to_jsonb(t)) from cadrivolt.messages t),'[]'),
 'favorites',coalesce((select jsonb_agg(to_jsonb(t)) from cadrivolt.favorites t),'[]'),
 'settings',coalesce((select jsonb_agg(to_jsonb(t)) from cadrivolt.settings t),'[]'),
 'auditLog',coalesce((select jsonb_agg(to_jsonb(t) order by t."createdAt" desc) from cadrivolt.audit_log t),'[]'),
 'uploads',coalesce((select jsonb_agg(jsonb_build_object('id',id,'path',name,'createdAt',created_at,'size',metadata->'size')) from storage.objects where bucket_id='cadrivolt-photos'),'[]'));
 if table_name is not null then
   if not data ? table_name then raise exception 'Table non autorisée.' using errcode='42501'; end if;
   select coalesce(jsonb_agg(value),'[]') into rows from (select value from jsonb_array_elements(data->table_name) limit 50 offset p*50) t;
   return jsonb_build_object('table',table_name,'page',p,'rows',rows);
 end if;
 if export_data then
   insert into cadrivolt.audit_log("actorId",action,"targetId") values(uid,'export_data','business');
   return jsonb_build_object('format','cadrivolt-supabase-v1','exportedAt',now(),'members',data->'accounts','data',data-'accounts');
 end if;
 select jsonb_object_agg(key,jsonb_array_length(value)) into counts from jsonb_each(data);
 return jsonb_build_object('user',(select jsonb_build_object('name',p.name,'email',a.email) from cadrivolt.accounts a join cadrivolt.profiles p using(id) where a.id=uid),
 'members',data->'accounts','profiles',data->'profiles','sessions',data->'sessions','counts',counts,
 'settings',(select jsonb_object_agg(key,value) from cadrivolt.settings),
 'activity',(select coalesce(jsonb_agg(value),'[]') from (select value from jsonb_array_elements(data->'auditLog') limit 30) t));
end $$;

create function public.cv_admin_action(payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(true); action text:=payload->>'action'; d jsonb:=payload->'data'; sid uuid;
 s cadrivolt.sessions; k text; v jsonb; n integer; label text;
begin
 perform cadrivolt.throttle(uid);
 if action='settings' then
   if jsonb_typeof(d)<>'object' or d is null then raise exception 'Réglages invalides.'; end if;
   for k,v in select * from jsonb_each(d) loop
     if not exists(select 1 from cadrivolt.settings where key=k) then raise exception 'Réglage inconnu.'; end if;
     if k in ('showExamples','registrationOpen') then
       if jsonb_typeof(v)<>'boolean' then raise exception 'Valeur invalide.'; end if;
     else
       if jsonb_typeof(v)<>'string' or length(d->>k)>2000 then raise exception 'Texte invalide.'; end if;
       if k='siteName' and length(trim(d->>k)) not between 2 and 25 then raise exception 'Nom invalide.'; end if;
       if k='accentColor' and d->>k !~ '^#[a-fA-F0-9]{6}$' then raise exception 'Couleur invalide.'; end if;
       if k='heroImage' then perform cadrivolt.check_image(d->>k,uid,true); end if;
       if k='contactEmail' and d->>k<>'' and d->>k !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'E-mail invalide.'; end if;
     end if;
     update cadrivolt.settings set value=v where key=k;
   end loop;
   label:='update_settings';
 elsif action in ('member','memberStatus') then
   sid:=(payload->>'id')::uuid;
   if not exists(select 1 from cadrivolt.accounts where id=sid) then raise exception 'Membre introuvable.'; end if;
   if action='member' then
     update cadrivolt.profiles set name=trim(d->>'name'),role=d->>'role',city=trim(d->>'city'),bio=coalesce(trim(d->>'bio'),''),car=coalesce(trim(d->>'car'),'') where id=sid;
     label:='edit_member';
   else
     if exists(select 1 from cadrivolt.accounts where id=sid and role='admin') then raise exception 'Le compte administrateur ne peut pas être suspendu.'; end if;
     update cadrivolt.accounts set status=payload->>'status' where id=sid;
     label:=case when payload->>'status'='active' then 'restore_member' else 'suspend_member' end;
   end if;
 elsif action in ('session','sessionStatus') then
   sid:=(payload->>'id')::uuid;
   select * into s from cadrivolt.sessions where id=sid for update;
   if s.id is null then raise exception 'Session introuvable.'; end if;
   if action='sessionStatus' then
     update cadrivolt.sessions set status=payload->>'status' where id=sid;
     label:=case when payload->>'status'='published' then 'restore_session' else 'archive_session' end;
   else
     select count(*) into n from cadrivolt.applications where "sessionId"=sid and status='accepted';
     if (d->>'spots')::integer<n then raise exception 'Des places sont déjà confirmées.'; end if;
     perform cadrivolt.check_image(d->>'image',uid,true);
     update cadrivolt.sessions set title=trim(d->>'title'),category=d->>'category',city=trim(d->>'city'),date=(d->>'date')::date,time=d->>'time',car=trim(d->>'car'),description=trim(d->>'description'),spots=(d->>'spots')::integer,price=(d->>'price')::integer,image=d->>'image' where id=sid;
     label:='edit_session';
   end if;
 else raise exception 'Action inconnue.';
 end if;
 insert into cadrivolt.audit_log("actorId",action,"targetId") values(uid,label,coalesce(sid::text,'site'));
 return '{"ok":true}'::jsonb;
end $$;

-- Photo storage is public by design; credentials and conversations never enter it.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('cadrivolt-photos','cadrivolt-photos',true,8388608,array['image/jpeg','image/png','image/webp']);
create policy cadrivolt_upload on storage.objects for insert to authenticated
 with check(bucket_id='cadrivolt-photos' and (storage.foldername(name))[1]=auth.uid()::text and public.cv_active());
-- No UPDATE policy: an uploaded photo cannot be silently overwritten.

revoke all on all functions in schema cadrivolt from public,anon,authenticated;
revoke all on function public.cv_active() from public,anon,authenticated;
revoke all on function public.cv_community_data() from public,anon,authenticated;
revoke all on function public.cv_community_action(jsonb) from public,anon,authenticated;
revoke all on function public.cv_admin_data(text,integer,boolean) from public,anon,authenticated;
revoke all on function public.cv_admin_action(jsonb) from public,anon,authenticated;
grant execute on function public.cv_active() to authenticated;
grant execute on function public.cv_community_data() to anon,authenticated;
grant execute on function public.cv_community_action(jsonb) to authenticated;
grant execute on function public.cv_admin_data(text,integer,boolean) to authenticated;
grant execute on function public.cv_admin_action(jsonb) to authenticated;
commit;

