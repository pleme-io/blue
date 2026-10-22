create or replace table mv as
  select * from read_csv('docs/verbs/merged/verbs.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table me as
  select * from read_csv('docs/verbs/merged/edges.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table mc as
  select * from read_csv('docs/verbs/contracts.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);

.mode box

select 'verbs' as k, count(*) as n from mv
union all select 'edges', count(*) from me
union all select 'spaces', count(distinct space) from mv
union all select 'provisional spaces', count(distinct space) from mv where space like '%?'
union all select 'contracts', count(*) from mc
union all select 'contracts open', count(*) from mc where status = 'open'
union all select 'contracts stdlib', count(*) from mc where status = 'stdlib'
union all select 'contracts decided', count(*) from mc where status = 'decided'
union all select 'verbs with a contract', count(*) from mv where conforms <> 'na'
union all select 'verbs conforming', count(*) from mv where conforms = 'yes'
union all select 'verbs not conforming', count(*) from mv where conforms = 'no';

select split_part(blue_today, ':', 1) as status, count(*) as n from mv group by 1 order by 2 desc;

select rel, count(*) as n from me group by 1 order by 2 desc;

select verb, count(*) as rows, count(*) filter (where conforms = 'yes') as conforming,
  count(*) filter (where conforms = 'no') as not_conforming,
  round(100.0 * count(*) filter (where conforms = 'yes') / count(*), 1) as pct
from mv where conforms <> 'na' group by verb
order by not_conforming desc, rows desc limit 40;

select 'residual defects' as k;
.read docs/verbs/queries/gate.sql
