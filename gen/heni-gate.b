use("heni", [:mutations, :ok?, :report_text, :run])
use("mokuroku", [:blue_path_roots])
use("retsu", [:find_first, :last, :reject, :size])

def off?()
  v = getenv("BLUE_HENI_OFF")
  if v.nil?
    false
  elsif v == "1"
    true
  else
    raise(:heni_gate, "BLUE_HENI_OFF is \"#{v}\"; the one value it takes is 1")
  end
end

def bidamas_root()
  here = find_first(
    (r) -> path_exists(path_join(r, "heni/mutations")),
    blue_path_roots(getenv("BLUE_PATH", ""))
  )
  if here.nil?
    "bidamas"
  else
    here
  end
end

def specs()
  reject(
    (p) -> not ends_with?(p, ".json"),
    sort_keyed((p) -> p, walk_dir(path_join(bidamas_root, "heni/mutations")))
  )
end

def package_of(spec_path)
  stem = replace(last(split(spec_path, "/")), ".json", "")
  path_join(bidamas_root, stem)
end

def report(spec_path)
  run(
    {
      package: package_of(spec_path),
      mutations: mutations(json_parse(read_file(spec_path))),
      blue: self_exe,
      test: nil,
      tmp: getenv("TMPDIR", "/tmp")
    }
  )
end

test "every mutation set of heni fails the tests of its package"
  if not off?
    assert size(specs) >= 2
    map(
      fn(spec_path)
        r = report(spec_path)
        if not ok?(r)
          write_stderr("#{spec_path}: #{report_text(r)}")
        end
        assert ok?(r)
      end,
      specs
    )
  end
end

test "a mutation file names the package it mutates"
  assert package_of("heni/mutations/shuusei.json") ==
    path_join(bidamas_root, "shuusei")
end
