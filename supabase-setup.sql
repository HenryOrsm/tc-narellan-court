-- Narellan Federal Court: database setup for Supabase
--
-- BEFORE YOU RUN THIS:
--   Find the line that says narellanfederalcourt1874@gmail.com (inside the is_clerk function, near the middle)
--   and replace it with the email address you will use to sign in to the Clerk's Desk.
--   For more than one clerk, write them like:  'one@example.com', 'two@example.com'
--
-- Then paste this whole file into Supabase > SQL Editor and click Run.
-- It is safe to run twice.

-- ---------- tables ----------
create table if not exists public.cases (
  id bigint generated always as identity primary key,
  ref text unique not null,
  title text not null,
  type text not null default 'Civil claim',
  status text not null default 'Pending',
  visibility text not null default 'pending' check (visibility in ('pending', 'public', 'rejected')),
  filed date not null default ((now() at time zone 'Australia/Brisbane')::date),
  judge text,
  when_label text,
  when_date date,
  outcome text,
  doc jsonb,
  filer text,
  defendant text,
  incident_date date,
  summary text,
  evidence text,
  orig_ref text,
  created_at timestamptz not null default now()
);

create table if not exists public.case_counters (
  year int primary key,
  n int not null
);

alter table public.cases enable row level security;
alter table public.case_counters enable row level security;
revoke all on public.cases from anon;
revoke all on public.case_counters from anon, authenticated;

-- ---------- who counts as a clerk ----------
create or replace function public.is_clerk()
returns boolean
language sql
stable
as $$
  select coalesce((auth.jwt() ->> 'email') = any (array['narellanfederalcourt1874@gmail.com']), false)
$$;

drop policy if exists clerks_all on public.cases;
create policy clerks_all on public.cases
  for all to authenticated
  using (public.is_clerk())
  with check (public.is_clerk());

-- ---------- what the public can read ----------
create or replace view public.public_cases as
  select ref, title, type, status, filed, judge,
         when_label as "whenLabel", when_date as "when", outcome, doc
  from public.cases
  where visibility = 'public';

grant select on public.public_cases to anon, authenticated;

-- ---------- reference numbers ----------
create or replace function public.make_ref()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year int := extract(year from (now() at time zone 'Australia/Brisbane'))::int;
  v_n int;
begin
  insert into public.case_counters as cc (year, n) values (v_year, 1)
  on conflict (year) do update set n = cc.n + 1
  returning cc.n into v_n;
  return 'NFC-' || v_year || '-' || lpad(v_n::text, 4, '0');
end
$$;
revoke execute on function public.make_ref() from public, anon, authenticated;

create or replace function public.claim_ref()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_clerk() then
    raise exception 'Clerks only';
  end if;
  return public.make_ref();
end
$$;
revoke execute on function public.claim_ref() from public, anon;
grant execute on function public.claim_ref() to authenticated;

-- ---------- filing a case (anyone) ----------
create or replace function public.file_case(
  p_type text, p_filer text, p_defendant text, p_incident date,
  p_summary text, p_evidence text, p_orig text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
begin
  if p_type not in ('Civil claim', 'Property dispute', 'Rule violation', 'Appeal') then
    raise exception 'Invalid type of filing';
  end if;
  if length(trim(coalesce(p_filer, ''))) not between 1 and 40 then
    raise exception 'Enter your username (up to 40 characters)';
  end if;
  if length(trim(coalesce(p_defendant, ''))) not between 1 and 40 then
    raise exception 'Enter the other party username (up to 40 characters)';
  end if;
  if length(trim(coalesce(p_summary, ''))) not between 1 and 3000 then
    raise exception 'Describe what happened (up to 3000 characters)';
  end if;
  if length(coalesce(p_evidence, '')) > 2000 then
    raise exception 'Evidence is too long (up to 2000 characters)';
  end if;
  if (select count(*) from public.cases where created_at > now() - interval '1 minute') >= 10 then
    raise exception 'Too many filings right now. Try again in a minute';
  end if;
  if (select count(*) from public.cases where visibility = 'pending') >= 300 then
    raise exception 'The court has a backlog. Try again later';
  end if;

  v_ref := public.make_ref();
  insert into public.cases (ref, title, type, status, visibility, filed, filer, defendant, incident_date, summary, evidence, orig_ref)
  values (
    v_ref,
    trim(p_filer) || ' v. ' || trim(p_defendant),
    p_type, 'Pending', 'pending',
    (now() at time zone 'Australia/Brisbane')::date,
    trim(p_filer), trim(p_defendant), p_incident,
    trim(p_summary),
    nullif(trim(coalesce(p_evidence, '')), ''),
    nullif(trim(coalesce(p_orig, '')), '')
  );
  return v_ref;
end
$$;
grant execute on function public.file_case(text, text, text, date, text, text, text) to anon, authenticated;

-- ---------- looking up a case (anyone) ----------
create or replace function public.lookup_case(p_ref text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when visibility = 'public' then jsonb_build_object(
      'ref', ref, 'title', title, 'type', type, 'status', status, 'filed', filed,
      'judge', judge, 'whenLabel', when_label, 'when', when_date, 'outcome', outcome, 'doc', doc)
    when visibility = 'pending' then jsonb_build_object(
      'ref', ref, 'type', type, 'status', 'Pending', 'filed', filed, 'pending', true)
  end
  from public.cases
  where ref = upper(trim(p_ref))
  limit 1
$$;
grant execute on function public.lookup_case(text) to anon, authenticated;

-- ---------- the cases already on the site ----------
insert into public.cases (ref, title, type, status, visibility, filed, judge, when_label, when_date, outcome, doc)
values (
  'NFC-2026-1102-VF', 'Cease and Desist Notice to Trainfan3714', 'Cease and desist notice', 'Issued', 'public', '2026-11-02', 'Office of the Chief Justice', 'Issued', '2026-11-02', 'Mr Falsetta is directed to stop scheduling community events at times that exclude Narellan citizens and to give a written explanation for the 8:00 AM Monday Halloween event. Further proceedings may follow if he does not comply.',
  $doc$[{"t": "org", "x": "THE NARELLAN FEDERAL COURT"}, {"t": "sub", "x": "OFFICE OF THE CHIEF JUSTICE"}, {"t": "title", "x": "FORMAL CEASE AND DESIST NOTICE"}, {"t": "meta", "x": [["Case Reference", "NFC-2026-1102-VF"], ["Date", "2 November 2026"], ["To", "Vincent \"Trainfan3714\" Falsetta"], ["From", "The Narellan Federal Court"], ["Subject", "Systematic Discrimination Against the Citizens of Narellan Through Deliberately Inaccessible Event Scheduling"]]}, {"t": "h", "x": "NOTICE TO CEASE AND DESIST"}, {"t": "p", "x": "Dear Mr Falsetta,"}, {"t": "p", "x": "The Narellan Federal Court hereby issues this formal Cease and Desist Notice concerning your repeated conduct in organising community events at times that render participation by the citizens of Narellan virtually impossible."}, {"t": "p", "x": "The Court has received substantial complaints regarding your organisation of events, most notably the recent Halloween event, which was scheduled for 8:00 AM on a Monday morning."}, {"t": "p", "x": "The Court considers this scheduling decision particularly egregious."}, {"t": "p", "x": "By scheduling a community event at such an unreasonable hour on a weekday, you effectively excluded almost the entire population of Narellan from participating in what should have been an inclusive community occasion."}, {"t": "p", "x": "The Court further notes that:"}, {"t": "ol", "x": ["The overwhelming majority of Narellan citizens were unable to attend the aforementioned Halloween event.", "No reasonable consideration appears to have been given to the availability of Narellan residents.", "This incident forms part of a broader pattern of event scheduling that disproportionately disadvantages the Narellan population.", "Your actions have caused considerable outrage among Narellan citizens and have undermined the principles of community participation and equality."]}, {"t": "h", "x": "FORMAL DEMANDS"}, {"t": "p", "x": "The Narellan Federal Court hereby DEMANDS that Mr Falsetta:"}, {"t": "ol", "x": ["Immediately cease organising events in a manner that systematically excludes Narellan citizens.", "Provide reasonable consideration to the schedules and availability of Narellan residents when arranging future events.", "Refrain from scheduling community-wide events at unreasonable times, including but not limited to weekday mornings.", "Provide a formal written explanation for the decision to schedule the Halloween event at 8:00 AM on a Monday.", "Commit to ensuring that future community events are accessible to all participating populations, irrespective of their place of residence."]}, {"t": "h", "x": "CONSEQUENCES OF NON-COMPLIANCE"}, {"t": "p", "x": "Should you fail to comply with the demands outlined in this notice, the Narellan Federal Court reserves the right to initiate further proceedings, including but not limited to:"}, {"t": "ul", "x": ["Formal condemnation by the Narellan Federal Court.", "A public declaration of your failure to uphold community inclusion.", "Referral of the matter to the Narellan Federal Government for consideration of further action."]}, {"t": "h", "x": "FINAL STATEMENT"}, {"t": "p", "x": "The Narellan Federal Court wishes to make its position abundantly clear: the citizens of Narellan are not second-class participants in community life, nor should they be expected to rearrange their entire Monday morning schedules to accommodate your frankly questionable event-planning abilities."}, {"t": "p", "x": "Scheduling a Halloween event for 8:00 AM on a Monday is not merely inconsiderate. It is an achievement in administrative incompetence."}, {"t": "p", "x": "The Court has little interest in entertaining further excuses, justifications, or attempts to pass this off as a simple scheduling oversight."}, {"t": "p", "x": "Get your act together, Mr Falsetta. Narellan has had quite enough of your nonsense."}, {"t": "p", "x": "We trust that this matter is now sufficiently clear. Frankly, we would prefer not to have to explain basic calendar literacy to you again."}, {"t": "p", "x": "Yours in the pursuit of justice,"}, {"t": "sign", "x": "THE OFFICE OF THE CHIEF JUSTICE", "y": "Narellan Federal Court"}, {"t": "motto", "x": "FIAT JUSTITIA.", "y": "Let justice be done."}]$doc$::jsonb
)
on conflict (ref) do nothing;
