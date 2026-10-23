begin;

-- Day 17: extend the existing table. Enum renames preserve every existing row.
-- Clients/SQL using legacy enum labels must switch to the new canonical labels.
alter type public.report_type rename value 'closed' to 'temporarily_closed';
alter type public.report_type rename value 'not_public' to 'not_publicly_accessible';
alter type public.report_type rename value 'dirty' to 'unclean_restroom';
alter type public.report_type rename value 'wrong_hours' to 'incorrect_opening_hours';
alter type public.report_type rename value 'duplicate' to 'duplicate_restroom';
alter type public.report_type add value 'permanently_closed';
alter type public.report_status rename value 'reviewed' to 'in_review';

alter table public.reports
 add column reviewed_at timestamptz,
 add column resolved_at timestamptz,
 add column client_request_id uuid not null default gen_random_uuid(),
 add constraint reports_request_unique unique(user_id,client_request_id),
 -- NOT VALID preserves legacy reports longer than today's limit; all new writes are checked.
 add constraint reports_comment_length check(comment is null or char_length(comment)<=1000) not valid,
 add constraint reports_other_explanation check(report_type::text<>'other' or char_length(btrim(coalesce(comment,''),E' \n\r\t'))>=10) not valid;
create index reports_owner_newest_idx on public.reports(user_id,created_at desc,id desc);
create index reports_recent_issue_idx on public.reports(user_id,restroom_id,report_type,created_at desc);

-- Invoker trigger keeps RLS active. Lock per owner before checking recent rows so
-- simultaneous requests cannot both pass. Volatile PL/pgSQL statements take fresh
-- READ COMMITTED snapshots after the lock. Tested with two concurrent connections.
create function app_private.prepare_report() returns trigger
language plpgsql volatile security invoker set search_path='' as $$
begin
 if not app_private.is_registered_user() or new.user_id is distinct from auth.uid() then
  raise exception using errcode='42501',message='Authenticated report owner required';
 end if;
 new.comment := nullif(btrim(new.comment,E' \n\r\t'),'');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('report:'||new.user_id::text,0));
 -- A retry with the same request UUID goes through ON CONFLICT DO NOTHING.
 if exists(select 1 from public.reports r where r.user_id=new.user_id and r.client_request_id=new.client_request_id) then
  return new;
 end if;
 if exists(select 1 from public.reports r where r.user_id=new.user_id and r.restroom_id=new.restroom_id
   and r.report_type=new.report_type and r.comment is not distinct from new.comment
   and r.created_at > clock_timestamp()-interval '5 minutes') then
  raise exception using errcode='P1701',message='Recent identical report already received';
 end if;
 return new;
end $$;
revoke all on function app_private.prepare_report() from public,anon;
grant execute on function app_private.prepare_report() to authenticated;
create trigger reports_prepare before insert on public.reports for each row execute function app_private.prepare_report();

alter table public.reports enable row level security;
drop policy reports_insert_own on public.reports;
create policy reports_insert_own on public.reports for insert to authenticated with check (
 auth.uid()=user_id and app_private.is_registered_user() and status='pending'
 and reviewed_at is null and resolved_at is null
 and exists(select 1 from public.restrooms r where r.id=restroom_id
  and (r.verification_status='verified' or app_private.is_google_anchor(r)))
);
-- Existing own-read policy remains; no UPDATE or DELETE policies/grants are added.
-- Column permissions prevent forged IDs, timestamps or moderation states on INSERT.
revoke all on public.reports from anon,authenticated;
grant select(id,user_id,restroom_id,report_type,comment,status,created_at,updated_at,reviewed_at,resolved_at,client_request_id)
 on public.reports to authenticated;
grant insert(user_id,restroom_id,report_type,comment,client_request_id) on public.reports to authenticated;
comment on table public.reports is 'Private unverified claims. Submitting never changes published restrooms. Moderation requires a trusted server/admin workflow.';
notify pgrst,'reload schema';

commit;
