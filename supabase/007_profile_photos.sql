-- Profile photo changes are atomic with the profile and restricted to owned uploads.
begin;
alter table cadrivolt.profiles add column if not exists avatar text not null default '' check(length(avatar)<=200);
create or replace function public.cv_community_action(payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(); action text:=payload->>'action'; d jsonb:=payload->'data'; sid uuid;
 s cadrivolt.sessions; a cadrivolt.applications; n integer;
begin
 perform cadrivolt.throttle(uid);
 if action='profile' then
   if d ? 'avatar' then
     if jsonb_typeof(d->'avatar') <> 'string' or d->>'avatar' is null then raise exception 'Photo invalide.'; end if;
     if d->>'avatar' <> '' then
       if left(d->>'avatar',8) <> 'storage:' then raise exception 'Photo invalide.'; end if;
       perform cadrivolt.check_image(d->>'avatar',uid);
     end if;
   end if;
   update cadrivolt.profiles set name=trim(d->>'name'),role=d->>'role',city=trim(d->>'city'),bio=coalesce(trim(d->>'bio'),''),car=coalesce(trim(d->>'car'),''),avatar=case when d ? 'avatar' then d->>'avatar' else avatar end where id=uid;
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
notify pgrst, 'reload schema';
commit;
