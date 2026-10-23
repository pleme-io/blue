create or replace table gv as
  select * from read_csv('docs/verbs/merged/verbs.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table ge as
  select * from read_csv('docs/verbs/merged/edges.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table gc as
  select * from read_csv('docs/verbs/contracts.tsv', delim='\t', header=true, quote='', escape='', all_varchar=true);
create or replace table gb as
  select split_part(file, '/', 2) as name from glob('bidamas/*/Bluefile');

create or replace macro npos(s) as
  len(list_filter(
    list_transform(
      string_split(regexp_replace(regexp_extract(split_part(s, ' -> ', 1), '\((.*)\)$', 1), '\{[^}]*\}', '{}', 'g'), ','),
      x -> trim(x)),
    x -> x <> '' and x <> 'opts' and x <> '{}'));

create or replace table gk as select space || '::' || verb as k from gv;

create or replace table gcl as
select verb,
  len(list_filter(list_transform(string_split(coalesce(args, ''), ','), x -> trim(x)), x -> x <> '')) as hi,
  len(list_filter(list_transform(string_split(coalesce(args, ''), ','), x -> trim(x)), x -> x <> '' and not (x like '~%' or x like '%?'))) as lo,
  opts
from gc;

create or replace table gdeg as
select k, count(*) as d from (select "from" as k from ge union all select "to" from ge) group by k;

select defect, detail from (
  select 'duplicate key' as defect, space || '::' || verb as detail from gv group by space, verb having count(*) > 1
  union all
  select 'composes cycle', root from (
    with recursive c(root, cur, depth) as (
      select "from", "to", 1 from ge where rel = 'composes'
      union all
      select c.root, ge."to", c.depth + 1 from c join ge on ge."from" = c.cur and ge.rel = 'composes'
      where c.depth < 12 and c.cur <> c.root)
    select distinct root from c where cur = root)
  union all
  select 'dangling endpoint', e.endpoint from (
    select "from" as endpoint from ge union select "to" from ge) e
  where e.endpoint not in (select k from gk)
  union all
  select 'duplicate edge', "from" || ' ' || rel || ' ' || "to" from ge group by "from", rel, "to" having count(*) > 1
  union all
  select 'inverse without reverse', a."from" || ' inverse ' || a."to" from ge a
  where a.rel = 'inverse'
    and not exists (select 1 from ge b where b.rel = 'inverse' and b."from" = a."to" and b."to" = a."from")
  union all
  select 'verb without an edge', k from gk where k not in (select k from gdeg)
  union all
  select 'self edge', "from" from ge where "from" = "to"
  union all
  select 'unknown relation', rel || ' ' || "from" from ge
  where rel not in ('inverse', 'composes', 'refines', 'generalizes', 'requires', 'lifts', 'guards', 'pairs')
  union all
  select 'shape names another verb', space || '::' || verb from gv where split_part(shape, '(', 1) <> verb
  union all
  select 'contract shape on a verb without a contract', space || '::' || verb from gv
  where contract_shape <> '' and verb not in (select verb from gc)
  union all
  select 'verb with a contract lacks a contract shape', space || '::' || verb from gv
  where contract_shape = '' and verb in (select verb from gc)
  union all
  select 'contract shape arity outside the contract', v.space || '::' || v.verb || ' ' || v.contract_shape
  from gv v join gcl c on c.verb = v.verb
  where v.contract_shape <> '' and (npos(v.contract_shape) < c.lo or npos(v.contract_shape) > c.hi)
  union all
  select 'contract shape names another verb', space || '::' || verb from gv
  where contract_shape <> '' and split_part(contract_shape, '(', 1) <> verb
  union all
  select 'conforms disagrees with the shape', v.space || '::' || v.verb || ' ' || v.shape
  from gv v join gcl c on c.verb = v.verb
  where v.conforms <> (case when npos(v.shape) >= c.lo and npos(v.shape) <= c.hi
                             and (c.opts = 'yes' or not (list_contains(list_transform(string_split(regexp_extract(split_part(v.shape, ' -> ', 1), '\((.*)\)$', 1), ','), x -> trim(x)), 'opts')
                                                        or regexp_matches(split_part(v.shape, ' -> ', 1), '\{[^}]*\}')))
                            then 'yes' else 'no' end)
  union all
  select 'conforms set without a contract', space || '::' || verb from gv
  where (verb not in (select verb from gc) and conforms <> 'na') or (verb in (select verb from gc) and conforms = 'na')
  union all
  select 'blue_today outside the closed set', space || '::' || verb || ' ' || blue_today from gv
  where not (blue_today = 'absent'
    or (split_part(blue_today, ':', 1) in ('exists', 'partial') and split_part(blue_today, ':', 2) in (select name from gb))
    or regexp_matches(blue_today, '^rust:[a-z0-9-]+$'))
  union all
  select 'lateral outside the closed set', v.space || '::' || v.verb || ' ' || l.lat from (
    select space, verb, unnest(string_split(laterals, ',')) as lat from gv) l
  join gv v on v.space = l.space and v.verb = l.verb
  where l.lat not in ('error', 'retry', 'deadline', 'cancel', 'log', 'trace', 'config', 'validate', 'serialize', 'time',
                      'resource', 'process', 'cache', 'idempotent', 'capability', 'test', 'migrate', 'ratelimit', 'switch', '-')
  union all
  select 'wave outside 0 to 4', space || '::' || verb from gv where wave not in ('0', '1', '2', '3', '4')
  union all
  select 'shared verb without a contract', verb from gv group by verb
  having count(distinct space) >= 3 and verb not in (select verb from gc)
  union all
  select 'duplicate contract', verb from gc group by verb having count(*) > 1
  union all
  select 'contract status outside the closed set', verb from gc where status not in ('stdlib', 'decided', 'open')
  union all
  select 'more than 12 open contracts', cast(count(*) as varchar) from gc where status = 'open' having count(*) > 12
  union all
  select 'contract kind outside the closed set', verb from gc where kind not in ('pure', 'effect', 'stream', 'decl', 'any')
);
