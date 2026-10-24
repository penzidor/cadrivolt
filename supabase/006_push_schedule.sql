-- Run on hosted Supabase after 005 and deployment of cadrivolt-push.
-- The function authenticates requests with a private dispatch token or user JWT.
begin;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
create function cadrivolt.dispatch_push() returns void language plpgsql security definer set search_path=pg_catalog,cadrivolt as $$
declare secret text;
begin
 if not exists(select 1 from cadrivolt.push_deliveries where not done and attempts<5 and available_at<=now()) then return; end if;
 select dispatch_secret::text into secret from cadrivolt.push_config where id;
 perform net.http_post(
  url:='https://pvaoczsykclahivhndow.supabase.co/functions/v1/cadrivolt-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-cadrivolt-dispatch',secret),
  body:='{}'::jsonb,timeout_milliseconds:=60000);
end $$;
revoke all on function cadrivolt.dispatch_push() from public,anon,authenticated;
select cron.schedule('cadrivolt-push-delivery','* * * * *','select cadrivolt.dispatch_push();');
commit;
