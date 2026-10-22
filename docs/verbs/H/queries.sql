-- Run: duckdb -init queries.sql   (or: duckdb < queries.sql). Loads the region TSVs unchanged.
-- Real corpus: replace the two paths with  'region*/verbs.tsv'  and  'region*/edges.tsv'.

CREATE OR REPLACE VIEW verbs AS
SELECT *, space || '::' || verb AS id,
       regexp_extract(shape, '\((.*)\) *->', 1) AS params,
       trim(regexp_extract(shape, '->(.*)$', 1)) AS ret,
       length(regexp_extract(shape, '\((.*)\) *->', 1))
         - length(replace(regexp_extract(shape, '\((.*)\) *->', 1), ',', ''))
         + (regexp_extract(shape, '\((.*)\) *->', 1) <> '')::INT AS nparams,
       regexp_matches(shape, ', *opts\) *->') AS has_opts
FROM read_csv('verbs.tsv', delim='\t', quote='', header=true, all_varchar=true);

CREATE OR REPLACE VIEW edges AS
SELECT * FROM read_csv('edges.tsv', delim='\t', quote='', header=true, all_varchar=true);

-- the closed lateral list (BRIEF) and relation list, in blue these are `lateral(...)` rows
CREATE OR REPLACE VIEW laterals(name) AS VALUES ('error'),('retry'),('deadline'),('cancel'),('log'),
  ('trace'),('config'),('validate'),('serialize'),('time'),('resource'),('process'),('cache'),
  ('idempotent'),('capability'),('test'),('migrate'),('ratelimit'),('switch');
CREATE OR REPLACE VIEW rels(rel) AS VALUES ('inverse'),('composes'),('refines'),('generalizes'),
  ('requires'),('lifts'),('guards'),('pairs');
-- return tokens grouped into the class a verb's shape may vary within
CREATE OR REPLACE VIEW retclass(ret, class) AS VALUES ('text','content'),('bytes','content'),
  ('value','content'),('record','content'),('content','content'),('list','list'),('nil','nil'),
  ('bool','bool'),('stream','stream'),('handle','handle');

-- G0 vocabulary integrity: each query below must return ZERO rows to be green.
-- G0a duplicate id, G0b bad kind/wave/blue_today, G0c lateral outside the closed set
SELECT 'dup-id' AS gate, id FROM verbs GROUP BY id HAVING count(*) > 1
UNION ALL SELECT 'bad-field', id FROM verbs
  WHERE kind NOT IN ('pure','effect','stream','decl') OR wave NOT IN ('0','1','2','3','4')
     OR NOT regexp_matches(blue_today, '^(exists|partial):[a-z]+$|^absent$')
UNION ALL SELECT 'unknown-lateral', id FROM (
  SELECT id, unnest(string_split(laterals, ',')) AS l FROM verbs WHERE laterals <> '-')
  WHERE l NOT IN (SELECT name FROM laterals);

-- G1 short-name rule: lowercase ASCII word, optional trailing ?, no underscore past one noun
SELECT 'bad-name' AS gate, id FROM verbs WHERE NOT regexp_matches(verb, '^[a-z]+(_[a-z]+)?\??$');

-- G2 edges resolve, relation is in the closed set
SELECT 'dangling' AS gate, "from" AS a, rel, "to" AS b FROM edges
 WHERE "from" NOT IN (SELECT id FROM verbs) OR "to" NOT IN (SELECT id FROM verbs)
UNION ALL SELECT 'bad-rel', "from", rel, "to" FROM edges WHERE rel NOT IN (SELECT rel FROM rels);

-- G3 composes is acyclic (also requires): a node reaching itself
WITH RECURSIVE r(src, cur, depth) AS (
  SELECT "from", "to", 1 FROM edges WHERE rel = 'composes'
  UNION ALL SELECT r.src, e."to", depth + 1 FROM r JOIN edges e
    ON e."from" = r.cur AND e.rel = 'composes' WHERE depth < 50)
SELECT 'composes-cycle' AS gate, src FROM r WHERE src = cur GROUP BY src;

-- G4 inverse is an involution: stored once or twice, each verb has at most one partner
WITH inv AS (SELECT "from" a, "to" b FROM edges WHERE rel = 'inverse'
             UNION SELECT "to", "from" FROM edges WHERE rel = 'inverse')
SELECT 'inverse-not-functional' AS gate, a FROM inv GROUP BY a HAVING count(DISTINCT b) > 1;

-- G5 an edge between two spaces' same-named verbs is redundant (same name = same meaning),
-- except composes/requires (a layer using the layer below)
SELECT 'same-name-edge' AS gate, "from", rel, "to" FROM edges
 WHERE split_part("from",'::',2) = split_part("to",'::',2) AND rel NOT IN ('composes','requires');

-- G6 one meaning per verb: two DIFFERENT verbs in one space with the same normalised meaning
-- (ordered tokens equal after dropping stop words: direction matters, so parse/render differ), and no refines/generalizes edge excusing them.
WITH tok AS (
  SELECT id, space, verb, list_filter(
    string_split(lower(regexp_replace(meaning, '[^a-z ]', '', 'g')), ' '),
    t -> t NOT IN ('a','an','the','of','to','is','in','for','and','by','its','it','as','at','on','with','from','a')
        AND t <> '') AS bag FROM verbs)
SELECT 'duplicate-meaning' AS gate, a.id, b.id FROM tok a JOIN tok b
  ON a.space = b.space AND a.verb < b.verb AND a.bag = b.bag
WHERE NOT EXISTS (SELECT 1 FROM edges e WHERE e.rel IN ('refines','generalizes','inverse')
  AND ((e."from" = a.id AND e."to" = b.id) OR (e."from" = b.id AND e."to" = a.id)));

-- G7 verbs of one name keep one shape across spaces: arity, options-last, return class
-- (the verb-law matrix of STDLIB 5.2-5.3). Modal shape per name, a space off the mode diverges.
WITH s AS (
  SELECT v.id, v.space, v.verb, v.nparams - (v.has_opts)::INT AS npos, v.has_opts,
         coalesce(c.class, v.ret) AS rclass
  FROM verbs v LEFT JOIN retclass c ON c.ret = v.ret),
cnt AS (SELECT verb, npos, has_opts, rclass, count(*) AS n FROM s GROUP BY ALL),
modal AS (SELECT *, row_number() OVER (PARTITION BY verb ORDER BY n DESC, npos) AS rk FROM cnt)
SELECT 'shape-divergence' AS gate, s.id, s.npos, s.has_opts, s.rclass,
       m.npos AS modal_npos, m.has_opts AS modal_opts, m.rclass AS modal_ret
FROM s JOIN modal m ON m.verb = s.verb AND m.rk = 1
WHERE (s.npos, s.has_opts, s.rclass) <> (m.npos, m.has_opts, m.rclass);
-- sample result: habu::delete (3 positionals, no opts, bool) against fairu/jisho delete

-- Q1 verbs with no implementation, by wave (what to build)
SELECT wave, space, verb, meaning FROM verbs WHERE blue_today = 'absent' ORDER BY wave, space, verb;

-- Q2 spaces that diverge from the shared shape: per space, how many verbs are off the mode
-- (reuse G7 as a view in the real graph: CREATE VIEW shape_divergence AS ...)

-- Q3 hubs: most connected verbs (in + out, any relation)
SELECT id, count(*) AS degree, count(*) FILTER (WHERE d = 'in') AS in_deg
FROM (SELECT "from" AS id, 'out' AS d FROM edges UNION ALL SELECT "to", 'in' FROM edges)
GROUP BY id ORDER BY degree DESC, id LIMIT 10;

-- Q4 orphan verbs: no edge at all (the real gate requires zero)
SELECT id FROM verbs WHERE id NOT IN (SELECT "from" FROM edges UNION SELECT "to" FROM edges);

-- Q5 longest composes chains (depth = number of hops), with the path
WITH RECURSIVE c(src, cur, depth, path) AS (
  SELECT "from", "to", 1, "from" || ' > ' || "to" FROM edges WHERE rel = 'composes'
  UNION ALL SELECT c.src, e."to", depth + 1, path || ' > ' || e."to" FROM c JOIN edges e
    ON e."from" = c.cur AND e.rel = 'composes' WHERE depth < 50)
SELECT depth, path FROM c ORDER BY depth DESC, path LIMIT 5;

-- Q6 laterals by number of verbs touching them (a lateral with 0 is a battery nobody uses,
-- a verb touching a lateral that has no battery bidama is a gap)
SELECT l.name AS lateral, count(v.id) AS verbs
FROM laterals l LEFT JOIN (SELECT id, unnest(string_split(laterals, ',')) AS l FROM verbs
  WHERE laterals <> '-') v ON v.l = l.name GROUP BY l.name ORDER BY verbs DESC, l.name;

-- Q7 wave burn-down: per wave, verbs total, built (exists), partial, absent, % built
SELECT wave::INT AS wave, count(*) AS verbs,
       count(*) FILTER (WHERE blue_today LIKE 'exists:%')  AS built,
       count(*) FILTER (WHERE blue_today LIKE 'partial:%') AS partial,
       count(*) FILTER (WHERE blue_today = 'absent')       AS absent,
       round(100.0 * count(*) FILTER (WHERE blue_today LIKE 'exists:%') / count(*), 1) AS pct_built
FROM verbs GROUP BY wave ORDER BY wave::INT;

-- Q8 requires-closure: what a verb drags in (build order = reverse of this)
WITH RECURSIVE need(root, cur) AS (
  SELECT "from", "to" FROM edges WHERE rel IN ('requires','composes')
  UNION SELECT n.root, e."to" FROM need n JOIN edges e
    ON e."from" = n.cur AND e.rel IN ('requires','composes'))
SELECT root, count(*) AS closure, max(v.wave) AS latest_wave_needed
FROM need n JOIN verbs v ON v.id = n.cur GROUP BY root ORDER BY closure DESC LIMIT 5;

-- Q9 a verb whose wave is earlier than a wave of something it needs (a plan that cannot build)
SELECT e."from", v1.wave AS wave, e."to", v2.wave AS needs_wave
FROM edges e JOIN verbs v1 ON v1.id = e."from" JOIN verbs v2 ON v2.id = e."to"
WHERE e.rel IN ('composes','requires') AND v2.wave::INT > v1.wave::INT;

-- Q10 doc/law/test completeness needs the derived columns of the real graph (docs_ok, laws,
-- tests) that `blue verbs export` adds, this sample has none, so the query is the red run:
-- SELECT id FROM verbs_full WHERE blue_today LIKE 'exists:%' AND NOT (doc_ok AND laws > 0 AND tests > 0),
