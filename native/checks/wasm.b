use("chuuzou", [:cz_wasm_image])

def run_of(args)
  r = exec_capture(*args)
  {ok: second(first(r)) == 0, out: second(second(r))}
end

def seeded(seed, work)
  text = join(
    map(
      fn(l)
        if starts_with?(l, "SEED = ")
          "SEED = #{to_s(seed)}"
        else
          l
        end
      end,
      split(read_file(env_required("WASM_PROGRAM")), line_break)
    ),
    line_break
  )
  dir = path_join(work, "seed-#{to_s(seed)}")
  mkdir_p(dir)
  file = path_join(dir, "hex.b")
  write_program(file, text)
  file
end

def interpret(program)
  run_of([self_exe, "run", "--quiet", "--door", "walker", program])
end

def component(program)
  image = cz_wasm_image(
    program,
    env_required("WASM_SEAM"),
    path_join(path_dirname(program), "out")
  )
  run_of(["wasmtime", "run", image])
end

def seeds()
  [1, 7, 255, 2026]
end

test "the hex words, compiled ahead of time to a wasm component, print what the interpreter prints for every seed"
  work = path_join(temp_dir("chuuzou-wasm"), "chuuzou-wasm")
  differ = filter(
    fn(seed)
      program = seeded(seed, work)
      want = interpret(program)
      got = component(program)
      not (
        want[:ok] and
        got[:ok] and
        want[:out] == got[:out] and
        ends_with?(want[:out], unlines(["64"]))
      )
    end,
    seeds
  )
  assert differ == []
end
