.read docs/verbs/merge.sql
.mode box
create or replace table vn as
select *,
  regexp_extract(shape, '\(([^)]*)\)', 1) as argtext,
  trim(regexp_extract(shape, '->\s*(.*)$', 1)) as ret
from v;
create or replace table va as
select *,
  case when trim(argtext)='' then 0
       else len(string_split(argtext, ',')) - (case when argtext like '%opts%' then 1 else 0 end) end as arity,
  (argtext like '%opts%') as has_opts
from vn;
select count(distinct verb) distinct_verbs, count(*) n_rows, count(distinct space) n_spaces,
       count(distinct case when space like '%?' then space end) provisional_spaces from va;
-- blue_today
select split_part(blue_today, ':', 1) status, count(*) n from va group by 1 order by 2 desc;
select wave, split_part(blue_today, ':', 1) status, count(*) n from va group by 1,2 order by 1,3 desc;
-- verbs used in >=3 spaces whose positional arity differs
select verb, count(distinct space) spaces, string_agg(distinct cast(arity as varchar), '/' order by cast(arity as varchar)) arities,
       count(distinct arity) n_arities
from va group by 1 having count(distinct space)>=3 and count(distinct arity)>1 order by spaces desc limit 30;
select 'shared verbs (>=3 spaces)' k, count(*) from (select verb from va group by 1 having count(distinct space)>=3)
union all select 'of which arity-consistent', count(*) from (select verb from va group by 1 having count(distinct space)>=3 and count(distinct arity)=1);
-- laterals
select lat, count(*) verbs from (select unnest(string_split(laterals, ',')) lat from va where laterals<>'' and laterals<>'-') group by 1 order by 2 desc;
