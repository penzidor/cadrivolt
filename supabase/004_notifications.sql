-- Run after 001 and 003. Private, persistent notifications for future events.
begin;
create table cadrivolt.notifications (
 id uuid primary key default gen_random_uuid(),
 "userId" uuid not null references cadrivolt.accounts(id) on delete cascade,
 "applicationId" uuid not null references cadrivolt.applications(id) on delete cascade,
 kind text not null check(kind in ('application','accepted','declined','message','session')),
 title text not null, body text not null,
 "createdAt" timestamptz not null default clock_timestamp(), "readAt" timestamptz
);
create index on cadrivolt.notifications("userId","createdAt" desc,id desc);
create index on cadrivolt.notifications("userId") where "readAt" is null;
alter table cadrivolt.notifications enable row level security;
revoke all on cadrivolt.notifications from public,anon,authenticated;

create function cadrivolt.notify_member(recipient uuid, application uuid, event_kind text, heading text, detail text)
returns void language sql security definer set search_path=pg_catalog,cadrivolt as $$
 insert into cadrivolt.notifications("userId","applicationId",kind,title,body)
 select recipient,application,event_kind,heading,detail
 where exists(select 1 from cadrivolt.accounts where id=recipient and status='active');
$$;
create function cadrivolt.notify_application() returns trigger language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare s cadrivolt.sessions; actor text;
begin
 select * into s from cadrivolt.sessions where id=new."sessionId";
 if tg_op='INSERT' then
  select name into actor from cadrivolt.profiles where id=new."userId";
  perform cadrivolt.notify_member(s."ownerId",new.id,'application','Nouvelle demande de participation',actor||' souhaite rejoindre « '||s.title||' ».');
 elsif new.status is distinct from old.status and new.status in ('accepted','declined') then
  perform cadrivolt.notify_member(new."userId",new.id,new.status,
    case when new.status='accepted' then 'Ta participation est confirmée' else 'Une réponse à ta demande' end,
    case when new.status='accepted' then 'Tu rejoins « '||s.title||' ».' else 'Ta demande pour « '||s.title||' » n’a pas été retenue.' end);
 end if;
 return new;
end $$;
create trigger cv_application_notification after insert or update of status on cadrivolt.applications
 for each row execute function cadrivolt.notify_application();
create function cadrivolt.notify_message() returns trigger language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare a cadrivolt.applications; s cadrivolt.sessions; recipient uuid; actor text;
begin
 select * into a from cadrivolt.applications where id=new."applicationId";
 select * into s from cadrivolt.sessions where id=a."sessionId";
 recipient:=case when new."senderId"=s."ownerId" then a."userId" else s."ownerId" end;
 select name into actor from cadrivolt.profiles where id=new."senderId";
 if recipient<>new."senderId" then
  perform cadrivolt.notify_member(recipient,a.id,'message','Nouveau message',actor||' t’a écrit au sujet de « '||s.title||' ».');
 end if;
 return new;
end $$;
create trigger cv_message_notification after insert on cadrivolt.messages for each row execute function cadrivolt.notify_message();
create function cadrivolt.notify_session() returns trigger language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare a cadrivolt.applications;
begin
 if row(new.title,new.date,new.time,new.city,new.status,new.price) is distinct from row(old.title,old.date,old.time,old.city,old.status,old.price) then
  for a in select * from cadrivolt.applications where "sessionId"=new.id and status in ('pending','accepted') loop
   perform cadrivolt.notify_member(a."userId",a.id,'session',case when new.status='archived' then 'Session archivée' else 'Session mise à jour' end,
    'Consulte les dernières informations de « '||new.title||' ».');
  end loop;
 end if;
 return new;
end $$;
create trigger cv_session_notification after update on cadrivolt.sessions for each row execute function cadrivolt.notify_session();

create function public.cv_notifications(before_at timestamptz default null,before_id uuid default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(); result jsonb;
begin
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(n) - 'userId' order by n."createdAt" desc,n.id desc)
 from (select * from cadrivolt.notifications where "userId"=uid and
 (before_at is null or ("createdAt",id)<(before_at,coalesce(before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
 order by "createdAt" desc,id desc limit 50) n),'[]'),
 'unread',(select count(*) from cadrivolt.notifications where "userId"=uid and "readAt" is null),
 'checkedAt',clock_timestamp()) into result;
 return result;
end $$;
create function public.cv_notifications_read(ids uuid[] default null,through_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(); changed integer;
begin
 perform cadrivolt.throttle(uid);
 if coalesce(array_length(ids,1),0)>100 then raise exception 'Trop de notifications.'; end if;
 update cadrivolt.notifications set "readAt"=clock_timestamp() where "userId"=uid and "readAt" is null
 and (id=any(ids) or (through_at is not null and "createdAt"<=least(through_at,clock_timestamp())));
 get diagnostics changed=row_count;
 return jsonb_build_object('changed',changed);
end $$;
revoke all on all functions in schema cadrivolt from public,anon,authenticated;
revoke all on function public.cv_notifications(timestamptz,uuid) from public,anon,authenticated;
revoke all on function public.cv_notifications_read(uuid[],timestamptz) from public,anon,authenticated;
grant execute on function public.cv_notifications(timestamptz,uuid) to authenticated;
grant execute on function public.cv_notifications_read(uuid[],timestamptz) to authenticated;
commit;
