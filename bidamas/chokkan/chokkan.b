use("deeta", [:as_json, :get_number, :get_str, :is_doc])
use("kyohi", [:kinds, :refusal, :refuse])
use("moji", [:drop_chars, :is_blank])
use("retsu", [:first, :flat_map, :is_empty, :last, :size])

# chokkan (直感) — System One judgment: typed questions in, calibrated answers out.

def noul(instructions)
  {type: "noul", instructions: instructions}
end

def choice(instructions, options)
  {type: "choice", instructions: instructions, options: options}
end

def score(instructions, levels)
  {type: "score", instructions: instructions, levels: levels}
end

def ask(name, question)
  [name, question]
end

def names_of(pairs)
  map(fn(p) first(p) end, pairs)
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
  range_err = if n < 1 || n > 255
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
  if n < 2 || n > 10
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
    append(dup_err, flat_map(fn(nq) question_problems(nq) end, questions))
  end
end

def criteria_of(q)
  t = get(q, :type)
  if t == "choice"
    reduce(fn(acc, o) assoc(acc, first(o), last(o)) end, {}, get(q, :options))
  elsif t == "score"
    get(q, :levels)
  else
    nil
  end
end

def wire(q)
  c = criteria_of(q)
  base = {type: get(q, :type), instructions: get(q, :instructions)}
  if c == nil
    base
  else
    assoc(base, :criteria, c)
  end
end

def request(model, state, questions)
  refuse(problems(questions))
  wired = reduce(
    fn(acc, nq) assoc(acc, first(nq), wire(last(nq))) end,
    {},
    questions
  )
  json_stringify({model: model, state: state, questions: wired})
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
  if body == nil
    nil
  else
    try(json_parse(body), catch(_e(), nil))
  end
end

def read(status, body)
  if status == 200
    doc = parsed(body)
    if is_doc(doc) && is_doc(as_json(doc, "answers"))
      {
        kind: :answered,
        answers: as_json(doc, "answers"),
        model: get_str(doc, "model", "")
      }
    else
      {kind: :blind, why: "the judge answered 200 without answers"}
    end
  elsif status == 400 || status == 404 || status == 422
    {kind: :refused, why: "the judge refused the request (#{to_s(status)})"}
  else
    {kind: :blind, why: "the judge could not answer (#{to_s(status)})"}
  end
end

def answer(reading, name)
  if get(reading, :kind) == :answered
    as_json(get(reading, :answers), name)
  else
    nil
  end
end

def number_of(reading, name, key)
  a = answer(reading, name)
  if is_doc(a)
    get_number(a, key, nil)
  else
    nil
  end
end

def chosen(reading, name)
  a = answer(reading, name)
  if is_doc(a)
    get_str(a, "choice", nil)
  else
    nil
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
  if is_doc(a) && as_json(a, "probabilities") != nil
    as_json(a, "probabilities")
  else
    []
  end
end

def expected_level(probs)
  reduce(fn(acc, p) acc + to_int(first(p)) * last(p) end, 0, probs)
end

def margin(probs)
  ps = reverse(sort_keyed(fn(p) last(p) end, probs))
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
  c != nil && c >= min
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
  assert error?(try(request("jev-latest", "s", []), catch(e(), e))) == true
  assert get(read(200, "{}"), :kind) == :blind
  assert get(read(200, "not json"), :kind) == :blind
  assert get(read(200, nil), :kind) == :blind
end

test "a request carries every question's name, type and criteria"
  doc = json_parse(request("jev-latest", "state", example_questions()))
  qs = json_get(doc, "questions")
  assert json_get(doc, "model") == "jev-latest"
  assert json_get(doc, "state") == "state"
  assert json_get(json_get(qs, "is_refund"), "type") == "noul"
  assert json_get(json_get(qs, "is_refund"), "criteria") == nil
  assert json_get(json_get(json_get(qs, "route"), "criteria"), "opus") == "deep"
  assert json_get(json_get(qs, "difficulty"), "criteria") ==
    ["easy", "middling", "hard"]
end

test "option and level counts are bounded exactly at their limits"
  many = fn(n) map(fn(i) [to_s(i), "d"] end, range(0, n)) end
  assert problems([ask("c", choice("pick", many(255)))]) == []
  assert kinds(problems([ask("c", choice("pick", many(256)))])) ==
    [:options_out_of_range]
  assert kinds(problems([ask("c", choice("pick", []))])) ==
    [:options_out_of_range]
  assert kinds(problems([ask("s", score("rate", ["a"]))])) ==
    [:levels_out_of_range]
  assert problems([ask("s", score("rate", ["a", "b"]))]) == []
  assert problems(
    [ask("s", score("rate", map(fn(i) to_s(i) end, range(0, 10))))]
  ) ==
    []
  assert kinds(
    problems([ask("s", score("rate", map(fn(i) to_s(i) end, range(0, 11))))])
  ) ==
    [:levels_out_of_range]
end

test "every problem is named at once, not only the first"
  qs = [
    ask("a", noul("")),
    ask("a", choice("x", [["o", "1"], ["o", "2"]])),
    ask("b", {type: "vote", instructions: "x"})
  ]
  assert kinds(problems(qs)) ==
    [:duplicate_question, :empty_instructions, :duplicate_option, :unknown_type]
end

test "an answered body reads as typed answers"
  r = read(200, example_body())
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
  assert chosen(r, "absent") == nil
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
  assert chosen(read(429, example_body()), "route") == nil
  assert confident(read(429, example_body()), "route", 0) == false
end

test "keep_tail keeps the newest characters"
  assert keep_tail("abcdef", 3) == "def"
  assert keep_tail("abc", 10) == "abc"
  assert keep_tail("", 3) == ""
end
