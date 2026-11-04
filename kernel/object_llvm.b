@moduledoc """
object_llvm: The same program built two ways, blue's `erufu::object` and clang from generated C, read by LLVM's own tools and compared.

The C holds naked functions over assembly `bpf::text` prints, so its instructions are blue's by construction and every other difference is the object's. Clang is an oracle here alone: nothing in the build path needs it.

    blue kernel/object_llvm.b CLANG LLVM_OBJDUMP LLVM_READOBJ READELF
"""

use("bpf")
use("btf")
use("deeta", [:json_at])
use("erufu")
use("retsu", %i[first flat_map rest size])

@doc """
param_c: a parameter's type in the generated C.

    param_c(:ctx) #=> "struct xdp_md *"
    param_c(:fault) #=> "long long *"
    param_c(:int) #=> "long long "
"""
def param_c(kind)
  case kind
  when :ctx
    "struct xdp_md *"
  when :fault
    "long long *"
  else
    "long long "
  end
end

@doc """
signature_c: a function's C signature, parameters named as BTF names them.

    signature_c({name: "g", params: [:int, :fault]}) #=> "long long g(long long arg0, long long *arg1)"
"""
def signature_c(f)
  params = map(
    (pair) -> "#{param_c(pair[1])}arg#{to_s(first(pair))}",
    retsu::enumerate(f[:params])
  )
  "long long #{f[:name]}(#{join(params, ", ")})"
end

@doc """
map_c: a map's definition in the generated C, as `bpf::map_btf` says it.

    contains?(map_c(bpf::declare_map(:m, :array, 4, 8, 1)), "(*value_size)[8]") #=> true
    contains?(map_c(bpf::declare_locked(:m, :array, 4, 1)), "struct blue_locked *value") #=> true
"""
def map_c(m)
  kind = retsu::index_of(bpf::map_kinds, m[:kind])
  inner = if m[:lock] == true
    "unsigned int *key; struct blue_locked *value;"
  else
    "int (*key_size)[#{to_s(m[:key_size])}]; int (*value_size)[#{to_s(m[:value_size])}];"
  end
  "struct { int (*type)[#{to_s(kind)}]; #{inner} int (*max_entries)[#{to_s(m[:max_entries])}]; } #{to_s(m[:name])} __attribute__((section(\".maps\"), used));"
end

@doc """
data_c: a map a program references by value, in the generated C.

    contains?(data_c(bpf::declare_map(:g, :array, 4, 16, 1)), "char g[16]") #=> true
"""
def data_c(m)
  "char #{to_s(m[:name])}[#{to_s(m[:value_size])}] __attribute__((section(\"#{bpf::data_map_place(m)[:section]}\"), used));"
end

@doc """
insn_text: one instruction as assembly, a map or a function by its symbol.

    insn_text(bpf::exit_program, 0, {relocs: {}, funcs: []}) #=> "exit"
    insn_text(bpf::map_ref(1, :m), 0, {relocs: {0 => "m"}, funcs: []}) #=> "r1 = m ll"
"""
def insn_text(i, slot, world)
  mapped = get(world[:relocs], slot)
  if mapped != nil
    "r#{to_s(i[:dst])} = #{mapped} ll"
  elsif i[:code] == 133 and i[:src] == 1
    callee = erufu::function_at(world[:funcs], slot + 1 + i[:imm])
    "call #{callee[:name]}"
  else
    bpf::text(i)
  end
end

@doc """
function_c: one function as a naked C function, its instructions the slots given.

    contains?(function_c({name: "e", params: [:ctx]}, [bpf::exit_program], 0, "xdp", {relocs: {}, funcs: []}), "naked") #=> true
"""
def function_c(f, insns, from, section, world)
  lines = get(
    reduce(
      fn(acc, i)
        {
          slot: acc[:slot] + bpf::slots_of(i),
          rows: append(
            acc[:rows],
            ["  \"#{insn_text(i, acc[:slot], world)}\\n\""]
          )
        }
      end,
      {slot: from, rows: []},
      insns
    ),
    :rows
  )
  placed = if section != nil
    ", section(\"#{section}\")"
  else
    ""
  end
  unlines(
    append(
      *[
        ["__attribute__((naked, used#{placed})) #{signature_c(f)} {"],
        ["asm volatile("],
        lines,
        [");"],
        ["}"]
      ]
    )
  )
end

@doc """
source_c: a whole compiled program as C.

    contains?(source_c(bpf::compile_forms(read_forms("(define (%root/e c) 2)"), {entry: :e, kind: :xdp})), "_license") #=> true
"""
def source_c(p)
  funcs = p[:funcs]
  by_value = erufu::value_maps(p)
  world = {
    funcs:,
    relocs: reduce(
      (acc, r) -> assoc(acc, r[:at], to_s(r[:map])),
      {},
      p[:relocs]
    )
  }
  boundary = erufu::split_at(p, funcs)
  parts = erufu::slot_split(p[:insns], boundary)
  subs = rest(funcs)
  by_sub = reduce(
    fn(acc, row)
      at = first(row)
      f = row[1]
      stop = if at + 1 < size(subs)
        subs[at + 1][:at]
      else
        p[:slots]
      end
      cut = erufu::slot_split(acc[:left], stop - f[:at])
      {
        left: cut[1],
        rows: append(
          acc[:rows],
          [function_c(f, first(cut), f[:at], nil, world)]
        )
      }
    end,
    {left: parts[1], rows: []},
    retsu::enumerate(subs)
  )
  join(
    append(
      *[
        [
          "struct xdp_md { unsigned int data; unsigned int data_end; unsigned int data_meta; unsigned int ingress_ifindex; unsigned int rx_queue_index; unsigned int egress_ifindex; };",
          "struct bpf_spin_lock { unsigned int val; };",
          "struct blue_locked { struct bpf_spin_lock lock; long long total; };"
        ],
        map(map_c, filter((m) -> not member?(m, by_value), p[:maps])),
        map(data_c, by_value),
        ["char _license[] __attribute__((section(\"license\"), used)) = \"GPL\";"],
        map((f) -> "#{signature_c(f)};", funcs),
        [
          function_c(
            first(funcs),
            first(parts),
            0,
            bpf::section_name(p[:kind]),
            world
          )
        ],
        by_sub[:rows]
      ]
    ),
    line_break
  )
end

@doc """
clang_only?: whether a section is one clang adds that an object need not hold: debug info, and the relocations of `.BTF` a linker reads and libbpf does not.

    clang_only?(".debug_info") #=> true
    clang_only?(".rel.BTF.ext") #=> true
    clang_only?(".BTF") #=> false
"""
def clang_only?(name)
  starts_with?(name, ".debug") or
    starts_with?(name, ".rel.debug") or
    starts_with?(name, ".rel.BTF") or
    name == ".llvm_addrsig"
end

@doc """
readobj_of: LLVM's reading of an object as parsed JSON.

    (readobj_of("/no/such/tool", "x.o") rescue :refused) #=> :refused
"""
def readobj_of(tool, path)
  got = exec_capture(
    tool,
    "--sections",
    "--symbols",
    "-r",
    "--elf-output-style=JSON",
    path
  )
  if got.status != 0
    raise(:llvm, "#{tool} #{path}: #{got.stderr}")
  end
  first(json_parse(got.stdout))
end

@doc """
sorted_rows: rows in one order, so two tables compare as sets.

    sorted_rows(["b", "a"]) #=> ["a", "b"]
"""
def sorted_rows(rows)
  sort_keyed((r) -> r, rows)
end

@doc """
section_rows: what LLVM says of each section that both objects must have.

    section_rows([]) #=> []
"""
def section_rows(doc)
  sections = json_get(doc, :Sections) or []
  sorted_rows(
    filter(
      (r) -> r != nil,
      map(
        fn(row)
          s = json_get(row, :Section)
          name = json_at(s, "Name.Name")
          if not clang_only?(name)
            "#{name} #{json_at(s, "Type.Name")} flags #{to_s(json_at(s, "Flags.Value"))} entsize #{to_s(json_get(s, "EntrySize"))} align #{to_s(json_get(s, "AddressAlignment"))}"
          end
        end,
        sections
      )
    )
  )
end

@doc """
symbol_rows: what LLVM says of each function and object symbol.

    symbol_rows([]) #=> []
"""
def symbol_rows(doc)
  symbols = json_get(doc, :Symbols) or []
  sorted_rows(
    filter(
      (r) -> r != nil,
      map(
        fn(row)
          s = json_get(row, :Symbol)
          kind = json_at(s, "Type.Name")
          name = json_at(s, "Name.Name")
          if member?(kind, %w[Function Object])
            "#{name} #{kind} #{json_at(s, "Binding.Name")} size #{to_s(json_get(s, "Size"))} in #{json_at(s, "Section.Name")} at #{to_s(json_get(s, "Value"))}"
          end
        end,
        symbols
      )
    )
  )
end

@doc """
reloc_rows: what LLVM says of each relocation of a section both objects must have.

    reloc_rows([]) #=> []
"""
def reloc_rows(doc)
  groups = json_get(doc, :Relocations) or []
  names = map(
    (row) -> json_at(json_get(row, :Section), "Name.Name"),
    json_get(doc, :Sections) or []
  )
  sorted_rows(
    flat_map(
      groups,
      fn(row)
        name = names[json_get(row, :SectionIndex)]
        if clang_only?(name)
          []
        else
          map(
            fn(r)
              one = json_get(r, :Relocation)
              "#{name} #{to_s(json_get(one, "Offset"))} #{json_at(one, "Type.Name")} #{json_at(one, "Symbol.Name")}"
            end,
            json_get(row, :Relocs) or []
          )
        end
      end
    )
  )
end

@doc """
after_first: the lines of a tool's output from the first one holding `word`.

    after_first(unlines(["x", "Disassembly", "y"]), "Disassembly") #=> ["Disassembly", "y"]
    after_first("", "Disassembly") #=> []
"""
def after_first(text, word)
  got = reduce(
    fn(acc, line)
      if acc[:seen] or contains?(line, word)
        {seen: true, rows: append(acc[:rows], [line])}
      else
        acc
      end
    end,
    {seen: false, rows: []},
    filter((l) -> trim(l) != "", split(text, line_break))
  )
  got[:rows]
end

@doc """
disassembly_of: LLVM's disassembly of an object with its relocations, from its first section.

    (disassembly_of("/no/such/tool", "x.o") rescue :refused) #=> :refused
"""
def disassembly_of(tool, path)
  got = exec_capture(tool, "-dr", path)
  if got.status != 0
    raise(:llvm, "#{tool} #{path}: #{got.stderr}")
  end
  after_first(got.stdout, "Disassembly of section")
end

@doc """
type_text: a BTF type as text with its ids gone, so two blobs compare by what they mean.

    type_text(btf::read(btf::encode([btf::int_type("int", 4)])), 1) #=> "int int 4"
    type_text(btf::read(btf::encode([])), 0) #=> "void"
"""
def type_text(table, id)
  t = btf::type_at(table, id)
  case t[:kind]
  when :void
    "void"
  when :int
    "int #{t[:name]} #{to_s(t[:size])}"
  when :ptr
    "*#{type_text(table, t[:type])}"
  when :array
    "#{type_text(table, t[:element])}[#{to_s(t[:count])}]"
  when :struct
    members = map(
      (m) -> "#{m[:name]}@#{to_s(m[:bits])}:#{type_text(table, m[:type])}",
      t[:members]
    )
    "struct #{t[:name]} #{to_s(t[:size])} {#{join(members, "; ")}}"
  when :func_proto
    params = map((p) -> type_text(table, p[:type]), t[:params])
    "(#{join(params, ", ")}) -> #{type_text(table, t[:type])}"
  else
    "#{to_s(t[:kind])} #{t[:name]}"
  end
end

@doc """
btf_rows: each function, variable and data section of a blob as text, after libbpf's fixup of a data section's places.

    btf_rows({sections: [], symbols: []}, btf::encode([])) #=> []
"""
def btf_rows(o, blob)
  table = btf::read(erufu::fixed_blob(o, blob))
  sorted_rows(
    filter(
      (r) -> r != nil,
      map(
        fn(id)
          t = btf::type_at(table, id)
          case t[:kind]
          when :func
            "func #{t[:name]} linkage #{to_s(bit_and(t[:vlen], 3))} #{type_text(table, t[:type])}"
          when :var
            "var #{t[:name]} #{type_text(table, t[:type])}"
          when :datasec
            vars = map(
              fn(v)
                "#{btf::type_at(table, v[:type])[:name]}@#{to_s(v[:offset])}+#{to_s(v[:size])}"
              end,
              t[:vars]
            )
            "datasec #{t[:name]} #{to_s(t[:size])} #{join(sorted_rows(vars), " ")}"
          end
        end,
        range(1, table[:count] + 1)
      )
    )
  )
end

@doc """
func_info_rows: `.BTF.ext`'s functions as text: section, byte offset and function name.

    func_info_rows(erufu::decode(erufu::object(bpf::assemble([bpf::exit_program]), {section: "xdp"}))) #=> ["xdp 0 blue"]
"""
def func_info_rows(o)
  blob = erufu::section_of(o, ".BTF")[:bytes]
  table = btf::read(blob)
  sorted_rows(
    flat_map(
      btf::read_ext(erufu::section_of(o, ".BTF.ext")[:bytes], blob),
      fn(s)
        map(
          fn(f)
            "#{s[:section]} #{to_s(f[:at])} #{btf::type_at(table, f[:type])[:name]}"
          end,
          s[:funcs]
        )
      end
    )
  )
end

@doc """
verdict: one view compared: {name:, same:, only_blue:, only_clang:}, each list what the other lacks.

    verdict("v", ["a"], ["a"])[:same] #=> true
    verdict("v", ["a"], ["b"])[:only_blue] #=> ["a"]
    verdict("v", [], [])[:same] #=> true
"""
def verdict(name, blue_rows, clang_rows)
  only_blue = filter((r) -> not member?(r, clang_rows), blue_rows)
  only_clang = filter((r) -> not member?(r, blue_rows), clang_rows)
  {
    name:,
    count: size(blue_rows),
    same: only_blue == [] and
      only_clang == [] and
      size(blue_rows) == size(clang_rows),
    only_blue:,
    only_clang:
  }
end

@doc """
line_info_rows: the sections an object's `.BTF.ext` holds source lines for. The lines differ, since blue's name blue's source and clang's its C; the shape must not.

    (line_info_rows({sections: []}) rescue :refused) #=> :refused
"""
def line_info_rows(o)
  rows = btf::read_lines(
    erufu::section_of(o, ".BTF.ext")[:bytes],
    erufu::section_of(o, ".BTF")[:bytes]
  )
  sorted_rows(map((s) -> s[:section], filter((s) -> s[:lines] != [], rows)))
end

@doc """
line_info_verdict: the view of source lines, for a program that has them. An assembled program has no source to name, where clang's C always does.

    line_info_verdict({sections: [{name: ".BTF.ext", bytes: btf::encode_ext([], [], [])}, {name: ".BTF", bytes: btf::encode([])}]}, {sections: []})[:same] #=> true
"""
def line_info_verdict(blue_o, clang_o)
  ours = line_info_rows(blue_o)
  if ours == []
    verdict("line_info sections", [], [])
  else
    verdict("line_info sections", ours, line_info_rows(clang_o))
  end
end

@doc """
views: every view of two objects, by LLVM's tools and by the BTF each holds.

    (views({}, "/no/a.o", "/no/b.o") rescue :refused) #=> :refused
"""
def views(tools, blue_path, clang_path)
  ours = readobj_of(tools[:readobj], blue_path)
  theirs = readobj_of(tools[:readobj], clang_path)
  blue_o = erufu::decode(read_bytes(blue_path))
  clang_o = erufu::decode(read_bytes(clang_path))
  [
    verdict("sections", section_rows(ours), section_rows(theirs)),
    verdict("symbols", symbol_rows(ours), symbol_rows(theirs)),
    verdict("relocations", reloc_rows(ours), reloc_rows(theirs)),
    verdict(
      "disassembly",
      disassembly_of(tools[:objdump], blue_path),
      disassembly_of(tools[:objdump], clang_path)
    ),
    verdict(
      "BTF",
      btf_rows(blue_o, erufu::section_of(blue_o, ".BTF")[:bytes]),
      btf_rows(clang_o, erufu::section_of(clang_o, ".BTF")[:bytes])
    ),
    verdict("func_info", func_info_rows(blue_o), func_info_rows(clang_o)),
    line_info_verdict(blue_o, clang_o)
  ]
end

@doc """
tool_verdict: a tool's acceptance of an object: exit 0 and nothing on stderr.

    tool_verdict("true", []) #=> true
    tool_verdict("false", []) #=> false
"""
def tool_verdict(tool, args)
  got = exec_capture(tool, *args)
  got.status == 0 and trim(got.stderr) == ""
end

@doc """
tampered: an object's bytes with one instruction's first byte changed, for the control run.

    tampered([1, 2, 3], 1) #=> [1, 3, 3]
"""
def tampered(bytes, at)
  erufu::replaced(bytes, at, bit_xor(bytes[at], 1))
end

@doc """
value_program: a program that reads through a reference into a map's value, the second shape this oracle holds against clang.

    value_program[:maps][0][:value_size] #=> 16
"""
def value_program()
  assoc(
    assoc(
      bpf::with_funcs(
        bpf::assemble(
          [
            bpf::map_value_ref(1, :globals, 0),
            bpf::load(:dw, 0, 1, 0),
            bpf::exit_program
          ]
        ),
        [{name: "e", linkage: :global, params: [:ctx]}]
      ),
      :maps,
      [bpf::declare_map(:globals, :array, 4, 16, 1)]
    ),
    :kind,
    :xdp
  )
end

@doc """
compared: one program built both ways and each view told: whether all of them agree, a tool reads blue's object and a changed instruction is seen.

    (compared({}, "/no/such", "x", bpf::assemble([])) rescue :refused) #=> :refused
"""
def compared(tools, dir, label, p)
  blue_path = path_join(dir, "#{label}_blue.o")
  c_path = path_join(dir, "#{label}_clang.c")
  clang_path = path_join(dir, "#{label}_clang.o")
  write_bytes(blue_path, erufu::object(p))
  write_file(c_path, source_c(p))
  built = exec_capture(
    tools[:clang],
    "-target",
    "bpf",
    "-mcpu=v4",
    "-O2",
    "-g",
    "-c",
    c_path,
    "-o",
    clang_path
  )
  if built.status != 0
    raise(:clang, built.stderr)
  end
  seen = views(tools, blue_path, clang_path)
  map(
    fn(v)
      if v[:same]
        write_stdout(
          unlines(["✅ #{label} #{v[:name]}: #{to_s(v[:count])} rows agree"])
        )
      else
        write_stdout(
          unlines(
            append(
              ["❌ #{label} #{v[:name]}"],
              append(
                map((r) -> "  blue:  #{r}", v[:only_blue]),
                map((r) -> "  clang: #{r}", v[:only_clang])
              )
            )
          )
        )
      end
    end,
    seen
  )
  accepted = tool_verdict(tools[:readelf], ["-a", "--wide", blue_path])
  write_stdout(
    unlines(
      [
        "#{if accepted
  "✅"
else
  "❌"
end} #{label} readelf -a: read without a warning"
      ]
    )
  )
  bytes = read_bytes(blue_path)
  section = erufu::section_of(erufu::decode(bytes), "xdp")
  bad_path = path_join(dir, "#{label}_bad.o")
  write_bytes(bad_path, tampered(bytes, section[:offset]))
  control = verdict(
    "control",
    disassembly_of(tools[:objdump], bad_path),
    disassembly_of(tools[:objdump], clang_path)
  )
  write_stdout(
    unlines(
      [
        "#{if control[:same]
  "❌ control: a changed instruction went unseen"
else
  "✅ control: a changed instruction is seen"
end}"
      ]
    )
  )
  filter((v) -> not v[:same], seen) == [] and accepted and not control[:same]
end

def main()
  args = argv
  tools = {clang: args[0], objdump: args[1], readobj: args[2], readelf: args[3]}
  dir = path_join(getenv("TMPDIR", "/tmp"), "blue-object-llvm-#{to_s(now_ms)}")
  mkdir_p(dir)
  compiled = bpf::compile(
    "kernel/programs/object.b",
    {entry: :on_packet, kind: :xdp, on_fault: 0, global: [:sum_into]}
  )
  green = compared(tools, dir, "compiled", compiled)
  valued = compared(tools, dir, "value", value_program)
  if not (green and valued)
    write_stdout(unlines(["kept for reading: #{dir}"]))
    exit_with(1)
  end
  rm_rf(dir)
end

test "no rows on either side agree, and rows only one side has are named"
  assert verdict("v", [], [])[:same]
  bad = verdict("v", %w[a b], %w[b c])
  assert not bad[:same]
  assert bad[:only_blue] == ["a"]
  assert bad[:only_clang] == ["c"]
  assert not verdict("v", %w[a a], ["a"])[:same]
end

test "the C of a compiled program declares its map, its function and its license"
  c = source_c(
    bpf::compile_forms(
      read_forms("(define %root/M (bpf/declare_map :m :array 4 8 1)) (define (%root/e c) (begin (bpf/map_add %root/M 0 1) 2))"),
      {entry: :e, kind: :xdp, on_fault: 0}
    )
  )
  assert contains?(c, "r1 = m ll")
  assert contains?(c, "long long e(struct xdp_md *arg0)")
  assert contains?(c, "_license")
end
