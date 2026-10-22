.read docs/verbs/merge.sql
.mode box
create or replace table ve as select *, space||'::'||verb k from v;
create or replace table ed as
 select split_part("from",'::',1) fs, split_part("to",'::',1) ts, rel, "from", "to" from e
 where rel in ('composes','requires') and split_part("from",'::',1) <> split_part("to",'::',1) and "to" not like 'core::%';
select ts space, count(distinct fs) dependent_spaces, count(*) edges,
  (select count(*) from ve where ve.space=ed.ts) verbs,
  (select count(*) from ve where ve.space=ed.ts and split_part(blue_today,':',1)='exists') exist_today,
  (select string_agg(distinct region, ',') from ve where ve.space=ed.ts) regions
from ed group by ts order by dependent_spaces desc, edges desc limit 28;
select 'spaces by wave<=1 absent' k;
select space, count(*) filter (where wave in ('0','1') and split_part(blue_today,':',1)<>'exists') build_w01, count(*) filter (where split_part(blue_today,':',1)='exists') exist, count(*) total
from ve group by 1 order by build_w01 desc limit 22;
