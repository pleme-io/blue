.read docs/verbs/merge.sql
.mode list
create or replace table keys as select distinct space||'::'||verb k from v;
select 'CYCLE ROOTS';
with recursive c(root, cur, depth, path) as (
  select "from", "to", 1, "from"||' > '||"to" from e where rel='composes'
  union all
  select c.root, e."to", c.depth+1, c.path||' > '||e."to" from c join e on e."from"=c.cur and e.rel='composes'
   where c.depth < 8 and c.cur<>c.root)
select distinct path from c where cur=root order by length(path) limit 14;
select 'DANGLING (not core::)';
select distinct "to" from e where "to" not in (select k from keys) and "to" not like 'core::%' order by 1;
select 'DUPLICATE EDGES';
select "from"||' '||rel||' '||"to"||' x'||count(*) from e group by "from",rel,"to" having count(*)>1 order by 1 limit 8;
select 'CORE VERBS REFERENCED';
select "to", count(*) n from e where "to" like 'core::%' group by 1 order by 2 desc limit 30;
