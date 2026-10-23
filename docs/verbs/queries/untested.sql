create or replace table uv as
select * from read_csv(getenv('VERBS_TSV'), delim='\t', header=true, quote='', escape='', all_varchar=true);

create or replace table usrc as
select split_part(filename, '/', -2) as pkg, content from read_text('bidamas/*/*.b');

create or replace table uprefix as
select pkg, any_value(p) as prefix from (
  select pkg, regexp_extract(content, '(?m)^legacy_names\("[^"]*", "([^"]*)"\)', 1) as p from usrc
) where p <> '' group by pkg;

create or replace table ublocks as
select pkg, unnest(regexp_extract_all(chr(10) || content, '\ntest "[^\n]*\n(?s:.*?)\nend', 0)) as body from usrc;

create or replace table utokens as
select distinct pkg, unnest(regexp_extract_all(regexp_replace(regexp_replace(body, '"[^"\n]*"', '', 'g'), '#[^\n]*', '', 'g'), '[A-Za-z0-9_?!]+(::[A-Za-z0-9_?!]+)?', 0)) as tok from ublocks;

create or replace table uexists as
select space, verb, space || '::' || verb as node, p.prefix from uv left join uprefix p on p.pkg = uv.space
where blue_today like 'exists%' and space not like '%?';

select 'g11-untested' || chr(9) || node from uexists e
where not exists (select 1 from utokens t where t.pkg = e.space and (t.tok = e.verb or t.tok = e.prefix || '_' || e.verb))
  and not exists (select 1 from utokens t where t.tok = e.node)
order by node;
