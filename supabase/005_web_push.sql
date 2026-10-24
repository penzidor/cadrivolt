-- Private device subscriptions and a retryable delivery queue. Run after 004.
begin;
create table cadrivolt.push_config (
 id boolean primary key default true check(id),
 public_key text, private_key text, dispatch_secret uuid not null default gen_random_uuid(),
 site_url text not null default 'https://penzidor.github.io/cadrivolt/'
);
insert into cadrivolt.push_config(id) values(true);
create table cadrivolt.push_subscriptions (
 id uuid primary key default gen_random_uuid(), "userId" uuid not null references cadrivolt.accounts(id) on delete cascade,
 endpoint text unique not null check(length(endpoint)<=2048), p256dh text not null, auth text not null,
 "createdAt" timestamptz not null default now()
);
create table cadrivolt.push_deliveries (
 id uuid primary key default gen_random_uuid(), subscription_id uuid not null references cadrivolt.push_subscriptions(id) on delete cascade,
 notification_id uuid references cadrivolt.notifications(id) on delete cascade,
 created_at timestamptz not null default now(), available_at timestamptz not null default now(),
 attempts integer not null default 0, lease uuid, done boolean not null default false, last_status integer,
 unique(subscription_id,notification_id)
);
create index on cadrivolt.push_deliveries(available_at) where not done;
alter table cadrivolt.push_config enable row level security;
alter table cadrivolt.push_subscriptions enable row level security;
alter table cadrivolt.push_deliveries enable row level security;
revoke all on cadrivolt.push_config,cadrivolt.push_subscriptions,cadrivolt.push_deliveries from public,anon,authenticated;

create function public.cv_push_subscription(payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare uid uuid:=cadrivolt.require_user(); ep text:=payload->>'endpoint'; action text:=payload->>'action'; sid uuid;
begin
 if action='status' then return jsonb_build_object('enabled',exists(select 1 from cadrivolt.push_subscriptions where "userId"=uid and endpoint=ep)); end if;
 perform cadrivolt.throttle(uid);
 if action='disable' then delete from cadrivolt.push_subscriptions where "userId"=uid and endpoint=ep; return '{"ok":true}'; end if;
 if action='test' then
  select id into sid from cadrivolt.push_subscriptions where "userId"=uid and endpoint=ep;
  if sid is null then raise exception 'Active les notifications sur cet appareil.'; end if;
  if exists(select 1 from cadrivolt.push_deliveries where subscription_id=sid and notification_id is null and created_at>now()-interval '1 minute') then raise exception 'Attends une minute avant un autre test.'; end if;
  insert into cadrivolt.push_deliveries(subscription_id) values(sid);return '{"ok":true}';
 end if;
 if action<>'enable' or action is null then raise exception 'Action inconnue.'; end if;
 if ep is null or ep !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.push\.apple\.com|web\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)/' then raise exception 'Service de notifications non reconnu.'; end if;
 if coalesce(payload->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}=?$' or coalesce(payload->>'auth','') !~ '^[A-Za-z0-9_-]{22}(==)?$' then raise exception 'Abonnement invalide.'; end if;
 if exists(select 1 from cadrivolt.push_subscriptions where endpoint=ep and "userId"<>uid) then raise exception 'Déconnecte d’abord le précédent compte sur cet appareil.'; end if;
 if (select count(*) from cadrivolt.push_subscriptions where "userId"=uid)>=10 and not exists(select 1 from cadrivolt.push_subscriptions where endpoint=ep and "userId"=uid) then raise exception 'Limite de 10 appareils atteinte.'; end if;
 insert into cadrivolt.push_subscriptions("userId",endpoint,p256dh,auth) values(uid,ep,payload->>'p256dh',payload->>'auth')
 on conflict(endpoint) do update set p256dh=excluded.p256dh,auth=excluded.auth where push_subscriptions."userId"=uid;
 return '{"ok":true}';
end $$;
create function cadrivolt.queue_push() returns trigger language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
begin
 insert into cadrivolt.push_deliveries(subscription_id,notification_id) select id,new.id from cadrivolt.push_subscriptions where "userId"=new."userId";
 return new;
end $$;
create trigger cv_queue_push after insert on cadrivolt.notifications for each row execute function cadrivolt.queue_push();

-- Accessible ONLY to the backend service role; never to application users.
create function public.cv_push_server(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare config cadrivolt.push_config; result jsonb; item cadrivolt.push_deliveries; status_code integer;
begin
 if action in ('config','initialize') then
  select * into config from cadrivolt.push_config where id for update;
  if action='initialize' and config.public_key is null then
   if coalesce(payload->>'publicKey','') !~ '^[A-Za-z0-9_-]{87}$' or coalesce(payload->>'privateKey','') !~ '^[A-Za-z0-9_-]{43}$' then raise exception 'Clés invalides.'; end if;
   update cadrivolt.push_config set public_key=payload->>'publicKey',private_key=payload->>'privateKey' where id returning * into config;
  end if;
  return to_jsonb(config);
 elsif action='claim' then
  -- A notification already read in the website does not need a phone alert.
  update cadrivolt.push_deliveries d set done=true where not done and (created_at<now()-interval '1 day'
   or exists(select 1 from cadrivolt.notifications n where n.id=d.notification_id and n."readAt" is not null)
   or exists(select 1 from cadrivolt.push_subscriptions s join cadrivolt.accounts a on a.id=s."userId" where s.id=d.subscription_id and a.status<>'active'));
  with selected as (select id from cadrivolt.push_deliveries where not done and attempts<5 and available_at<=now() order by created_at for update skip locked limit 30),
  claimed as (update cadrivolt.push_deliveries d set lease=gen_random_uuid(),attempts=attempts+1,available_at=now()+interval '5 minutes' from selected s where d.id=s.id returning d.*)
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'lease',d.lease,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth),'kind',coalesce(n.kind,'test'),'applicationId',n."applicationId")),'[]') into result
  from claimed d join cadrivolt.push_subscriptions s on s.id=d.subscription_id left join cadrivolt.notifications n on n.id=d.notification_id;
  return result;
 elsif action='finish' then
  select * into item from cadrivolt.push_deliveries where id=(payload->>'id')::uuid and lease=(payload->>'lease')::uuid for update;
  if item.id is null then return '{"ok":false}'; end if;
  status_code:=(payload->>'status')::integer;
  if status_code in (404,410) then delete from cadrivolt.push_subscriptions where id=item.subscription_id;
  else update cadrivolt.push_deliveries set done=(status_code between 200 and 299 or attempts>=5),last_status=status_code,available_at=now()+interval '5 minutes',lease=null where id=item.id; end if;
  return '{"ok":true}';
 end if;
 raise exception 'Action inconnue.';
end $$;
revoke all on all functions in schema cadrivolt from public,anon,authenticated;
revoke all on function public.cv_push_subscription(jsonb) from public,anon,authenticated;
revoke all on function public.cv_push_server(text,jsonb) from public,anon,authenticated;
grant execute on function public.cv_push_subscription(jsonb) to authenticated;
grant execute on function public.cv_push_server(text,jsonb) to service_role;
commit;
