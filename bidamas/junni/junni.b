@moduledoc """
junni — the pure words of blue's full-text index (the subject of the `sakuin` verb space, docs/verbs): text analyzed into tokens, documents inverted into postings, and a question's terms ranked by BM25 over them. Everything here is in memory and a function of its arguments; a stored index, a writer and its lock are later rungs of the space. arika's `find` is the first consumer (docs/ARIKA.md ruling R7).

    lookup(invert([["a", "blue words"]], {}), "words") #=> ["a"]
"""

use("moji", [:is_alnum])
use("retsu", %i[first flat_map push size])

@doc """
STOP is the words analyze drops unless its options name others: English glue that ranks every document alike.

    member?("the", STOP) #=> true
"""
STOP = %w[a an and as at by for from in is it of on or the to with]

@doc """
K1 is BM25's term-frequency saturation: how fast a repeated term stops adding to a score.

    K1 #=> 1.2
"""
K1 = 1.2

@doc """
B is BM25's length normalization: 0 ignores a document's length, 1 divides by it in full.

    B #=> 0.75
"""
B = 0.75

@doc """
flush adds the token being read to the tokens, when there is one.

    flush(["a"], "b") #=> ["a", "b"]
"""
def flush(acc, cur)
  if cur == ""
    acc
  else
    push(acc, cur)
  end
end

@doc """
split_tokens cuts lower-case text at every character that is not an ASCII letter or digit.

    split_tokens("word_shapes::first") #=> ["word", "shapes", "first"]
"""
def split_tokens(text)
  step = reduce(
    fn(st, c)
      if is_alnum(c)
        [st[0], "#{st[1]}#{c}"]
      else
        [flush(st[0], st[1]), ""]
      end
    end,
    [[], ""],
    chars(downcase(text))
  )
  flush(step[0], step[1])
end

@doc """
analyze: The index tokens of a text, in order: lower case, cut at every character that is not an ASCII letter or digit, the stop words dropped (`opts[:stop]` replaces STOP).

    analyze("The running_sum of a list", {}) #=> ["running", "sum", "list"]
"""
def analyze(text, opts)
  stop = opts[:stop] or STOP
  filter((t) -> not member?(t, stop), split_tokens(text or ""))
end

@doc """
postings_of adds one document's term counts to the postings by term.

    postings_of({}, "a", ["x", "x"]) #=> {"x" => [["a", 2]]}
"""
def postings_of(by_term, id, tokens)
  reduce(
    (m, e) -> assoc(m, e[0], push(get(m, e[0]) or [], [id, e[1]])),
    by_term,
    map_entries(frequencies(tokens))
  )
end

@doc """
invert: An in-memory inverted index of `docs`, each `[id, text]`: per term the `[id, count]` of every document holding it, per document its token count, the document count and the mean length. `opts` is analyze's.

    invert([["a", "x y"], ["b", "x"]], {})[:docs] #=> 2
"""
def invert(docs, opts)
  analyzed = map((d) -> [d[0], analyze(d[1], opts)], docs)
  lengths = reduce((m, d) -> assoc(m, d[0], size(d[1])), {}, analyzed)
  total = reduce((n, d) -> n + size(d[1]), 0, analyzed)
  n = size(analyzed)
  {
    terms: reduce((m, d) -> postings_of(m, d[0], d[1]), {}, analyzed),
    lengths:,
    docs: n,
    mean: if n == 0
      0.0
    else
      total / (n * 1.0)
    end,
    opts:
  }
end

@doc """
lookup: The ids of the documents that hold `term`, after analysis, in the order they were inverted; [] for a term no document holds.

    lookup(invert([["a", "Blue"], ["b", "red"]], {}), "BLUE") #=> ["a"]
"""
def lookup(postings, term)
  t = first(analyze(term, postings[:opts]))
  if t.nil?
    []
  else
    map(first, get(postings[:terms], t) or [])
  end
end

@doc """
idf is BM25's inverse document frequency of a term held by `df` of `n` documents; never negative.

    idf(1, 1) > 0 #=> true
"""
def idf(df, n)
  log((n - df + 0.5) / (df + 0.5) + 1.0)
end

@doc """
term_score is one posting's BM25 contribution: its count, its document's length against the mean, and the term's idf.

    term_score(1, 2, 2.0, 1.0) #=> 1.0
"""
def term_score(tf, len, mean, w)
  norm = if mean == 0
    1.0
  else
    1.0 - B + B * len / mean
  end
  w * tf * (K1 + 1.0) / (tf + K1 * norm)
end

@doc """
scores_of adds one query term's contributions to the scores by id.

    get(scores_of({}, invert([["a", "x"]], {}), "x"), "a") > 0 #=> true
"""
def scores_of(acc, postings, term)
  held = get(postings[:terms], term) or []
  w = idf(size(held), postings[:docs])
  reduce(
    fn(m, p)
      assoc(
        m,
        p[0],
        (get(m, p[0]) or 0.0) +
          term_score(p[1], get(postings[:lengths], p[0]), postings[:mean], w)
      )
    end,
    acc,
    held
  )
end

@doc """
score: The documents that hold any of `terms` (each analyzed), ranked by BM25 (K1, B): `[{id, score}]`, highest first, ties by id; `opts[:limit]` keeps the first that many.

    map((h) -> h[:id], score(invert([["a", "x y"], ["b", "x x"]], {}), ["x"], {})) #=> ["b", "a"]
"""
def score(postings, terms, opts)
  wanted = distinct(flat_map(terms, (t) -> analyze(t, postings[:opts])))
  totals = reduce((m, t) -> scores_of(m, postings, t), {}, wanted)
  hits = map((e) -> {id: e[0], score: e[1]}, map_entries(totals))
  ranked = sort_keyed((h) -> 0.0 - h[:score], sort_keyed((h) -> h[:id], hits))
  if opts[:limit].nil?
    ranked
  else
    take(opts[:limit], ranked)
  end
end

test "a token is a run of letters and digits; stop words go unless the options say otherwise"
  assert analyze("Read a file, line by line!", {}) == %w[read file line line]
  assert analyze("a b", {stop: []}) == %w[a b]
  assert analyze(nil, {}) == []
end

test "the postings count each term per document and keep every length"
  p = invert([["a", "x y x"], %w[b y]], {})
  assert p[:terms]["x"] == [["a", 2]]
  assert p[:terms]["y"] == [["a", 1], ["b", 1]]
  assert p[:lengths] == {"a" => 3, "b" => 1}
  assert p[:mean] == 2.0
end

test "a rarer term outranks a common one, and a shorter document a longer one"
  p = invert(
    [
      ["long", "sum of a list and more words here"],
      %w[short sum],
      %w[other list]
    ],
    {}
  )
  ids = map((h) -> h[:id], score(p, ["sum"], {}))
  assert ids == %w[short long]
  both = score(p, %w[sum list], {})
  assert first(both)[:id] == "long"
  assert size(score(p, ["absent"], {})) == 0
end

test "ties are ordered by id and a limit keeps the first hits"
  p = invert([%w[b x], %w[a x], %w[c x]], {})
  assert map((h) -> h[:id], score(p, ["x"], {})) == %w[a b c]
  assert map((h) -> h[:id], score(p, ["x"], {limit: 2})) == %w[a b]
end

test "an empty index answers nothing and divides by nothing"
  p = invert([], {})
  assert p[:docs] == 0
  assert score(p, ["x"], {}) == []
  assert lookup(p, "x") == []
end
