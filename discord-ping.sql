-- Narellan Federal Court: Discord ping for new filings
--
-- WHAT IT DOES
--   When a player files a case on the website, a short message appears in a Discord
--   channel of your choice: the reference number, the type, who filed against whom,
--   and a link to the Clerk's Desk. It never includes what the player wrote or their evidence.
--
-- BEFORE YOU RUN THIS
--   1. In Discord, make a private channel for clerks, for example #new-filings.
--      Click the gear next to the channel > Integrations > Webhooks > New Webhook > Copy Webhook URL.
--   2. In Supabase, go to Database > Extensions, search for pg_net, and switch it on.
--   3. Find the line below that says https://discord.com/api/webhooks/1567112083055714426/NUtJ3jk5fV87ogzTNG5ul1LHRWeI5wpOfBDgPs1onSv048tzPxncLeuf6HP-ssPsTrjD and replace those
--      words with the webhook URL. Keep the single quotes around it.
--   4. Paste this whole file into Supabase > SQL Editor and click Run.
--
-- KEEP THE WEBHOOK URL PRIVATE
--   Anyone who has it can post in your channel. Only put it in this SQL, inside Supabase.
--   Never put it in config.js, index.html or your GitHub repo.
--
-- It is safe to run twice. To change the webhook later, edit the line and run it again.

create extension if not exists pg_net;

create or replace function public.notify_new_filing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hook text := 'https://discord.com/api/webhooks/1567112083055714426/NUtJ3jk5fV87ogzTNG5ul1LHRWeI5wpOfBDgPs1onSv048tzPxncLeuf6HP-ssPsTrjD';
  v_desk text := 'https://henryorsm.github.io/tc-narellan-court/clerk.html';
  v_text text;
begin
  v_text := '**New filing** `' || new.ref || '`' || E'\n'
         || new.type || ' - ' || coalesce(new.filer, '?') || ' against ' || coalesce(new.defendant, '?') || E'\n'
         || 'Review it: ' || v_desk;
  perform net.http_post(
    url := v_hook,
    body := jsonb_build_object(
      'username', 'Narellan Court Clerk',
      'content', left(v_text, 1900),
      'allowed_mentions', jsonb_build_object('parse', jsonb_build_array()),
      'flags', 4
    )
  );
  return null;
exception when others then
  -- A Discord problem must never stop someone from filing a case.
  return null;
end
$$;
revoke execute on function public.notify_new_filing() from public, anon, authenticated;

drop trigger if exists notify_new_filing on public.cases;
create trigger notify_new_filing
  after insert on public.cases
  for each row
  when (new.visibility = 'pending' and new.filer is not null)
  execute function public.notify_new_filing();
