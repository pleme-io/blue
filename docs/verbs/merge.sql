create or replace table v as
  select * from read_csv(['docs/verbs/A/verbs.tsv','docs/verbs/B/verbs.tsv','docs/verbs/C/verbs.tsv','docs/verbs/D/verbs.tsv','docs/verbs/E/verbs.tsv','docs/verbs/F/verbs.tsv','docs/verbs/G/verbs.tsv'],
    delim='\t', header=true, quote='', escape='', all_varchar=true, union_by_name=true, ignore_errors=false);
create or replace table e as
  select * from read_csv(['docs/verbs/A/edges.tsv','docs/verbs/B/edges.tsv','docs/verbs/C/edges.tsv','docs/verbs/D/edges.tsv','docs/verbs/E/edges.tsv','docs/verbs/F/edges.tsv','docs/verbs/G/edges.tsv'],
    delim='\t', header=true, quote='', escape='', all_varchar=true, union_by_name=true, ignore_errors=false);
select 'verbs' k, count(*) n from v union all select 'edges', count(*) from e
union all select 'spaces', count(distinct space) from v
union all select 'distinct space::verb', count(distinct space||'::'||verb) from v;
select region, count(*) verbs, count(distinct space) spaces, round(count(*)*1.0/count(distinct space),1) per_space from v group by 1 order by 1;
select wave, count(*) n from v group by 1 order by 1;
select kind, count(*) n from v group by 1 order by 2 desc;
