-- AFTER creating and confirming your own account through the website:
-- replace the email below with YOUR exact account email, then run in SQL Editor.
-- Run this manually as the project owner. Never expose it through a public RPC.
do $$
declare chosen uuid;
begin
 select id into chosen from auth.users where lower(email)=lower('REMPLACE_PAR_TON_EMAIL') and email_confirmed_at is not null;
 if chosen is null then raise exception 'Crée et confirme d’abord ce compte, puis remplace l’adresse e-mail dans ce script.'; end if;
 update cadrivolt.accounts set role='admin',status='active' where id=chosen;
 if not found then raise exception 'Profil Cadrivolt absent. Le script 001 doit être installé avant la création du compte.'; end if;
end $$;
