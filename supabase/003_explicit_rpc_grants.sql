-- Tighten explicit function grants, including Supabase's default role grants.
begin;
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
