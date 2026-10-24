@moduledoc """
chokkan (直感) — System One judgment: typed questions in, calibrated answers out.

    margin([]) #=> 0
"""

use("deeta", [:as_json, :get_number, :get_str, :is_doc])
use("kyohi", [:enforce, :kinds, :refusal])
use("moji", [:drop_chars, :is_blank])
use("retsu", [:first, :flat_map, :is_empty, :last, :size])

def noul(instructions)
  {type: "noul", instructions:}
end

@doc """
choice: a question with a closed set of answers.
"""
def choice(instructions, options)
  {type: "choice", instructions:, options:}
end

@doc """
score: grade an output: exact, pattern, similarity or judge.
"""
def score(instructions, levels)
  {type: "score", instructions:, levels:}
end

@doc """
ask: one call to a model; reply holds text, tool uses, usage.
"""
def ask(name, question)
  [name, question]
end

def names_of(pairs)
  map((p) -> first(p), pairs)
end

def repeats(xs)
  size(xs) != size(distinct(xs))
end

def question_problems(nq)
  name = first(nq)
  q = last(nq)
  t = get(q, :type)
  blank = if is_blank(to_s(get(q, :instructions)))
    [refusal(:empty_instructions, "#{name}: a question needs instructions")]
  else
    []
  end
  append(blank, shape_problems(name, t, q))
end

def shape_problems(name, t, q)
  if t == "noul"
    []
  elsif t == "choice"
    option_problems(name, get(q, :options))
  elsif t == "score"
    level_problems(name, get(q, :levels))
  else
    [refusal(:unknown_type, "#{name}: no question type #{to_s(t)}")]
  end
end

def option_problems(name, options)
  n = size(options)
  range_err = if n < 1 or n > 255
    [
      refusal(
        :options_out_of_range,
        "#{name}: #{to_s(n)} options, 1 to 255 allowed"
      )
    ]
  else
    []
  end
  dup_err = if repeats(names_of(options))
    [refusal(:duplicate_option, "#{name}: an option is named twice")]
  else
    []
  end
  append(range_err, dup_err)
end

def level_problems(name, levels)
  n = size(levels)
  if n < 2 or n > 10
    [
      refusal(
        :levels_out_of_range,
        "#{name}: #{to_s(n)} levels, 2 to 10 allowed"
      )
    ]
  else
    []
  end
end

def problems(questions)
  if is_empty(questions)
    [refusal(:no_questions, "a request needs at least one question")]
  else
    dup_err = if repeats(names_of(questions))
      [refusal(:duplicate_question, "a question is named twice")]
    else
      []
    end
    append(dup_err, flat_map(questions, question_problems))
  end
end

def criteria_of(q)
  t = get(q, :type)
  if t == "choice"
    reduce((acc, o) -> assoc(acc, first(o), last(o)), {}, get(q, :options))
  elsif t == "score"
    get(q, :levels)
  end
end

def wire(q)
  c = criteria_of(q)
  base = {type: get(q, :type), instructions: get(q, :instructions)}
  if c.nil?
    base
  else
    assoc(base, :criteria, c)
  end
end

@doc """
request: the wire request that carries the questions.
"""
def request(model, state, questions)
  enforce(questions, [problems], {kind: :first})
  wired = reduce(
    (acc, nq) -> assoc(acc, first(nq), wire(last(nq))),
    {},
    questions
  )
  json_stringify({model:, state:, questions: wired})
end

def keep_tail(text, max_chars)
  n = length(text)
  if n <= max_chars
    text
  else
    drop_chars(text, n - max_chars)
  end
end

def parsed(body)
  if body.nil?
    nil
  else
    json_parse(body) rescue nil
  end
end

@doc """
read: The whole content of a source, by the source's space: in_space("gitto", repo) reads a file at a ref. Raises :usage when no space owns the subject or the space has no handler.
"""
def read(status, body)
  if status == 200
    doc = parsed(body)
    if is_doc(doc) and is_doc(as_json(doc, "answers"))
      {
        kind: :answered,
        answers: as_json(doc, "answers"),
        model: get_str(doc, "model", "")
      }
    else
      {kind: :blind, why: "the judge answered 200 without answers"}
    end
  elsif status == 400 or status == 404 or status == 422
    {kind: :refused, why: "the judge refused the request (#{to_s(status)})"}
  else
    {kind: :blind, why: "the judge could not answer (#{to_s(status)})"}
  end
end

def answer(reading, name)
  if get(reading, :kind) == :answered
    as_json(get(reading, :answers), name)
  end
end

def number_of(reading, name, key)
  a = answer(reading, name)
  if is_doc(a)
    get_number(a, key, nil)
  end
end

def chosen(reading, name)
  a = answer(reading, name)
  if is_doc(a)
    get_str(a, "choice", nil)
  end
end

def confidence(reading, name)
  number_of(reading, name, "confidence")
end

def probability(reading, name)
  number_of(reading, name, "noul")
end

def score_of(reading, name)
  number_of(reading, name, "score")
end

def probabilities(reading, name)
  a = answer(reading, name)
  if is_doc(a) and as_json(a, "probabilities") != nil
    as_json(a, "probabilities")
  else
    []
  end
end

def expected_level(probs)
  reduce((acc, p) -> acc + to_int(first(p)) * last(p), 0, probs)
end

def margin(probs)
  ps = reverse(sort_keyed((p) -> last(p), probs))
  if is_empty(ps)
    0
  elsif size(ps) == 1
    last(first(ps))
  else
    last(first(ps)) - last(nth(1, ps))
  end
end

def confident(reading, name, min)
  c = confidence(reading, name)
  c != nil and c >= min
end

def example_body()
  "{\"model\":\"jev-1.13.0\",\"answers\":{\"is_refund\":{\"type\":\"noul\",\"noul\":0.99},\"route\":{\"type\":\"choice\",\"choice\":\"cid\",\"probabilities\":{\"cid\":0.75,\"opus\":0.25},\"confidence\":0.85},\"difficulty\":{\"type\":\"score\",\"score\":2.5,\"legend\":{\"1\":\"easy\",\"2\":\"middling\",\"3\":\"hard\"},\"probabilities\":{\"1\":0.25,\"2\":0.0,\"3\":0.75},\"confidence\":0.82}},\"usage\":{\"input_tokens\":279,\"output_tokens\":22}}"
end

def example_questions()
  [
    ask("is_refund", noul("Is the customer asking for a refund?")),
    ask("route", choice("Which model?", [["cid", "local"], ["opus", "deep"]])),
    ask("difficulty", score("How hard?", ["easy", "middling", "hard"]))
  ]
end

test "a request with nothing to ask is refused, and an empty answer is blind"
  assert kinds(problems([])) == [:no_questions]
  empty = begin
    request("jev-latest", "s", [])
  rescue e
    e
  end
  assert empty.kind == :no_questions
  assert error?(
    begin
      request("jev-latest", "s", [])
    rescue e
      e
    end
  ) == true
  assert get(read(200, "{}"), :kind) == :blind
  assert get(read(200, "not json"), :kind) == :blind
  assert get(read(200, nil), :kind) == :blind
end

test "a request carries every question's name, type and criteria"
  doc = json_parse(request("jev-latest", "state", example_questions))
  qs = json_get(doc, "questions")
  assert json_get(doc, "model") == "jev-latest"
  assert json_get(doc, "state") == "state"
  assert json_get(json_get(qs, "is_refund"), "type") == "noul"
  assert json_get(json_get(qs, "is_refund"), "criteria").nil?
  assert json_get(json_get(json_get(qs, "route"), "criteria"), "opus") == "deep"
  assert json_get(json_get(qs, "difficulty"), "criteria") ==
    ["easy", "middling", "hard"]
end

test "option and level counts are bounded exactly at their limits"
  many = (n) -> map((i) -> [to_s(i), "d"], range(0, n))
  assert problems([ask("c", choice("pick", many(255)))]) == []
  assert kinds(problems([ask("c", choice("pick", many(256)))])) ==
    [:options_out_of_range]
  assert kinds(problems([ask("c", choice("pick", []))])) ==
    [:options_out_of_range]
  assert kinds(problems([ask("s", score("rate", ["a"]))])) ==
    [:levels_out_of_range]
  assert problems([ask("s", score("rate", ["a", "b"]))]) == []
  assert problems(
    [ask("s", score("rate", map((i) -> to_s(i), range(0, 10))))]
  ) == []
  assert kinds(
    problems([ask("s", score("rate", map((i) -> to_s(i), range(0, 11))))])
  ) == [:levels_out_of_range]
end

test "every problem is named at once, not only the first"
  qs = [
    ask("a", noul("")),
    ask("a", choice("x", [["o", "1"], ["o", "2"]])),
    ask("b", {type: "vote", instructions: "x"})
  ]
  assert kinds(problems(qs)) ==
    [:duplicate_question, :empty_instructions, :duplicate_option, :unknown_type]
  thrown = begin
    request("jev-latest", "s", qs)
  rescue e
    e
  end
  assert thrown.kind == :duplicate_question
  assert thrown.message == join(map(kyohi::why, problems(qs)), "; ")
end

test "an answered body reads as typed answers"
  r = read(200, example_body)
  assert get(r, :kind) == :answered
  assert get(r, :model) == "jev-1.13.0"
  assert probability(r, "is_refund") == 0.99
  assert chosen(r, "route") == "cid"
  assert confidence(r, "route") == 0.85
  assert score_of(r, "difficulty") == 2.5
  assert expected_level(probabilities(r, "difficulty")) == 2.5
  assert margin(probabilities(r, "route")) == 0.5
  assert confident(r, "route", 0.8) == true
  assert confident(r, "route", 0.9) == false
  assert chosen(r, "absent").nil?
  assert probabilities(r, "absent") == []
end

test "values anyone can check: an expectation and a margin"
  assert expected_level([["1", 0.5], ["3", 0.5]]) == 2.0
  assert margin([["a", 0.75], ["b", 0.25]]) == 0.5
  assert margin([["a", 0.25], ["b", 0.75]]) == 0.5
  assert margin([["only", 0.5]]) == 0.5
  assert margin([]) == 0
end

test "a refusal and a failure are told apart, and neither answers"
  assert get(read(400, "{}"), :kind) == :refused
  assert get(read(404, ""), :kind) == :refused
  assert get(read(401, ""), :kind) == :blind
  assert get(read(429, ""), :kind) == :blind
  assert get(read(503, ""), :kind) == :blind
  assert get(read(0, nil), :kind) == :blind
  assert chosen(read(429, example_body), "route").nil?
  assert confident(read(429, example_body), "route", 0) == false
end

test "keep_tail keeps the newest characters"
  assert keep_tail("abcdef", 3) == "def"
  assert keep_tail("abc", 10) == "abc"
  assert keep_tail("", 3) == ""
end
