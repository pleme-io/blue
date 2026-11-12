use("fairu", [:absolute])

use(
  "moji",
  %i[after_first after_last before_first before_last includes lines trim]
)

use("retsu", %i[first flat_map is_empty last size])
use("shisutemu", %i[read_or status_of stderr_of stdout_of])

INTS = [0, 1, 2, 3, 7, 12, 18, -1, -5, 100]

FLOATS = [0.0, 1.5, -2.25, 10.0]

TEXTS = ["", "a", "abc", "hello world", "aab", "Blue"]

BOOLS = [true, false]

LISTS = [[], [1], [3, 1, 2], [5, 5, -1, 0], [2, 4, 6, 8]]

ROWS = 40

INT_TYPES = %w[i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize]

@doc """
int_type: The Rust integer type a type names, or nil.

    int_type("u32") #=> "u32"
    int_type("String") #=> nil
"""
def int_type(t)
  if member?(t, INT_TYPES)
    t
  end
end

@doc """
element_of: The integer element type of a Vec<T>, &[T] or &Vec<T>, or nil.

    element_of("&[i64]") #=> "i64"
    element_of("Vec<u8>") #=> "u8"
    element_of("&Vec<i32>") #=> "i32"
    element_of("Vec<String>") #=> nil
"""
def element_of(t)
  inner = if starts_with?(t, "&[") and ends_with?(t, "]")
    before_last(after_first(t, "&["), "]")
  elsif starts_with?(t, "&Vec<") and ends_with?(t, ">")
    before_last(after_first(t, "&Vec<"), ">")
  elsif starts_with?(t, "Vec<") and ends_with?(t, ">")
    before_last(after_first(t, "Vec<"), ">")
  end
  if inner != nil
    int_type(trim(inner))
  end
end

@doc """
kind_of: A Rust type as the harness carries it: `{kind:, rust:}` with kind one
of int, float, bool, text and list, or nil for a type naturalize cannot drive.

    kind_of("i64")[:kind] #=> :int
    kind_of("&str")[:kind] #=> :text
    kind_of("&[u8]")[:kind] #=> :list
    kind_of("HashMap<String, i64>") #=> nil
"""
def kind_of(t)
  rust = trim(t)
  k = if int_type(rust) != nil
    :int
  elsif member?(rust, %w[f32 f64])
    :float
  elsif rust == "bool"
    :bool
  elsif member?(rust, %w[String &str &String])
    :text
  elsif element_of(rust) != nil
    :list
  end
  if k != nil
    {kind: k, rust:}
  end
end

@doc """
param_of: One Rust parameter, `name: Type`, as `{name:, type:}`; the type is
nil when naturalize cannot drive it.

    param_of("mut n: u32") #=> {name: "n", type: {kind: :int, rust: "u32"}}
"""
def param_of(p)
  name = trim(before_first(p, ":"))
  bare = if starts_with?(name, "mut ")
    trim(after_first(name, "mut "))
  else
    name
  end
  {name: bare, type: kind_of(after_first(p, ":"))}
end

@doc """
signature_of: A `pub fn` signature's text, up to its body, as `{name:, params:,
returns:}`, or nil when it is generic, takes self or returns nothing.

    signature_of("pub fn gcd(a: i64, b: i64) -> i64")[:name] #=> "gcd"
    signature_of("pub fn show<T>(x: T) -> String") #=> nil
    signature_of("pub fn log(x: i64)") #=> nil
"""
def signature_of(text)
  head = trim(after_first(text, "pub fn "))
  name = trim(before_first(head, "("))
  args = before_last(after_first(head, "("), ")")
  ret = if includes(after_last(head, ")"), "->")
    trim(after_first(after_last(head, ")"), "->"))
  end
  params = map(param_of, filter((p) -> trim(p) != "", split(args, ",")))
  if not includes(name, "<") and ret != nil and not includes(args, "self")
    {name:, params:, returns: kind_of(ret)}
  end
end

@doc """
drivable?: Whether every parameter and the result of a signature are types
the harness can build and read.

    drivable?(signature_of("pub fn gcd(a: i64, b: i64) -> i64")) #=> true
    drivable?(signature_of("pub fn f(x: Option<i64>) -> i64")) #=> false
"""
def drivable?(s)
  s[:returns] != nil and every?((p) -> p[:type] != nil, s[:params])
end

@doc """
signatures: Every `pub fn` signature of a Rust source, in order: a signature
runs from `pub fn` to the line that opens its body.

    size(signatures(unlines(["pub fn a(x: i64) -> i64 {", "    x", "}"]))) #=> 1
"""
def signatures(source)
  get(
    reduce(
      fn(acc, line)
        t = trim(line)
        open = acc[:open]
        if open != nil
          joined = "#{open} #{t}"
          if includes(t, "{")
            {open: nil, found: append(acc[:found], [before_first(joined, "{")])}
          else
            {open: joined, found: acc[:found]}
          end
        elsif starts_with?(t, "pub fn ")
          if includes(t, "{")
            {open: nil, found: append(acc[:found], [before_first(t, "{")])}
          else
            {open: t, found: acc[:found]}
          end
        else
          acc
        end
      end,
      {open: nil, found: []},
      lines(source)
    ),
    :found
  )
end

@doc """
samples: The values a parameter of this kind is driven with: unsigned types
take no negative value.

    samples({kind: :int, rust: "u8"}) #=> [0, 1, 2, 3, 7, 12, 18, 100]
    samples({kind: :bool, rust: "bool"}) #=> [true, false]
"""
def samples(t)
  unsigned = starts_with?(t[:rust], "u") or
    starts_with?(t[:rust], "&[u") or
    starts_with?(t[:rust], "Vec<u") or
    starts_with?(t[:rust], "&Vec<u")
  k = t[:kind]
  if k == :int and unsigned
    filter((v) -> v >= 0, INTS)
  elsif k == :int
    INTS
  elsif k == :float
    FLOATS
  elsif k == :bool
    BOOLS
  elsif k == :text
    TEXTS
  elsif unsigned
    filter((xs) -> every?((v) -> v >= 0, xs), LISTS)
  else
    LISTS
  end
end

@doc """
inputs: At most ROWS distinct argument lists for a signature, each parameter's
samples walked at its own stride so the rows spread over every parameter.

    inputs(signature_of("pub fn f() -> i64")) #=> [[]]
    size(inputs(signature_of("pub fn g(a: bool) -> bool"))) #=> 2
"""
def inputs(s)
  pools = map((p) -> samples(p[:type]), s[:params])
  distinct(
    map(
      fn(i)
        map(
          fn(k)
            pool = pools[k]
            pool[(i * (k + 1) + floor(i / 7) * k) % size(pool)]
          end,
          range(0, size(pools))
        )
      end,
      range(0, ROWS)
    )
  )
end

@doc """
rust_text: A Rust string literal for a text.

    size(rust_text("ab")) #=> 4
"""
def rust_text(s)
  json_stringify(s)
end

@doc """
rust_value: A value as a Rust expression of the parameter's type.

    rust_value({kind: :int, rust: "i64"}, -5) #=> "(-5i64)"
    rust_value({kind: :list, rust: "&[u8]"}, [1, 2]) #=> "&{ let v: Vec<u8> = vec![1u8, 2u8]; v }[..]"
"""
def rust_value(t, v)
  k = t[:kind]
  r = t[:rust]
  if k == :int
    "(#{to_s(v)}#{r})"
  elsif k == :float
    "(#{to_s(v)}#{r})"
  elsif k == :bool
    to_s(v)
  elsif k == :text and r == "&str"
    rust_text(v)
  elsif k == :text and r == "&String"
    "&String::from(#{rust_text(v)})"
  elsif k == :text
    "String::from(#{rust_text(v)})"
  else
    e = element_of(r)
    built = "{ let v: Vec<#{e}> = vec![#{join(map((x) -> "#{to_s(x)}#{e}", v), ", ")}]; v }"
    if starts_with?(r, "&[")
      "&#{built}[..]"
    elsif starts_with?(r, "&")
      "&#{built}"
    else
      built
    end
  end
end

@doc """
call_line: One harness line: call the original on one row and print the JSON
of its result, or `{"raises":true}` when it panics.

    includes(call_line("original::f", [], []), "original::f()") #=> true
"""
def call_line(callee, params, args)
  given = join(
    map((k) -> rust_value(params[k][:type], args[k]), range(0, size(params))),
    ", "
  )
  "    row(std::panic::catch_unwind(|| J::j(&#{callee}(#{given}))));"
end

HARNESS = [
  "trait J { fn j(&self) -> String; }",
  "macro_rules! ints { ($($t:ty),*) => { $(impl J for $t { fn j(&self) -> String { self.to_string() } })* } }",
  "ints!(i8, i16, i32, i64, i128, isize, u8, u16, u32, u64, u128, usize);",
  "impl J for bool { fn j(&self) -> String { self.to_string() } }",
  "impl J for f64 { fn j(&self) -> String { format!(\"{:?}\", self) } }",
  "impl J for f32 { fn j(&self) -> String { format!(\"{:?}\", self) } }",
  "impl J for str { fn j(&self) -> String { let mut o = String::from(\"\\\"\"); for c in self.chars() { match c { '\"' => o.push_str(\"\\\\\\\"\"), '\\\\' => o.push_str(\"\\\\\\\\\"), '\\n' => o.push_str(\"\\\\n\"), c if (c as u32) < 0x20 => o.push_str(&format!(\"\\\\u{:04x}\", c as u32)), c => o.push(c) } } o.push('\"'); o } }",
  "impl J for String { fn j(&self) -> String { self.as_str().j() } }",
  "impl<T: J> J for Vec<T> { fn j(&self) -> String { format!(\"[{}]\", self.iter().map(J::j).collect::<Vec<_>>().join(\",\")) } }",
  "impl<T: J + ?Sized> J for &T { fn j(&self) -> String { (**self).j() } }",
  "fn row(r: std::thread::Result<String>) { match r { Ok(s) => println!(\"{{\\\"out\\\":{}}}\", s), Err(_) => println!(\"{{\\\"raises\\\":true}}\") } }"
]

@doc """
harness_main: The Rust program that drives every row of every signature
through the original and prints one JSON line per row.

    includes(harness_main("mod original;", []), "fn main()") #=> true
"""
def harness_main(head, plans)
  join_lines(
    append(
      append([head], HARNESS),
      append(
        ["fn main() {", "    std::panic::set_hook(Box::new(|_| {}));"],
        append(
          flat_map(
            plans,
            fn(p)
              map(
                (args) -> call_line(p[:callee], p[:sig][:params], args),
                p[:rows]
              )
            end
          ),
          ["}", ""]
        )
      )
    )
  )
end

@doc """
package_name: The package name a Cargo.toml declares.

    package_name(join(["name = ", json_stringify("my-lib")], "")) #=> "my-lib"
"""
def package_name(toml)
  line = first(filter((l) -> starts_with?(trim(l), "name"), lines(toml)))
  trim(before_last(after_first(line, "\""), "\""))
end

@doc """
origin: Where TARGET's Rust source is and how the harness reaches it:
`FILE.rs` or `FILE.rs::name` (a module, included by path, compiled with
rustc), or `CRATE_DIR` or `CRATE_DIR::module::name` (a crate, a path
dependency, built with cargo).

    origin("src/gcd.rs::gcd")[:only] #=> "gcd"
    origin("src/gcd.rs")[:only] #=> nil
"""
def origin(target)
  parts = split(target, "::")
  base = first(parts)
  rest = drop(1, parts)
  if ends_with?(base, ".rs")
    {
      mode: :module,
      source: base,
      only: if is_empty(rest)
        nil
      else
        last(rest)
      end,
      path: []
    }
  else
    modules = if is_empty(rest)
      []
    else
      take(size(rest) - 1, rest)
    end
    file = if is_empty(modules)
      path_join(base, "src/lib.rs")
    else
      path_join(base, "src/#{join(modules, "/")}.rs")
    end
    {
      mode: :crate,
      dir: base,
      source: file,
      only: if is_empty(rest)
        nil
      else
        last(rest)
      end,
      path: modules
    }
  end
end

@doc """
drive: Build and run the harness in a fresh directory; the capture of the run,
or of the build when the build failed.

    status_of(drive({mode: :module, source: "/no/such.rs"}, [])) != 0 #=> true
"""
def drive(o, plans)
  dir = temp_dir("blue-naturalize")
  if o[:mode] == :module
    src = path_join(dir, "main.rs")
    head = "#[allow(dead_code)] #[path = #{json_stringify(absolute(o[:source]))}] mod original;"
    write_file(src, harness_main(head, plans))
    exe = path_join(dir, "harness")
    built = exec_capture(
      "rustc",
      "--edition",
      "2021",
      "-A",
      "warnings",
      "-o",
      exe,
      src
    )
    if status_of(built) != 0
      built
    else
      exec_capture(exe)
    end
  else
    toml = read_file(path_join(o[:dir], "Cargo.toml"))
    write_file(
      path_join(dir, "Cargo.toml"),
      join_lines(
        [
          "[package]",
          "name = \"blue-naturalize-harness\"",
          "version = \"0.0.0\"",
          "edition = \"2021\"",
          "",
          "[workspace]",
          "",
          "[dependencies]",
          "original = { path = #{json_stringify(absolute(o[:dir]))}, package = #{json_stringify(package_name(toml))} }",
          ""
        ]
      )
    )
    mkdir_p(path_join(dir, "src"))
    write_file(
      path_join(dir, "src/main.rs"),
      harness_main("#[allow(unused_imports)] use original;", plans)
    )
    exec_capture(
      "cargo",
      "run",
      "--quiet",
      "--offline",
      "--manifest-path",
      path_join(dir, "Cargo.toml")
    )
  end
end

@doc """
blue_value: A value written as blue source.

    blue_value([1, 2, true]) #=> "[1, 2, true]"
"""
def blue_value(v)
  if list?(v)
    "[#{join(map(blue_value, v), ", ")}]"
  elsif string?(v)
    json_stringify(v)
  else
    to_s(v)
  end
end

@doc """
row_text: One recorded row as blue source.

    row_text({args: [1, 2], out: 3}) #=> "{args: [1, 2], out: 3}"
    row_text({args: [0], raises: true}) #=> "{args: [0], raises: true}"
"""
def row_text(r)
  if r[:raises]
    "{args: #{blue_value(r[:args])}, raises: true}"
  else
    "{args: #{blue_value(r[:args])}, out: #{blue_value(r[:out])}}"
  end
end

@doc """
rows_name: The constant a word's rows are held in.

    rows_name("gcd") #=> "GCD_ROWS"
"""
def rows_name(name)
  "#{upcase(name)}_ROWS"
end

@doc """
example_of: A doc example from a word's first row that returns, or nil.

    includes(example_of("gcd", [{args: [12, 18], out: 6}]), "gcd(12, 18)") #=> true
"""
def example_of(name, rows)
  ok = filter((r) -> not r[:raises], rows)
  if not is_empty(ok)
    r = first(ok)
    "    #{name}(#{join(map(blue_value, r[:args]), ", ")}) #=> #{blue_value(r[:out])}"
  end
end

@doc """
word_text: A word's stub, its rows and its differential test, as blue source:
the stub raises until its body is written, so the test is red until the port
agrees with every row.

    includes(word_text("f", "src/f.rs", ["a"], [{args: [1], out: 1}]), "def f(_a)") #=> true
"""
def word_text(name, source, params, rows)
  rows_const = rows_name(name)
  example = example_of(name, rows)
  join_lines(
    [
      "@doc \"\"\"",
      "#{name}: The port of `#{name}` in #{source}; what it must return is the rows recorded from that original.",
      "",
      "    length(#{rows_const}) #=> #{to_s(size(rows))}",
      if example.nil?
        ""
      else
        example
      end,
      "\"\"\"",
      "def #{name}(#{join(map((p) -> "_#{p}", params), ", ")})",
      "  raise(:unported, \"#{name} is not ported yet: write its body until its rows agree\")",
      "end",
      "",
      "@doc \"\"\"",
      "#{rows_const}: What the original returned for each argument list, recorded by blue naturalize.",
      "",
      "    length(#{rows_const}) #=> #{to_s(size(rows))}",
      "\"\"\"",
      "#{rows_const} = [#{join(map(row_text, rows), ", ")}]",
      "",
      "test \"#{name} agrees with the original on every recorded row\"",
      "  assert disagreements(#{rows_const}, (args) -> #{name}(*args)) == []",
      "end",
      ""
    ]
  )
end

@doc """
module_text: The bidama's file: its moduledoc, the shared differential word,
then each ported word.

    includes(module_text("kazu", "src/a.rs", []), "def disagreements") #=> true
"""
def module_text(pkg, source, words)
  join_lines(
    append(
      [
        "@moduledoc \"\"\"",
        "#{pkg}: Words naturalized from the Rust in #{source}. Each word's rows were recorded from the original by `blue naturalize`; porting is writing each body until `blue test` agrees with every row.",
        "",
        "    disagreements([{args: [1], out: 1}], (args) -> first(args)) #=> []",
        "\"\"\"",
        "",
        "@doc \"\"\"",
        "disagreements: The recorded rows a word does not reproduce, each with what the word gave: a row that raises in the original must raise in the port.",
        "",
        "    disagreements([{args: [1], out: 2}], (args) -> first(args)) #=> [{args: [1], out: 2, got: 1}]",
        "\"\"\"",
        "def disagreements(rows, f)",
        "  filter(",
        "    (r) -> r != nil,",
        "    map(",
        "      fn(r)",
        "        got = f(r[:args]) rescue :raised",
        "        want = if r[:raises]",
        "          :raised",
        "        else",
        "          r[:out]",
        "        end",
        "        if got != want",
        "          assoc(r, :got, got)",
        "        end",
        "      end,",
        "      rows",
        "    )",
        "  )",
        "end",
        ""
      ],
      words
    )
  )
end

@doc """
parsed_rows: The harness's output lines, read beside the inputs that made them.

    parsed_rows([[1]], json_stringify({out: 2})) #=> [{args: [1], out: 2}]
"""
def parsed_rows(inputs, out)
  outs = map(json_read, filter((l) -> trim(l) != "", lines(out)))
  map(
    fn(k)
      o = outs[k]
      if o["raises"] == true
        {args: inputs[k], raises: true}
      else
        {args: inputs[k], out: o["out"]}
      end
    end,
    range(0, size(outs))
  )
end

@doc """
split_rows: The rows of each plan, in plan order, from the rows of all plans.

    split_rows([{rows: [1, 2]}, {rows: [3]}], %w[a b c]) #=> [%w[a b], ["c"]]
"""
def split_rows(plans, all)
  get(
    reduce(
      fn(acc, p)
        n = size(p[:rows])
        {
          at: acc[:at] + n,
          parts: append(acc[:parts], [take(n, drop(acc[:at], all))])
        }
      end,
      {at: 0, parts: []},
      plans
    ),
    :parts
  )
end

@doc """
naturalize: Scaffold DIR as a bidama whose words are TARGET's drivable `pub
fn`s: a stub per word, the rows the original returned, and a test per word
that is red until the stub's body agrees with every row.

    origin("a.rs")[:mode] #=> :module
"""
def naturalize(target, dir)
  o = origin(target)
  if path_exists(dir) and not is_empty(ls(dir))
    raise(
      :naturalize,
      "#{dir} exists and is not empty; naturalize writes only a new bidama"
    )
  end
  source = read_or(o[:source], nil)
  if source.nil?
    raise(:naturalize, "#{o[:source]}: no such Rust source")
  end
  sigs = filter((s) -> s != nil, map(signature_of, signatures(source)))
  chosen = filter((s) -> o[:only].nil? or s[:name] == o[:only], sigs)
  skipped = filter((s) -> not drivable?(s), chosen)
  driven = filter(drivable?, chosen)
  if is_empty(driven)
    raise(
      :naturalize,
      "#{target}: no pub fn whose parameters and result are integers, floats, bools, text or integer lists"
    )
  end
  prefix = if o[:mode] == :module
    "original"
  else
    join(cons("original", o[:path]), "::")
  end
  plans = map(
    (s) -> {sig: s, callee: "#{prefix}::#{s[:name]}", rows: inputs(s)},
    driven
  )
  ran = drive(o, plans)
  if status_of(ran) != 0
    raise(
      :naturalize,
      "the harness against #{o[:source]} failed: #{stderr_of(ran)}"
    )
  end
  recorded = split_rows(
    plans,
    parsed_rows(flat_map(plans, (p) -> p[:rows]), stdout_of(ran))
  )
  pkg = path_basename(dir)
  words = map(
    fn(k)
      p = plans[k]
      s = p[:sig]
      word_text(
        s[:name],
        o[:source],
        map((x) -> x[:name], s[:params]),
        recorded[k]
      )
    end,
    range(0, size(plans))
  )
  mkdir_p(dir)
  write_file(
    path_join(dir, "Bluefile"),
    unlines(["package(#{json_stringify(pkg)}, \"0.1.0\")"])
  )
  write_program(path_join(dir, "#{pkg}.b"), module_text(pkg, o[:source], words))
  write_stdout(
    unlines(
      append(
        map(
          fn(k)
            "naturalized #{plans[k][:sig][:name]}: #{to_s(size(recorded[k]))} rows"
          end,
          range(0, size(plans))
        ),
        append(
          map(
            (s) -> "skipped #{s[:name]}: a type naturalize cannot drive",
            skipped
          ),
          [
            "wrote #{path_join(dir, "#{pkg}.b")}; blue test it until every row agrees"
          ]
        )
      )
    )
  )
end

def main()
  if size(argv) != 2
    write_stderr(
      unlines(
        ["usage: blue naturalize <FILE.rs[::name] | CRATE_DIR[::module::name]> DIR"]
      )
    )
    exit_with(64)
  end
  naturalize(argv[0], argv[1])
  exit_with(0)
end
