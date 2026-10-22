.read docs/verbs/merge.sql

create or replace table contracts as
  select * from read_csv('docs/verbs/contracts.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table owners as
  select * from read_csv('docs/verbs/merged/owners.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table renames as
  select * from read_csv('docs/verbs/merged/renames.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table edgefix as
  select * from read_csv('docs/verbs/merged/edge-fixes.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table added as
  select * from read_csv('docs/verbs/merged/added.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);

create or replace table bidamas as
  select split_part(file, '/', 2) as name from glob('bidamas/*/Bluefile');

create or replace table ranked as
select v.*,
  cast(wave as integer) as w,
  case split_part(blue_today, ':', 1) when 'exists' then 3 when 'partial' then 2 else 0 end as btrank,
  coalesce(o.owner = v.region, false) as is_owner,
  row_number() over (
    partition by v.space, v.verb
    order by
      case split_part(blue_today, ':', 1) when 'exists' then 3 when 'partial' then 2 else 0 end desc,
      coalesce(o.owner = v.region, false) desc,
      length(meaning) desc,
      v.region
  ) as rk
from v left join owners o on o.space = v.space;

create or replace table lat_union as
select space, verb, string_agg(lat, ',' order by lat) as laterals
from (
  select distinct space, verb, unnest(string_split(replace(laterals, 'resume', 'cancel'), ',')) as lat from ranked
) where lat <> '-'
group by space, verb;

create or replace table wave_min as
select space, verb, cast(min(w) as varchar) as wave from ranked group by space, verb;

create or replace table winners3 as
select r.region, r.space, r.verb, r.kind, r.shape, r.fleet, r.blue_today, r.meaning,
  coalesce(l.laterals, '-') as laterals, m.wave
from ranked r
left join lat_union l on l.space = r.space and l.verb = r.verb
join wave_min m on m.space = r.space and m.verb = r.verb
where r.rk = 1;

create or replace table renamed as
select w.region, w.space,
  coalesce(r.newverb, w.verb) as verb,
  w.kind,
  case
    when w.shape not like '%(%' then split_part(w.shape, ' -> ', 1) || '() -> ' || split_part(w.shape, ' -> ', 2)
    when r.newverb is not null then regexp_replace(w.shape, '^[^(]+\(', r.newverb || '(')
    else w.shape end as shape,
  w.laterals, w.fleet, w.blue_today, w.meaning, w.wave,
  w.verb as old_verb
from winners3 w left join renames r on r.space = w.space and r.verb = w.verb;

create or replace table renamed1 as
select * from renamed qualify row_number() over (partition by space, verb order by (old_verb = verb) desc, length(meaning) desc) = 1;

create or replace table keymap as
select space || '::' || verb as oldk, space || '::' || newverb as newk from renames;

create or replace table bt_map as
select blue_today as old,
  case
    when blue_today = 'absent' then 'absent'
    when split_part(blue_today, ':', 2) in (select name from bidamas) then blue_today
    when split_part(blue_today, ':', 2) in ('builtin', 'net') then 'rust:blue-lang-runtime'
    when split_part(blue_today, ':', 2) = 'blue' then 'rust:blue-lang-cli'
    when split_part(blue_today, ':', 2) = 'proc' then 'rust:blue-lang-proc'
    when split_part(blue_today, ':', 2) = 'bidama' then 'rust:blue-lang-bidama'
    else 'rust:' || split_part(blue_today, ':', 2)
  end as new
from (select distinct blue_today from renamed1);

create or replace table verbs0 as
select r.region, r.space, r.verb, r.kind, r.shape, r.laterals, r.fleet, b.new as blue_today, r.meaning, r.wave
from renamed1 r join bt_map b on b.old = r.blue_today
union all
select region, space, verb, kind, shape, laterals, fleet, blue_today, meaning, wave from added;

create or replace table edges_k as
select coalesce(f.newk, e."from") as "from", e.rel, coalesce(t.newk, e."to") as "to", e.why
from e
left join keymap f on f.oldk = e."from"
left join keymap t on t.oldk = e."to";

create or replace table edges_fixed as
select k."from",
  coalesce(case x.action when 'refines' then 'refines' end, k.rel) as rel,
  k."to", k.why
from edges_k k
left join edgefix x on x."from" = k."from" and x.rel = k.rel and x."to" = k."to"
where coalesce(x.action, '') <> 'drop';

create or replace table edges_inv as
select "from", rel, "to", why from edges_fixed
union all
select "to", rel, "from", why from edges_fixed where rel = 'inverse';

create or replace table edges1 as
select "from", rel, "to", min(why) as why from edges_inv group by 1, 2, 3;

create or replace table core_targets as
select distinct split_part("to", '::', 2) as verb from edges1 where "to" like 'core::%';

create or replace table core_rows as
select 'H' as region, 'core' as space, c.verb,
  case when c.kind = 'pure' then 'pure' else 'effect' end as kind,
  c.verb || '(' || replace(replace(c.args, '~', ''), ',', ', ') ||
    case when c.opts = 'yes' then case when c.args = '' then 'opts' else ', opts' end else '' end ||
    ') -> ' || c.returns as shape,
  '-' as laterals, '-' as fleet, 'absent' as blue_today, c.meaning, '0' as wave
from core_targets t join contracts c on c.verb = t.verb;

create or replace table verbs1 as
select * from verbs0 union all select * from core_rows;

create or replace table parsed as
select v.*,
  list_filter(
    list_transform(
      string_split(regexp_replace(regexp_extract(split_part(shape, ' -> ', 1), '\((.*)\)$', 1), '\{[^}]*\}', '{}', 'g'), ','),
      x -> trim(x)),
    x -> x <> '' and x <> 'opts' and x <> '{}') as pos,
  list_contains(
    list_transform(
      string_split(regexp_replace(regexp_extract(split_part(shape, ' -> ', 1), '\((.*)\)$', 1), '\{[^}]*\}', '{}', 'g'), ','),
      x -> trim(x)),
    'opts') or regexp_matches(split_part(shape, ' -> ', 1), '\{[^}]*\}') as has_opts,
  trim(split_part(shape, ' -> ', 2)) as ret
from verbs1 v;

create or replace table cparsed as
select verb, opts as copts, returns,
  list_transform(string_split(args, ','), x -> trim(x)) as raw,
  list_filter(list_transform(string_split(args, ','), x -> trim(x)), x -> x <> '') as items
from contracts;

create or replace table cshape as
select verb, copts, returns, items,
  len(items) as hi,
  len(list_filter(items, x -> not (x like '~%' or x like '%?'))) as lo,
  list_transform(list_filter(items, x -> not (x like '~%' or x like '%?')), x -> x) as req,
  (len(items) > 0 and items[1] like '~%') as ambient
from cparsed;

create or replace table shaped0 as
select p.*, c.verb is not null as has_contract, len(p.pos) as n, c.lo, c.hi, c.copts, c.ambient, c.req,
  c.verb is not null and len(p.pos) >= c.lo and len(p.pos) <= c.hi and (not p.has_opts or c.copts = 'yes') as ok,
  c.verb is not null and len(p.pos) >= c.lo and len(p.pos) <= c.hi as arity_ok
from parsed p left join cshape c on c.verb = p.verb;

create or replace table shaped1 as
select *,
  case
    when not has_contract then pos
    when arity_ok then pos
    when n > hi then pos[1:hi]
    else list_concat(pos, req[n + 1:])
  end as np,
  has_contract and copts = 'yes' and (has_opts or not arity_ok) as add_opts
from shaped0;

create or replace table shaped as
select region, space, verb, kind, shape, laterals, fleet, blue_today, meaning, wave,
  case when not has_contract then ''
       else verb || '(' || array_to_string(case when add_opts then list_append(np, 'opts') else np end, ', ') || ') -> ' || ret end as contract_shape,
  case when not has_contract then 'na' when ok then 'yes' else 'no' end as conforms
from shaped1;

create or replace table srn as
  select * from read_csv('docs/verbs/merged/space-renames.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);

copy (
  select s.region, coalesce(r.new, s.space) as space, s.verb, s.kind, s.shape, s.laterals, s.fleet, s.blue_today, s.meaning, s.wave, s.contract_shape, s.conforms
  from shaped s left join srn r on r.old = s.space order by 2, s.verb
) to 'docs/verbs/merged/verbs.tsv' (delimiter '\t', header true, quote '', escape '');

copy (
  select
    case when a.old is not null then a.new || substr(e."from", length(a.old) + 1) else e."from" end as "from",
    e.rel,
    case when b.old is not null then b.new || substr(e."to", length(b.old) + 1) else e."to" end as "to",
    e.why
  from edges1 e
  left join srn a on split_part(e."from", '::', 1) = a.old
  left join srn b on split_part(e."to", '::', 1) = b.old
  order by 1, 2, 3
) to 'docs/verbs/merged/edges.tsv' (delimiter '\t', header true, quote '', escape '');
