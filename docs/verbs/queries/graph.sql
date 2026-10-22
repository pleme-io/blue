.read docs/verbs/merge.sql
.mode box
create or replace table keys as select distinct space||'::'||verb k from v;
select rel, count(*) n from e group by 1 order by 2 desc;
select 'edges total' k, count(*) n from e
union all select 'from not a verb row', count(*) from e where "from" not in (select k from keys)
union all select 'to not a verb row', count(*) from e where "to" not in (select k from keys)
union all select 'to core:: (master verb)', count(*) from e where "to" like 'core::%'
union all select 'self edges', count(*) from e where "from"="to"
union all select 'duplicate edges', count(*) from (select "from",rel,"to" from e group by all having count(*)>1);
create or replace table deg as
select k, count(*) d from (select "from" k from e union all select "to" from e) group by 1;
select k, d from deg order by d desc limit 15;
select 'verbs with no edge' k, count(*) n from keys where k not in (select k from deg);
-- longest composes chain (recursive, bounded)
with recursive c(root, cur, depth) as (
  select "from", "to", 1 from e where rel='composes' and "from" in (select k from keys)
  union all
  select c.root, e."to", c.depth+1 from c join e on e."from"=c.cur and e.rel='composes' where c.depth < 12)
select max(depth) longest_composes_chain from c;
-- cycles in composes
with recursive c(root, cur, depth) as (
  select "from", "to", 1 from e where rel='composes'
  union all
  select c.root, e."to", c.depth+1 from c join e on e."from"=c.cur and e.rel='composes' where c.depth < 12 and c.cur<>c.root)
select count(*) composes_cycles from c where cur=root;
-- inverse symmetry
select 'inverse edges' k, count(*) n from e where rel='inverse'
union all select 'inverse without the reverse', count(*) from e a where rel='inverse' and not exists (select 1 from e b where b.rel='inverse' and b."from"=a."to" and b."to"=a."from");
