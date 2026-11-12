use("chuuzou", [:cz_wasm_image])

def printed(args)
  r = exec_capture(*args)
  if second(first(r)) == 0
    second(second(r))
  end
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
  printed([self_exe, "run", "--quiet", "--door", "walker", program])
end

def component(program)
  image = cz_wasm_image(
    program,
    env_required("WASM_SEAM"),
    path_join(path_dirname(program), "out")
  )
  printed(["wasmtime", "run", image])
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
      want.nil? or want != got or not ends_with?(want, unlines(["64"]))
    end,
    seeds
  )
  assert differ == []
end
