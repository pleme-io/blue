@moduledoc """
memory: the ownership facts kuzushi reads from a program (M2 of docs/PURE-BLUE.md).
`blue explain --memory FILE` lowers FILE with `blue ast --resolved` and prints one
fact per line, in order: today the last read of each local (M1's facts). With
`--hints` it prints each fact as a JSON hint placed at that last read, from the
`local_reads` and `definitions` of `blue ast --resolved --json`: the inlay hints
the language server serves without running the program.

    facts_of("(define (sq x) (* x x))") #=> ["sq: last_use x (* x x)"]
"""

use("kuzushi", [:memory_facts])
use("retsu", %i[first is_empty last])

@doc """
facts_of: The facts kuzushi reads from resolved forms written as text.

    facts_of("(define (k x) 1)") #=> []
"""
def facts_of(text)
  memory_facts(read_forms(text))
end

@doc """
fact_parts: The definition and the local a fact is about.

    fact_parts("sq: last_use x (* x x)") #=> ["sq", "x"]
"""
def fact_parts(fact)
  halves = split(fact, ": last_use ")
  [halves[0], first(split(halves[1], " "))]
end

@doc """
place_of: Where the local a fact is about is last read in its definition, as
[line, column], or nil when the definition or a read is not found.

    place_of("f: last_use x x", [{"name" => "f", "top_level" => 0}], [{"top_level" => 0, "name" => "x", "byte_start" => 3, "line" => 1, "column" => 4}]) #=> [1, 4]
"""
def place_of(fact, definitions, reads)
  parts = fact_parts(fact)
  found = find(definitions, (d) -> d["name"] == parts[0])
  mine = if found.nil?
    []
  else
    filter(
      (r) -> r["top_level"] == found["top_level"] and r["name"] == parts[1],
      reads
    )
  end
  if not is_empty(mine)
    at = last(sort_keyed((r) -> r["byte_start"], mine))
    [at["line"], at["column"]]
  end
end

@doc """
hint_lines: Each fact that has a place as one JSON hint line: line, column and
a label naming the local whose last read it marks.

    hint_lines(["f: last_use x x"], [{"name" => "f", "top_level" => 0}], [{"top_level" => 0, "name" => "x", "byte_start" => 3, "line" => 1, "column" => 4}]) #=> ["{\"column\":4,\"label\":\"last read of x\",\"line\":1}"]
"""
def hint_lines(facts, definitions, reads)
  placed = map(
    fn(fact)
      at = place_of(fact, definitions, reads)
      if at != nil
        json_stringify(
          {
            "line" => at[0],
            "column" => at[1],
            "label" => "last read of #{fact_parts(fact)[1]}"
          }
        )
      end
    end,
    facts
  )
  filter((h) -> h != nil, placed)
end

def main(args)
  if is_empty(args)
    write_stderr(unlines(["usage: blue explain --memory FILE [--hints]"]))
    false
  else
    file = first(args)
    lowered = exec_capture(self_exe, "ast", "--resolved", file)
    if lowered.status != 0
      write_stderr(
        join_lines(
          ["blue explain --memory: #{file} does not lower", lowered.stderr]
        )
      )
      false
    else
      facts = facts_of(lowered.stdout)
      out = if member?("--hints", args)
        doc = json_read(
          exec_capture(self_exe, "ast", "--resolved", "--json", file).stdout
        )
        hint_lines(facts, doc["definitions"], doc["local_reads"])
      else
        facts
      end
      if not is_empty(out)
        write_stdout(unlines(out))
      end
      true
    end
  end
end

test "a program's facts are its locals' last reads, one per local", {
  kind: :integration
}
  assert facts_of("(define (f x) (let ((y (+ x 1))) (* y x)))") ==
    ["f: last_use y (* y x)", "f: last_use x (* y x)"]
  assert facts_of("(define (k x) 1)") == []
end

test "each fact is placed at its local's last read in its own definition", {
  kind: :unit
}
  defs = [{"name" => "f", "top_level" => 0}, {"name" => "g", "top_level" => 1}]
  reads = [
    {
      "top_level" => 0,
      "name" => "x",
      "byte_start" => 3,
      "line" => 1,
      "column" => 4
    },
    {
      "top_level" => 0,
      "name" => "x",
      "byte_start" => 9,
      "line" => 2,
      "column" => 3
    },
    {
      "top_level" => 1,
      "name" => "x",
      "byte_start" => 20,
      "line" => 4,
      "column" => 5
    }
  ]
  assert fact_parts("g: last_use s (size s)") == %w[g s]
  assert place_of("f: last_use x (* x x)", defs, reads) == [2, 3]
  assert place_of("g: last_use x x", defs, reads) == [4, 5]
  assert place_of("h: last_use x x", defs, reads).nil?
  assert hint_lines(["k: last_use z z"], defs, reads) == []
end

main(argv)
