create or replace table gv as
  select * from read_csv(getvariable('vdir') || '/verbs.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table ge as
  select * from read_csv(getvariable('vdir') || '/edges.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table gc as
  select * from read_csv(getvariable('vdir') || '/contracts.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);

create or replace macro meaning_key(s) as array_to_string(
  list_filter(regexp_split_to_array(lower(s), '[^a-z0-9]+'),
    lambda x: x <> '' and not list_contains(['a','an','the','of','to','in','on','by','for','and','or','with','as','from','into','at','its','is','it','that'], x)),
  ' ');

create or replace table gk as
  select space || '::' || verb as k, space, cast(wave as integer) as wave, meaning from gv;

create or replace table g_found(kind varchar, subject varchar);

insert into g_found
select 'g1-meaning', a.k || ' ' || b.k
from gk a join gk b on a.space = b.space and a.k < b.k
 and meaning_key(a.meaning) = meaning_key(b.meaning) and meaning_key(a.meaning) <> ''
where not exists (
  select 1 from ge e
  where e.rel in ('refines', 'generalizes', 'inverse')
    and ((e."from" = a.k and e."to" = b.k) or (e."from" = b.k and e."to" = a.k)));

insert into g_found
select 'g2-vocab', space || '::' || verb from gv where verb not in (select verb from gc);

insert into g_found
with recursive r(a, b) as (
  select "from", "to" from ge where rel in ('composes', 'requires')
  union
  select r.a, e."to" from r join ge e on e."from" = r.b and e.rel in ('composes', 'requires'))
select 'g4-cycle', a from r where a = b;

insert into g_found
select 'g4-wave', e."from" || ' -> ' || e."to"
from ge e join gk f on f.k = e."from" join gk t on t.k = e."to"
where e.rel in ('composes', 'requires') and t.wave > f.wave;

insert into g_found
with p as (
  select distinct least("from", "to") as x, greatest("from", "to") as y from ge where rel = 'inverse'),
 q as (select x as v, y as w from p union all select y, x from p)
select 'g7-inverse', v from q group by v having count(distinct w) > 1;

insert into g_found
select 'g9-dangling', e from (select "from" as e from ge union select "to" from ge)
where e not in (select k from gk);

insert into g_found
select 'g9-relation', "from" || ' ' || rel || ' ' || "to" from ge
where rel not in ('inverse', 'composes', 'refines', 'generalizes', 'requires', 'lifts', 'guards', 'pairs');

select kind || chr(9) || subject from g_found order by 1;
