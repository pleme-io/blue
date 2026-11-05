@moduledoc """
erufu — an ELF relocatable object as data: written from a compiled kernel program, and read back, so `bpftool`, `veristat`, `llvm-objdump` and `readelf` apply to what blue compiles, and blue can read what clang compiles.

`object` writes the bytes the kernel's own tools read: the program in a section libbpf knows by name, its subprograms in `.text`, its maps in `.maps`, its types in `.BTF` and `.BTF.ext`. `decode` reads any little-endian ELF64 object, and `program_of` links one back into a program `kaaneru::bpf::run` and `kaaneru::install` take. Every record is a `baito` layout.

    p = kaaneru::bpf::assemble([kaaneru::bpf::alu(:mov, 0, 2), kaaneru::bpf::exit_program])
    bytes = object(assoc(assoc(p, :kind, :xdp), :name, "pass"))
    section_of(decode(bytes), "xdp")[:size] #=> 16
    kaaneru::bpf::run(program_of(decode(bytes))).ret #=> 2
"""

use("baito", %i[align_up layout pack slice_bytes text_of unpack width])

use("kaaneru/bpf")
use("kaaneru/btf")
use("retsu", %i[first flat_map index_of last repeat rest size zip])
use("shuugou")

@doc """
header_layout: `Elf64_Ehdr`.

    width(header_layout) #=> 64
"""
def header_layout()
  layout(
    [
      [:ident, [:bytes, 16]],
      %i[type u16],
      %i[machine u16],
      %i[version u32],
      %i[entry u64],
      %i[phoff u64],
      %i[shoff u64],
      %i[flags u32],
      %i[ehsize u16],
      %i[phentsize u16],
      %i[phnum u16],
      %i[shentsize u16],
      %i[shnum u16],
      %i[shstrndx u16]
    ]
  )
end

@doc """
section_layout: `Elf64_Shdr`.

    width(section_layout) #=> 64
"""
def section_layout()
  layout(
    [
      %i[name u32],
      %i[type u32],
      %i[flags u64],
      %i[addr u64],
      %i[offset u64],
      %i[size u64],
      %i[link u32],
      %i[info u32],
      %i[addralign u64],
      %i[entsize u64]
    ]
  )
end

@doc """
symbol_layout: `Elf64_Sym`.

    width(symbol_layout) #=> 24
"""
def symbol_layout()
  layout(
    [
      %i[name u32],
      %i[info u8],
      %i[other u8],
      %i[shndx u16],
      %i[value u64],
      %i[size u64]
    ]
  )
end

@doc """
rel_layout: `Elf64_Rel`.

    width(rel_layout) #=> 16
"""
def rel_layout()
  layout([%i[offset u64], %i[info u64]])
end

@doc """
ident_bytes: an ELF's first 16 bytes: its magic, 64-bit, little-endian, version 1.

    first(ident_bytes) #=> 127
    size(ident_bytes) #=> 16
"""
def ident_bytes()
  append([127, 69, 76, 70, 2, 1, 1], repeat(0, 9))
end

@doc """
kind_number: the number of a section's type, a symbol's type or binding, or a relocation, from each table in `elf.h` and `llvm/BinaryFormat/ELFRelocs/BPF.def`.

    kind_number(:section_type, :rel) #=> 9
    kind_number(:binding, :global) #=> 1
    kind_number(:reloc, :call) #=> 10
    (kind_number(:binding, :nope) rescue :refused) #=> :refused
"""
def kind_number(table, name)
  rows = case table
  when :section_type
    {
      null: 0,
      progbits: 1,
      symtab: 2,
      strtab: 3,
      rel: 9,
      llvm_addrsig: 1_879_002_115
    }
  when :binding
    {local: 0, global: 1, weak: 2}
  when :symbol_type
    {notype: 0, object: 1, func: 2, section: 3, file: 4}
  when :reloc
    {none: 0, map: 1, abs64: 2, abs32: 3, nodyld32: 4, call: 10}
  end
  got = get(rows, name)
  if got.nil?
    raise(:bad_option, "no #{to_s(table)} #{to_s(name)}")
  end
  got
end

@doc """
section_flags: a section's flags from the names of its bits.

    section_flags([:alloc, :exec]) #=> 6
    section_flags([]) #=> 0
"""
def section_flags(names)
  reduce(
    fn(acc, flag)
      bit = case flag
      when :write
        1
      when :alloc
        2
      when :exec
        4
      when :info_link
        64
      else
        raise(:bad_option, "no section flag #{to_s(flag)}")
      end
      bit_or(acc, bit)
    end,
    0,
    names
  )
end

@doc """
symbols_ordered: a symbol table's order: every local before every global, as ELF requires.

    map((s) -> s[:name], symbols_ordered([{name: "g", bind: :global}, {name: "l", bind: :local}])) #=> ["l", "g"]
    symbols_ordered([]) #=> []
"""
def symbols_ordered(symbols)
  append(
    filter((s) -> s[:bind] == :local, symbols),
    filter((s) -> s[:bind] != :local, symbols)
  )
end

@doc """
section_named: the index of a section by name among those given, the null section being 0; a name that is none raises.

    section_named([{name: "a"}, {name: "b"}], "b") #=> 2
    (section_named([], "b") rescue :refused) #=> :refused
"""
def section_named(sections, name)
  at = index_of(map((s) -> s[:name], sections), name)
  if at < 0
    raise(:bad_option, "no section #{name}")
  end
  at + 1
end

@doc """
symbol_bytes: one symbol's record, its name from the string table and its section by index.

    size(symbol_bytes({name: "a", bind: :global, type: :func, section: "s", value: 0, size: 8}, {offsets: {"a" => 1}}, [{name: "s"}])) #=> 24
"""
def symbol_bytes(s, strings, sections)
  shown = if s[:type] == :section
    0
  else
    get(strings[:offsets], s[:name])
  end
  pack(
    symbol_layout,
    {
      name: shown,
      info: bit_or(
        shift_left(kind_number(:binding, s[:bind]), 4),
        kind_number(:symbol_type, s[:type])
      ),
      other: 0,
      shndx: section_named(sections, s[:section]),
      value: s[:value],
      size: s[:size]
    }
  )
end

@doc """
rel_bytes: one relocation's record: {at:, symbol:, type:}, the symbol by name among those placed. A symbol that is none raises.

    size(rel_bytes({at: 8, symbol: "m", type: :map}, [{name: "m"}])) #=> 16
    (rel_bytes({at: 8, symbol: "x", type: :map}, []) rescue :refused) #=> :refused
"""
def rel_bytes(r, ordered)
  at = index_of(map((s) -> s[:name], ordered), r[:symbol])
  if at < 0
    raise(
      :bad_option,
      "a relocation names the symbol #{r[:symbol]}, which is not there"
    )
  end
  pack(
    rel_layout,
    {
      offset: r[:at],
      info: bit_or(shift_left(at + 1, 32), kind_number(:reloc, r[:type]))
    }
  )
end

@doc """
placed_section: one section with its offset, the bytes before it padded to its alignment.

    placed_section({at: 65, body: []}, {name: "s", align: 8, bytes: [1]}).at #=> 73
"""
def placed_section(acc, s)
  from = align_up(acc[:at], s[:align])
  gap = repeat(0, from - acc[:at])
  {
    at: from + length(s[:bytes]),
    body: append(acc[:body], [gap, s[:bytes]]),
    rows: append(acc[:rows] or [], [assoc(s, :offset, from)])
  }
end

@doc """
section_record: one section's header.

    size(section_record({name: "s", type: :progbits, flags: [], bytes: [], offset: 64, align: 1}, {offsets: {"s" => 1}}, [])) #=> 64
"""
def section_record(s, strings, sections)
  link = if s[:link_to] != nil
    section_named(sections, s[:link_to])
  else
    0
  end
  info = if s[:info_to] != nil
    section_named(sections, s[:info_to])
  else
    s[:info] or 0
  end
  pack(
    section_layout,
    {
      name: get(strings[:offsets], s[:name]),
      type: kind_number(:section_type, s[:type]),
      flags: section_flags(s[:flags] or []),
      addr: 0,
      offset: s[:offset],
      size: length(s[:bytes]),
      link:,
      info:,
      addralign: s[:align],
      entsize: s[:entsize] or 0
    }
  )
end

@doc """
encode: sections and symbols as an ELF object's bytes, with its `.strtab` first and its `.symtab` last. A section is {name:, type:, flags:, align:, bytes:}, or a relocation section {name:, target:, rels: [{at:, symbol:, type:}]}; a symbol is {name:, bind:, type:, section:, value:, size:}. A name a relocation or a symbol reaches that is not there raises.

    decode(encode([], []))[:sections] != [] #=> true
    section_of(decode(encode([{name: "s", type: :progbits, flags: [:alloc], align: 4, bytes: [1, 2, 3, 4]}], [])), "s")[:bytes] #=> [1, 2, 3, 4]
"""
def encode(sections, symbols)
  ordered = symbols_ordered(symbols)
  shown_rels = map(
    fn(s)
      if s[:rels].nil?
        s
      else
        {
          name: s[:name],
          type: :rel,
          flags: [:info_link],
          align: 8,
          entsize: width(rel_layout),
          link_to: ".symtab",
          info_to: s[:target],
          bytes: flat_map(s[:rels], (r) -> rel_bytes(r, ordered))
        }
      end
    end,
    sections
  )
  names = append(
    *[
      %w[.strtab .symtab],
      map((s) -> s[:name], shown_rels),
      map((s) -> s[:name], filter((s) -> s[:type] != :section, ordered))
    ]
  )
  strings = kaaneru::btf::strings_of([], names)
  skeleton = append(
    *[
      [
        {
          name: ".strtab",
          type: :strtab,
          flags: [],
          align: 1,
          bytes: strings[:bytes]
        }
      ],
      shown_rels,
      [{name: ".symtab", type: :symtab, flags: [], align: 8, bytes: []}]
    ]
  )
  symtab = {
    name: ".symtab",
    type: :symtab,
    flags: [],
    align: 8,
    entsize: width(symbol_layout),
    link_to: ".strtab",
    info: 1 + size(filter((s) -> s[:bind] == :local, ordered)),
    bytes: append(
      repeat(0, width(symbol_layout)),
      flat_map(ordered, (s) -> symbol_bytes(s, strings, skeleton))
    )
  }
  whole = append(take(size(skeleton) - 1, skeleton), [symtab])
  laid = reduce(placed_section, {at: width(header_layout), body: []}, whole)
  shoff = align_up(laid[:at], 8)
  headers = flat_map(laid[:rows], (s) -> section_record(s, strings, whole))
  append(
    *[
      pack(
        header_layout,
        {
          ident: ident_bytes,
          type: 1,
          machine: 247,
          version: 1,
          entry: 0,
          phoff: 0,
          shoff:,
          flags: 0,
          ehsize: width(header_layout),
          phentsize: 0,
          phnum: 0,
          shentsize: width(section_layout),
          shnum: size(whole) + 1,
          shstrndx: 1
        }
      ),
      flat_map(laid[:body], (b) -> b),
      repeat(0, shoff - laid[:at]),
      repeat(0, width(section_layout)),
      headers
    ]
  )
end

@doc """
text_at: the text at an offset in a string section; an offset past it is empty.

    text_at([0, 97, 0], 1) #=> "a"
    text_at([0], 9) #=> ""
"""
def text_at(strings, at)
  if at >= length(strings)
    ""
  else
    text_of(map((i) -> strings[at + i], range(0, length(strings) - at)))
  end
end

@doc """
decode: an ELF64 little-endian object's bytes as {header:, sections:, symbols:, rels:}. `rels` has each section's relocations by its name, each {at:, symbol:, type:, value:}. Bytes that are no such object, or that run short, raise :decode_error.

    size(decode(encode([], []))[:sections]) #=> 3
    (decode([1, 2, 3]) rescue :refused) #=> :refused
    (decode(map((_i) -> 0, range(0, 64))) rescue :refused) #=> :refused
"""
def decode(bytes)
  if length(bytes) < width(header_layout) or
      slice_bytes(bytes, 0, 4) != [127, 69, 76, 70]
    raise(:decode_error, "these bytes are not ELF")
  end
  if bytes[4] != 2 or bytes[5] != 1
    raise(:decode_error, "this ELF is not 64-bit little-endian")
  end
  head = unpack(header_layout, bytes, 0)
  raw = map(
    fn(i)
      unpack(section_layout, bytes, head[:shoff] + i * width(section_layout))
    end,
    range(0, head[:shnum])
  )
  strings = slice_bytes(
    bytes,
    raw[head[:shstrndx]][:offset],
    raw[head[:shstrndx]][:size]
  )
  sections = map(
    fn(row)
      index = first(row)
      s = row[1]
      {
        index:,
        name: text_at(strings, s[:name]),
        type: s[:type],
        flags: s[:flags],
        offset: s[:offset],
        size: s[:size],
        link: s[:link],
        info: s[:info],
        align: s[:addralign],
        entsize: s[:entsize],
        bytes: if s[:type] == 0 or s[:type] == 8
          []
        else
          slice_bytes(bytes, s[:offset], s[:size])
        end
      }
    end,
    zip(range(0, size(raw)), raw)
  )
  symbols = symbols_of(sections)
  {header: head, sections:, symbols:, rels: rels_of(sections, symbols)}
end

@doc """
symbols_of: a decoded object's symbols, the null symbol kept so that indexes hold.

    symbols_of([]) #=> []
"""
def symbols_of(sections)
  table = find(sections, (s) -> s[:type] == 2)
  if table.nil?
    []
  else
    names = sections[table[:link]][:bytes]
    count = floor(table[:size] / width(symbol_layout))
    map((i) -> symbol_read(table[:bytes], i, names, sections), range(0, count))
  end
end

@doc """
symbol_read: one symbol of a table: its section by name, a section symbol named for its section.

    symbol_read(repeat(0, 24), 0, [0], [{name: "", index: 0}])[:bind] #=> :local
"""
def symbol_read(bytes, i, names, sections)
  row = unpack(symbol_layout, bytes, i * width(symbol_layout))
  type = bit_and(row[:info], 15)
  in_section = if row[:shndx] < size(sections)
    sections[row[:shndx]][:name]
  else
    ""
  end
  {
    name: if type == 3
      in_section
    else
      text_at(names, row[:name])
    end,
    bind: if shift_right(row[:info], 4) == 0
      :local
    else
      :global
    end,
    type: case type
    when 1
      :object
    when 2
      :func
    when 3
      :section
    when 4
      :file
    else
      :notype
    end,
    section: in_section,
    value: row[:value],
    size: row[:size]
  }
end

@doc """
rels_of: each relocation section's records, by the name of the section they apply to.

    rels_of([], []) #=> {}
"""
def rels_of(sections, symbols)
  reduce(
    fn(acc, s)
      if s[:type] != 9
        acc
      else
        rows = map(
          fn(i)
            r = unpack(rel_layout, s[:bytes], i * width(rel_layout))
            sym = symbols[shift_right_logical(r[:info], 32)]
            {
              at: r[:offset],
              symbol: sym[:name],
              type: bit_and(r[:info], 4_294_967_295),
              sym:
            }
          end,
          range(0, floor(s[:size] / width(rel_layout)))
        )
        assoc(acc, sections[s[:info]][:name], rows)
      end
    end,
    {},
    sections
  )
end

@doc """
section_of: a decoded object's section by name, nil when it has none.

    section_of(decode(encode([], [])), ".strtab")[:type] #=> 3
    section_of(decode(encode([], [])), "x").nil? #=> true
"""
def section_of(o, name)
  find(o[:sections], (s) -> s[:name] == name)
end

@doc """
functions_of: a program's functions, or for a bare assembled one the one function it is. A program with no name is `blue`.

    first(functions_of({name: "p"}))[:name] #=> "p"
    first(functions_of({funcs: [{name: "f"}]}))[:name] #=> "f"
"""
def functions_of(p)
  if p[:funcs] != nil
    p[:funcs]
  else
    [
      {
        name: p[:name] or "blue",
        at: 0,
        linkage: :global,
        params: [:ctx],
        ret: :int
      }
    ]
  end
end

@doc """
split_at: the slots each function of a program starts and ends at: the entry's section, then `.text`.

    split_at({slots: 5}, [{at: 0}, {at: 3}]) #=> 3
    split_at({slots: 5}, [{at: 0}]) #=> 5
"""
def split_at(p, funcs)
  if size(funcs) > 1
    funcs[1][:at]
  else
    p[:slots]
  end
end

@doc """
function_at: the function that starts at a slot, nil when none does.

    function_at([{at: 3, name: "f"}], 3)[:name] #=> "f"
    function_at([], 3).nil? #=> true
"""
def function_at(funcs, slot)
  first(filter((f) -> f[:at] == slot, funcs))
end

@doc """
relocated: one instruction as the object holds it, and its relocation: a map reference holds nothing until libbpf gives it a descriptor, a reference into a map's value holds its offset, a global call holds -1 and names its target, a reference to a static function names `.text` and holds the place in it, and a kernel field's instruction holds its local offset, which libbpf moves.

    relocated(kaaneru::bpf::map_ref(1, :m), 2, {funcs: [], text_from: 9, relocs: {2 => "m"}}).rel #=> {at: 2, symbol: "m", type: :map}
    relocated(kaaneru::bpf::exit_program, 0, {funcs: [], text_from: 9, relocs: {}})[:rel].nil? #=> true
"""
def relocated(i, slot, world)
  mapped = get(world[:relocs], slot)
  if mapped != nil
    {
      insn: if i[:src] == 2
        assoc(assoc(assoc(i, :src, 0), :imm, i[:imm2]), :imm2, 0)
      else
        assoc(assoc(i, :src, 0), :imm, 0)
      end,
      rel: {at: slot, symbol: mapped, type: :map}
    }
  elsif get(world[:field_offsets] or {}, slot) != nil
    {insn: assoc(i, :imm, get(world[:field_offsets], slot))}
  elsif i[:code] == 133 and i[:src] == 1
    relocated_call(i, slot, world)
  elsif i[:code] == 24 and i[:src] == 4
    target = slot + 1 + i[:imm] - world[:text_from]
    {
      insn: assoc(i, :imm, target * 8),
      rel: {at: slot, symbol: ".text", type: :map}
    }
  else
    {insn: i}
  end
end

@doc """
relocated_call: a call as the object holds it. A global function is named; a static one in the same section stays relative.

    relocated_call(kaaneru::bpf::call_local(0), 0, {funcs: [{at: 1, name: "f", linkage: :global}], text_from: 1}).rel.symbol #=> "f"
    (relocated_call(kaaneru::bpf::call_local(0), 0, {funcs: [], text_from: 1}) rescue :refused) #=> :refused
"""
def relocated_call(i, slot, world)
  to = slot + 1 + (i[:imm] or 0)
  callee = function_at(world[:funcs], to)
  if callee.nil?
    raise(:bad_option, "a call at slot #{to_s(slot)} reaches no function")
  end
  if callee[:linkage] == :global
    {
      insn: assoc(i, :imm, -1),
      rel: {at: slot, symbol: callee[:name], type: :call}
    }
  elsif slot >= world[:text_from]
    {insn: i}
  else
    {
      insn: assoc(i, :imm, to - world[:text_from] - 1),
      rel: {at: slot, symbol: ".text", type: :call}
    }
  end
end

@doc """
coded: a run of instructions as the bytes a section holds and its relocations, each `at` in bytes from the section's start.

    coded([kaaneru::bpf::exit_program], 0, {funcs: [], text_from: 9, relocs: {}}).rels #=> []
    size(coded([kaaneru::bpf::exit_program], 0, {funcs: [], text_from: 9, relocs: {}}).bytes) #=> 8
"""
def coded(insns, from, world)
  got = reduce(
    fn(acc, i)
      r = relocated(i, acc[:slot], world)
      {
        slot: acc[:slot] + kaaneru::bpf::slots_of(i),
        chunks: append(acc[:chunks], [kaaneru::bpf::encode_insn(r[:insn])]),
        rels: if r[:rel].nil?
          acc[:rels]
        else
          append(acc[:rels], [assoc(r[:rel], :at, (r[:rel][:at] - from) * 8)])
        end
      }
    end,
    {slot: from, chunks: [], rels: []},
    insns
  )
  {bytes: flat_map(got[:chunks], (c) -> c), rels: got[:rels]}
end

@doc """
slot_split: instructions before a slot and from it.

    size(first(slot_split([kaaneru::bpf::exit_program, kaaneru::bpf::exit_program], 1))) #=> 1
    slot_split([], 0) #=> [[], []]
"""
def slot_split(insns, at)
  got = reduce(
    fn(acc, i)
      if acc[:slot] < at
        {
          slot: acc[:slot] + kaaneru::bpf::slots_of(i),
          early: append(acc[:early], [i]),
          late: acc[:late]
        }
      else
        {
          slot: acc[:slot] + kaaneru::bpf::slots_of(i),
          early: acc[:early],
          late: append(acc[:late], [i])
        }
      end
    end,
    {slot: 0, early: [], late: []},
    insns
  )
  [got[:early], got[:late]]
end

@doc """
function_symbols: each function's symbol: the entry's in its section, the rest in `.text`, each sized to the next.

    first(function_symbols([{name: "e", at: 0, linkage: :global}], 3, "xdp"))[:size] #=> 24
    function_symbols([], 3, "xdp") #=> []
"""
def function_symbols(funcs, slots, section)
  map(
    fn(row)
      at = first(row)
      f = row[1]
      next_at = if at + 1 < size(funcs)
        funcs[at + 1][:at]
      else
        slots
      end
      text_from = if size(funcs) > 1
        funcs[1][:at]
      else
        slots
      end
      {
        name: f[:name],
        bind: if f[:linkage] == :global
          :global
        else
          :local
        end,
        type: :func,
        section: if at == 0
          section
        else
          ".text"
        end,
        value: if at == 0
          0
        else
          (f[:at] - text_from) * 8
        end,
        size: (next_at - f[:at]) * 8
      }
    end,
    zip(range(0, size(funcs)), funcs)
  )
end

@doc """
map_symbols: each map's symbol, at its place in `.maps`.

    map_symbols([kaaneru::bpf::declare_map(:m, :array, 4, 8, 1)], {"m" => {size: 32}})[0][:value] #=> 0
    map_symbols([], {}) #=> []
"""
def map_symbols(maps, vars)
  get(
    reduce(
      fn(acc, m)
        var = get(vars, to_s(m[:name]))
        {
          at: acc[:at] + var[:size],
          rows: append(
            acc[:rows],
            [
              {
                name: to_s(m[:name]),
                bind: :global,
                type: :object,
                section: ".maps",
                value: acc[:at],
                size: var[:size]
              }
            ]
          )
        }
      end,
      {at: 0, rows: []},
      maps
    ),
    :rows
  )
end

@doc """
object: a compiled or assembled program as an ELF object's bytes, in the shape clang gives the same program: the entry in the section libbpf names its type by, subprograms in `.text`, maps in `.maps`, `license`, `.BTF` and `.BTF.ext`. `opts` takes {section:} for a program whose section names a target, such as "fentry/do_sys_openat2", {license:}, and {line_info: false} to leave out the source lines `.BTF.ext` holds by default. {core: false} refuses a program whose kernel fields are unbound, where by default each is a CO-RE relocation libbpf moves to the running kernel's offset. A map a program references by value becomes its own `.data.NAME` section, as libbpf reads global data.

    size(object(kaaneru::bpf::assemble([kaaneru::bpf::exit_program]), {section: "xdp"})) > 64 #=> true
    (object(assoc(kaaneru::bpf::assemble([]), :fields, [{}]), {section: "xdp"}) rescue :refused) #=> :refused
"""
def object(p, opts?)
  given = opts or {}
  if (p[:fields] or []) != [] and given[:core] == false
    raise(
      :bad_option,
      "this program reads kernel fields and {core: false} leaves CO-RE relocations out: bind them first with kaaneru::bpf::bind_fields"
    )
  end
  by_value = value_maps(p)
  plain_maps = filter((m) -> not member?(m, by_value), p[:maps] or [])
  kind = p[:kind] or :xdp
  section = given[:section] or kaaneru::bpf::section_name(kind)
  funcs = functions_of(p)
  maps = plain_maps
  shaped = reduce(
    (acc, row) -> assoc(acc, first(row), row[1]),
    p,
    [
      [:funcs, funcs],
      [:kind, kind],
      [:license, given[:license] or "GPL"],
      [:maps, plain_maps],
      [:data_maps, by_value]
    ]
  )
  types = kaaneru::bpf::program_btf(
    if given[:line_info] == false
      assoc(shaped, :lines, [])
    else
      shaped
    end
  )
  boundary = split_at(p, funcs)
  world = {
    funcs:,
    text_from: boundary,
    field_offsets: types[:field_offsets],
    relocs: reduce(
      (acc, r) -> assoc(acc, r[:at], to_s(r[:map])),
      {},
      p[:relocs] or []
    )
  }
  parts = slot_split(p[:insns], boundary)
  main = coded(first(parts), 0, world)
  text = coded(parts[1], boundary, world)
  license = append(text_bytes(given[:license] or "GPL"), [0])
  map_bytes = reduce(
    (acc, m) -> acc + get(types[:map_vars], to_s(m[:name]))[:size],
    0,
    maps
  )
  uses_section = filter(
    (r) -> r[:symbol] == ".text",
    append(main[:rels], text[:rels])
  ) != []
  symbols = append(
    *[
      if uses_section
        [
          {
            name: ".text",
            bind: :local,
            type: :section,
            section: ".text",
            value: 0,
            size: 0
          }
        ]
      else
        []
      end,
      function_symbols(funcs, p[:slots], section),
      map_symbols(maps, types[:map_vars]),
      map(data_map_symbol, by_value),
      [
        {
          name: "_license",
          bind: :global,
          type: :object,
          section: "license",
          value: 0,
          size: length(license)
        }
      ]
    ]
  )
  sections = append(
    *[
      [
        {
          name: ".text",
          type: :progbits,
          flags: %i[alloc exec],
          align: if text[:bytes] == []
            4
          else
            8
          end,
          bytes: text[:bytes]
        },
        {
          name: section,
          type: :progbits,
          flags: %i[alloc exec],
          align: 8,
          bytes: main[:bytes]
        }
      ],
      if main[:rels] == []
        []
      else
        [{name: ".rel#{section}", target: section, rels: main[:rels]}]
      end,
      if text[:rels] == []
        []
      else
        [{name: ".rel.text", target: ".text", rels: text[:rels]}]
      end,
      [
        {
          name: "license",
          type: :progbits,
          flags: %i[write alloc],
          align: 1,
          bytes: license
        }
      ],
      if maps == []
        []
      else
        [
          {
            name: ".maps",
            type: :progbits,
            flags: %i[write alloc],
            align: 8,
            bytes: repeat(0, map_bytes)
          }
        ]
      end,
      map(data_map_part, by_value),
      [
        {
          name: ".BTF",
          type: :progbits,
          flags: [],
          align: 4,
          bytes: types_with_section(types, section)
        },
        {
          name: ".BTF.ext",
          type: :progbits,
          flags: [],
          align: 4,
          bytes: ext_with_section(types, section, funcs)
        }
      ]
    ]
  )
  encode(sections, symbols)
end

@doc """
value_maps: the maps a program holds a reference into, each a one-entry array, which is what libbpf can make from a section. One also named as a map, or of another shape, is refused by name.

    value_maps({insns: [], relocs: [], maps: []}) #=> []
    size(value_maps(kaaneru::bpf::assemble([kaaneru::bpf::exit_program]))) #=> 0
    (value_maps(assoc(kaaneru::bpf::assemble([kaaneru::bpf::map_value_ref(1, :m, 0)]), :maps, [kaaneru::bpf::declare_map(:m, :hash, 4, 8, 1)])) rescue :refused) #=> :refused
"""
def value_maps(p)
  placed = placed_rows(p[:insns])
  named = fn(want)
    shuugou::unique(
      map(
        (r) -> to_s(r[:map]),
        filter(
          fn(r)
            row = find(placed, (x) -> first(x) == r[:at])
            row != nil and want(row[1][:src] == 2)
          end,
          p[:relocs] or []
        )
      )
    )
  end
  valued = named((x) -> x)
  plain = named((x) -> not x)
  map(
    fn(name)
      m = find(p[:maps] or [], (x) -> to_s(x[:name]) == name)
      if m.nil?
        raise(
          :bad_option,
          "the program references the value of #{name}, which is not among its maps"
        )
      elsif member?(name, plain)
        raise(
          :bad_option,
          "an object cannot name #{name} both as a map and by a reference into its value: libbpf reads each from another section"
        )
      elsif m[:kind] != :array or m[:max_entries] != 1 or m[:key_size] != 4
        raise(
          :bad_option,
          "a reference into a map's value needs a one-entry array with a 4-byte key in an object, and #{name} is not one"
        )
      end
      m
    end,
    valued
  )
end

@doc """
data_map_part: the section a map referenced by value lives in, zero-filled.

    data_map_part(kaaneru::bpf::declare_map(:m, :array, 4, 8, 1)).name #=> ".data.m"
    size(data_map_part(kaaneru::bpf::declare_map(:m, :array, 4, 8, 1)).bytes) #=> 8
"""
def data_map_part(m)
  {
    name: kaaneru::bpf::data_map_place(m)[:section],
    type: :progbits,
    flags: %i[write alloc],
    align: 1,
    bytes: repeat(0, m[:value_size])
  }
end

@doc """
data_map_symbol: the symbol at the start of a map referenced by value.

    data_map_symbol(kaaneru::bpf::declare_map(:m, :array, 4, 8, 1)).size #=> 8
"""
def data_map_symbol(m)
  {
    name: to_s(m[:name]),
    bind: :global,
    type: :object,
    section: kaaneru::bpf::data_map_place(m)[:section],
    value: 0,
    size: m[:value_size]
  }
end

@doc """
types_with_section: the `.BTF` bytes, the entry's section among its strings.

    kaaneru::btf::read(types_with_section({types: [], names: []}, "xdp"))[:count] #=> 0
"""
def types_with_section(types, section)
  kaaneru::btf::encode(types[:types], append(types[:names], [section]))
end

@doc """
ext_with_section: the `.BTF.ext` bytes for an object whose entry sits in this section.

    size(ext_with_section({types: [], names: [], func_info: []}, "xdp", [])) #=> 32
"""
def ext_with_section(types, section, funcs)
  kaaneru::btf::encode_ext(
    types[:types],
    append(types[:names], [section]),
    kaaneru::bpf::func_info_sections(
      map((row) -> [first(row), row[1][:type]], zip(funcs, types[:func_info])),
      section
    ),
    kaaneru::bpf::line_info_sections(types[:lines] or [], funcs, section),
    kaaneru::bpf::core_sections(types[:core_relos] or [], funcs, section)
  )
end

@doc """
section_kind: the program type a section's name says, as libbpf reads it; nil for one this table has no row for.

    section_kind("xdp") #=> :xdp
    section_kind("fentry/do_sys_openat2") #=> :tracing
    section_kind("whatever").nil? #=> true
"""
def section_kind(name)
  case first(split(name, "/"))
  when "xdp"
    :xdp
  when "tc"
    :sched_cls
  when "socket"
    :socket_filter
  when "kprobe"
    :kprobe
  when "tracepoint"
    :tracepoint
  when "raw_tracepoint"
    :raw_tracepoint
  when "fentry"
    :tracing
  when "fexit"
    :tracing
  when "lsm"
    :lsm
  end
end

@doc """
map_rows: a BTF-defined map's members by name: an integer is a pointer to an array of that many, a type a pointer to it.

    map_rows(kaaneru::btf::read(kaaneru::btf::encode([])), {members: []}) #=> {}
"""
def map_rows(table, shape)
  reduce(
    fn(acc, m)
      target = kaaneru::btf::type_at(
        table,
        kaaneru::btf::type_at(table, m[:type])[:type]
      )
      if target[:kind] == :array
        assoc(acc, m[:name], target[:count])
      else
        assoc(
          assoc(acc, m[:name], kaaneru::btf::size_of(table, target[:id])),
          "#{m[:name]}_type",
          target[:id]
        )
      end
    end,
    {},
    shape[:members]
  )
end

@doc """
has_lock?: whether a value type holds a `struct bpf_spin_lock`.

    has_lock?(kaaneru::btf::read(kaaneru::btf::encode([])), nil) #=> false
"""
def has_lock?(table, id)
  if id.nil?
    false
  else
    t = kaaneru::btf::resolved(table, id)
    t[:kind] == :struct and
      filter(
        fn(m)
          kaaneru::btf::resolved(table, m[:type])[:name] == "bpf_spin_lock"
        end,
        t[:members]
      ) != []
  end
end

@doc """
map_of_var: the map shape a `.maps` variable declares.

    (map_of_var(kaaneru::btf::read(kaaneru::btf::encode([])), 1) rescue :refused) #=> :refused
"""
def map_of_var(table, var_id)
  var = kaaneru::btf::type_at(table, var_id)
  rows = map_rows(table, kaaneru::btf::resolved(table, var[:type]))
  value_type = rows["value_type"]
  shape = kaaneru::bpf::declare_map(
    var[:name],
    kaaneru::bpf::map_kinds[rows["type"]],
    rows["key"] or rows["key_size"] or 0,
    rows["value"] or rows["value_size"] or 0,
    rows["max_entries"] or 0
  )
  described = assoc(
    assoc(shape, :key_type, rows["key_type"]),
    :value_type,
    value_type
  )
  if has_lock?(table, value_type)
    assoc(described, :lock, true)
  else
    described
  end
end

@doc """
maps_of: the maps a decoded object's `.BTF` declares in `.maps`.

    maps_of(decode(object(kaaneru::bpf::assemble([kaaneru::bpf::exit_program]), {section: "xdp"}))) #=> []
"""
def maps_of(o)
  blob = section_of(o, ".BTF")
  if blob.nil?
    []
  else
    table = kaaneru::btf::read(blob[:bytes])
    id = kaaneru::btf::find(table, ".maps", :datasec)
    if id.nil?
      []
    else
      map(
        (v) -> map_of_var(table, v[:type]),
        kaaneru::btf::type_at(table, id)[:vars]
      )
    end
  end
end

@doc """
fixed_blob: the `.BTF` as the kernel takes it: a data section's size and each variable's place come from the object's symbols, as clang leaves them for libbpf to fill.

    kaaneru::btf::read(fixed_blob({sections: [{name: ".maps", size: 0}], symbols: []}, kaaneru::btf::encode([])))[:count] #=> 0
"""
def fixed_blob(o, blob)
  table = kaaneru::btf::read(blob)
  count = table[:count]
  words = reduce(
    fn(acc, id)
      t = kaaneru::btf::type_at(table, id)
      if t[:kind] == :datasec
        fixed_datasec(acc, o, table, t)
      else
        acc
      end
    end,
    table[:words],
    range(1, count + 1)
  )
  h = kaaneru::btf::header_of(blob)
  append(
    *[
      map((i) -> blob[i], range(0, h[:header])),
      flat_map(words, kaaneru::btf::word_bytes),
      map((i) -> blob[h[:str_off] + i], range(0, h[:str_len]))
    ]
  )
end

@doc """
fixed_datasec: type words with one data section's size and its variables' places filled in from symbols.

    fixed_datasec([], {sections: [], symbols: []}, kaaneru::btf::read(kaaneru::btf::encode([])), {name: ".x", id: 1, vars: []}) #=> []
"""
def fixed_datasec(words, o, table, t)
  at = get(table[:starts], t[:id])
  s = section_of(o, t[:name])
  sized = if s.nil?
    words
  else
    replaced(words, at + 2, s[:size])
  end
  reduce(
    fn(acc, row)
      i = first(row)
      v = row[1]
      name = kaaneru::btf::type_at(table, v[:type])[:name]
      sym = find(o[:symbols], (x) -> x[:name] == name)
      if sym.nil?
        acc
      else
        replaced(
          replaced(acc, at + 3 + i * 3 + 1, sym[:value]),
          at + 3 + i * 3 + 2,
          sym[:size]
        )
      end
    end,
    sized,
    zip(range(0, size(t[:vars])), t[:vars])
  )
end

@doc """
replaced: a list with the item at one place changed.

    replaced([1, 2], 1, 9) #=> [1, 9]
"""
def replaced(xs, at, value)
  map(
    fn(pair)
      if first(pair) == at
        value
      else
        pair[1]
      end
    end,
    zip(range(0, size(xs)), xs)
  )
end

@doc """
linked_rel: one instruction of a section given what its relocation names: a map named, a call or function reference made relative. `base` is where this section lands in the linked program, and `text_base` where `.text` does.

    linked_rel(kaaneru::bpf::exit_program, nil, 0, 0, 9).code #=> 149
    linked_rel(assoc(kaaneru::bpf::imm64(1, 0), :src, 0), {sym: {section: ".maps", name: "m", value: 0, type: :object}}, 0, 0, 9).map #=> "m"
"""
def linked_rel(i, rel, slot, _base, text_base)
  if rel.nil?
    i
  elsif rel[:sym][:section] == ".maps"
    assoc(assoc(i, :src, 1), :map, rel[:sym][:name])
  elsif i[:code] == 24 and starts_with?(rel[:sym][:section], ".data.")
    assoc(
      assoc(
        assoc(assoc(i, :src, 2), :imm2, i[:imm] + rel[:sym][:value]),
        :imm,
        0
      ),
      :map,
      after_data(rel[:sym][:section])
    )
  elsif i[:code] == 133
    to = floor(rel[:sym][:value] / 8) + i[:imm] + 1 + text_base
    assoc(i, :imm, to - slot - 1)
  elsif i[:code] == 24
    to = floor((rel[:sym][:value] + i[:imm]) / 8) + text_base
    assoc(assoc(i, :src, 4), :imm, to - slot - 1)
  else
    assoc(
      i,
      :unlinked,
      "a relocation at slot #{to_s(slot)} names #{rel[:symbol]}, which this reader cannot link"
    )
  end
end

@doc """
refused_unlinked: nil, or the refusal for an instruction still holding a relocation this reader could not link.

    refused_unlinked([kaaneru::bpf::exit_program]).nil? #=> true
    (refused_unlinked([{unlinked: "no"}]) rescue :refused) #=> :refused
"""
def refused_unlinked(insns)
  stuck = find(insns, (i) -> i[:unlinked] != nil)
  if stuck != nil
    raise(:bad_option, stuck[:unlinked])
  end
end

@doc """
after_data: the map a `.data.NAME` section is.

    after_data(".data.m") #=> "m"
"""
def after_data(section)
  join(drop(2, split(section, ".")), ".")
end

@doc """
data_maps_of: the one-entry array each zero-filled `.data.NAME` section of a decoded object is. A section holding other bytes needs its contents written at load, which this reader has no form for, so it is left out and a reference to it is refused when the array is not found.

    data_maps_of({sections: [{name: ".data.m", bytes: [0, 0, 0, 0]}]})[0][:value_size] #=> 4
    data_maps_of({sections: [{name: ".data.m", bytes: [1]}]}) #=> []
    data_maps_of({sections: []}) #=> []
"""
def data_maps_of(o)
  map(
    fn(s)
      kaaneru::bpf::declare_map(
        after_data(s[:name]),
        :array,
        4,
        size(s[:bytes]),
        1
      )
    end,
    filter(
      fn(s)
        starts_with?(s[:name], ".data.") and
          filter((b) -> b != 0, s[:bytes]) == []
      end,
      o[:sections]
    )
  )
end

@doc """
fields_of: a decoded object's CO-RE relocations as the fields `kaaneru::bpf::bind_fields` fills: each by its slot in a linked program, its struct and its member names from the object's own BTF. An instruction this linker cannot patch, or a kind other than a byte offset, is refused by name: reading on with the local offset would read the wrong field.

    fields_of({sections: []}, "xdp", 1) #=> []
"""
def fields_of(o, section, main_slots)
  blob = section_of(o, ".BTF")
  ext = section_of(o, ".BTF.ext")
  if blob.nil? or ext.nil?
    []
  else
    table = kaaneru::btf::read(blob[:bytes])
    flat_map(
      kaaneru::btf::read_core(ext[:bytes], blob[:bytes]),
      fn(s)
        base = if s[:section] == section
          0
        elsif s[:section] == ".text"
          main_slots
        end
        if base.nil?
          []
        else
          map(
            (r) -> field_of_core(table, r, base + floor(r[:at] / 8)),
            s[:relos]
          )
        end
      end
    )
  end
end

@doc """
field_of_core: one CO-RE relocation as a field. An anonymous member adds nothing to the path, as `kaaneru::btf::field` walks through it.

    (field_of_core(kaaneru::btf::read(kaaneru::btf::encode([])), {kind: 3, access: "0:0", type: 1}, 0) rescue :refused) #=> :refused
"""
def field_of_core(table, r, slot)
  if r[:kind] != 0
    raise(
      :bad_option,
      "a CO-RE relocation of kind #{to_s(r[:kind])} at slot #{to_s(slot)} is not a byte offset, the only kind this reader binds"
    )
  end
  walked = reduce(
    fn(acc, index)
      t = kaaneru::btf::resolved(table, acc[:type])
      m = t[:members][to_int(index)]
      {
        type: m[:type],
        path: if m[:name] == ""
          acc[:path]
        else
          append(acc[:path], [m[:name]])
        end
      }
    end,
    {type: r[:type], path: []},
    rest(split(r[:access], ":"))
  )
  {
    at: slot,
    struct: kaaneru::btf::resolved(table, r[:type])[:name],
    path: walked[:path],
    size: kaaneru::btf::size_of(table, walked[:type])
  }
end

@doc """
fields_patchable: the fields of a linked program, refusing one whose instruction holds its offset anywhere but an immediate.

    fields_patchable([], []) #=> []
    (fields_patchable([{at: 0, struct: "s", path: ["f"]}], [kaaneru::bpf::load(:w, 0, 1, 0)]) rescue :refused) #=> :refused
"""
def fields_patchable(fields, insns)
  rows = placed_rows(insns)
  map(
    fn(f)
      row = find(rows, (x) -> first(x) == f[:at])
      if row != nil and not member?(row[1][:code], [7, 183])
        raise(
          :bad_option,
          "#{f[:struct]}.#{join(f[:path], ".")} is relocated at an instruction that holds no immediate offset, which this reader cannot bind; bind it with libbpf"
        )
      end
      f
    end,
    fields
  )
end

@doc """
linked_section: a section's instructions placed from a slot, each relocation applied: {insns:, relocs:}.

    linked_section({bytes: [], name: "x"}, {}, 0, 0).insns #=> []
"""
def linked_section(s, rels, base, text_base)
  by_at = reduce(
    (acc, r) -> assoc(acc, r[:at], r),
    {},
    get(rels, s[:name]) or []
  )
  got = reduce(
    fn(acc, i)
      slot = acc[:slot]
      fixed = linked_rel(
        i,
        get(by_at, (slot - base) * 8),
        slot,
        base,
        text_base
      )
      {
        slot: slot + kaaneru::bpf::slots_of(i),
        insns: append(acc[:insns], [dissoc(fixed, :map)]),
        relocs: if fixed[:map] != nil
          append(acc[:relocs], [{at: slot, map: fixed[:map]}])
        else
          acc[:relocs]
        end
      }
    end,
    {slot: base, insns: [], relocs: []},
    kaaneru::bpf::decode(s[:bytes])
  )
  {insns: got[:insns], relocs: got[:relocs]}
end

@doc """
entry_section: the program section of a decoded object: the named one, or else the first that holds code and is not `.text`. None raises by name.

    entry_section({sections: [{name: "xdp", flags: 6, size: 8}]}, nil)[:name] #=> "xdp"
    (entry_section({sections: []}, nil) rescue :refused) #=> :refused
"""
def entry_section(o, name)
  found = if name != nil
    find(o[:sections], (s) -> s[:name] == name)
  else
    find(
      o[:sections],
      (s) -> s[:name] != ".text" and bit_and(s[:flags], 4) != 0 and s[:size] > 0
    )
  end
  if found.nil?
    raise(:not_found, "this object has no program section #{to_s(name)}")
  end
  found
end

@doc """
info_of: an object's func_info as the linked program's rows, each `at` by slot, and each row's function: {funcs:, func_info:}.

    info_of(decode(object(kaaneru::bpf::assemble([kaaneru::bpf::exit_program]), {section: "xdp"})), "xdp", 1)[:func_info] #=> [{at: 0, type: 6}]
"""
def info_of(o, section, main_slots)
  blob = section_of(o, ".BTF")
  ext = section_of(o, ".BTF.ext")
  if blob.nil? or ext.nil?
    {funcs: nil, func_info: []}
  else
    table = kaaneru::btf::read(blob[:bytes])
    rows = sort_keyed(
      (r) -> r[:at],
      flat_map(
        kaaneru::btf::read_ext(ext[:bytes], blob[:bytes]),
        fn(s)
          if s[:section] == section
            map((f) -> {at: floor(f[:at] / 8), type: f[:type]}, s[:funcs])
          elsif s[:section] == ".text"
            map(
              (f) -> {at: main_slots + floor(f[:at] / 8), type: f[:type]},
              s[:funcs]
            )
          else
            []
          end
        end
      )
    )
    {
      func_info: rows,
      funcs: map(
        fn(r)
          t = kaaneru::btf::type_at(table, r[:type])
          {
            name: t[:name],
            at: r[:at],
            linkage: if bit_and(t[:vlen], 3) == 1
              :global
            else
              :static
            end,
            type: r[:type]
          }
        end,
        rows
      )
    }
  end
end

@doc """
function_starts: the slots a linked program's functions start at, read from its func_info and its function symbols: the first slot, then each in `.text`, in order. An object that says nothing of `.text` has one function there.

    function_starts({symbols: []}, {funcs: nil}, 2) #=> [0, 2]
    function_starts({symbols: [{type: :func, section: ".text", value: 16}]}, {funcs: [{at: 2}]}, 2) #=> [0, 2, 4]
"""
def function_starts(o, info, main_slots)
  named = map(
    (f) -> main_slots + floor(f[:value] / 8),
    filter((f) -> f[:type] == :func and f[:section] == ".text", o[:symbols])
  )
  listed = map(
    (f) -> f[:at],
    filter((f) -> f[:at] >= main_slots, info[:funcs] or [])
  )
  sort_keyed(
    (n) -> n,
    shuugou::unique(append(*[[0, main_slots], named, listed]))
  )
end

@doc """
placed_rows: a program's instructions, each `[slot, instruction]`.

    placed_rows([kaaneru::bpf::imm64(1, 0), kaaneru::bpf::exit_program])[1][0] #=> 2
    placed_rows([]) #=> []
"""
def placed_rows(insns)
  get(
    reduce(
      fn(acc, i)
        {
          at: acc[:at] + kaaneru::bpf::slots_of(i),
          rows: append(acc[:rows], [[acc[:at], i]])
        }
      end,
      {at: 0, rows: []},
      insns
    ),
    :rows
  )
end

@doc """
reference_target: the slot an instruction calls or takes the address of in this program, nil for any other instruction.

    reference_target([2, kaaneru::bpf::call_local(:f)]) #=> 3
    reference_target([0, kaaneru::bpf::exit_program]).nil? #=> true
"""
def reference_target(row)
  i = row[1]
  if i[:code] == 133 and i[:src] == 1 or i[:code] == 24 and i[:src] == 4
    first(row) + 1 + i[:imm]
  end
end

@doc """
start_holding: the function start a slot falls in.

    start_holding([0, 2, 4], 3) #=> 2
    start_holding([0, 2, 4], 4) #=> 4
"""
def start_holding(starts, slot)
  last(filter((n) -> n <= slot, starts))
end

@doc """
reached_starts: the functions a program reaches from its first, by call or by reference.

    reached_starts([0], [[0, kaaneru::bpf::exit_program]]) #=> [0]
    reached_starts([], []) #=> []
"""
def reached_starts(starts, rows)
  if starts == []
    []
  else
    edges = filter(
      (e) -> e[1] != nil,
      map(
        (row) -> [start_holding(starts, first(row)), reference_target(row)],
        rows
      )
    )
    walked = reduce(
      fn(seen, _)
        shuugou::unique(
          append(
            seen,
            map(
              (e) -> start_holding(starts, e[1]),
              filter((e) -> member?(first(e), seen), edges)
            )
          )
        )
      end,
      [0],
      starts
    )
    filter((n) -> member?(n, walked), starts)
  end
end

@doc """
slot_after_drop: where a slot lands once only these functions stay: `kept` is each kept function's `[start, end]`.

    slot_after_drop([[0, 2], [4, 6]], 5) #=> 3
    slot_after_drop([[0, 2]], 1) #=> 1
"""
def slot_after_drop(kept, slot)
  reduce(
    fn(at, k)
      if slot >= k[1]
        at + k[1] - first(k)
      elsif slot >= first(k)
        at + slot - first(k)
      else
        at
      end
    end,
    0,
    kept
  )
end

@doc """
linked_only: a linked program with the functions nothing reaches removed, as libbpf links one: each call, reference, relocation and function row moved to its new slot. A program that reaches them all comes back as it was.

    linked_only({insns: [kaaneru::bpf::exit_program], relocs: [], slots: 1}, [0]).slots #=> 1
"""
def linked_only(program, starts)
  rows = placed_rows(program[:insns])
  stops = append(rest(starts), [program[:slots]])
  reached = reached_starts(starts, rows)
  if size(reached) == size(starts)
    program
  else
    kept = filter((k) -> member?(first(k), reached), zip(starts, stops))
    stays = (slot) -> member?(start_holding(starts, slot), reached)
    moved = (slot) -> slot_after_drop(kept, slot)
    moved_row = (f) -> assoc(f, :at, moved(f[:at]))
    insns = map(
      fn(row)
        target = reference_target(row)
        if target.nil?
          row[1]
        else
          assoc(row[1], :imm, moved(target) - moved(first(row)) - 1)
        end
      end,
      filter((row) -> stays(first(row)), rows)
    )
    funcs = if program[:funcs].nil?
      nil
    else
      map(moved_row, filter((f) -> stays(f[:at]), program[:funcs]))
    end
    types = if program[:btf].nil?
      nil
    else
      assoc(
        program[:btf],
        :func_info,
        map(moved_row, filter((f) -> stays(f[:at]), program[:btf][:func_info]))
      )
    end
    reduce(
      (acc, pair) -> assoc(acc, first(pair), pair[1]),
      program,
      [
        [:insns, insns],
        [
          :relocs,
          map(moved_row, filter((r) -> stays(r[:at]), program[:relocs]))
        ],
        [
          :fields,
          map(moved_row, filter((r) -> stays(r[:at]), program[:fields] or []))
        ],
        [:slots, moved(program[:slots])],
        [:funcs, funcs],
        [:btf, types]
      ]
    )
  end
end

@doc """
program_of: a decoded object linked into a program, as libbpf links one: the section named, or the first program section, then the functions of `.text` it reaches; a function nothing reaches is dropped, where the verifier would refuse it. `opts` {keep_unreached: true} links the whole of `.text` when anything reaches it. Its maps, functions and BTF come from the object, and a program type its section does not name is nil. An object for another machine raises.

    kaaneru::bpf::run(program_of(decode(object(kaaneru::bpf::assemble([kaaneru::bpf::alu(:mov, 0, 3), kaaneru::bpf::exit_program]), {section: "xdp"})))).ret #=> 3
    (program_of(assoc_machine(decode(encode([], [])))) rescue :refused) #=> :refused
"""
def program_of(o, name?, opts?)
  if o[:header][:machine] != 247
    raise(
      :bad_option,
      "this object is for machine #{to_s(o[:header][:machine])}, not BPF"
    )
  end
  given = opts or {}
  s = entry_section(o, name)
  main_slots = floor(s[:size] / 8)
  rels = o[:rels]
  text = section_of(o, ".text")
  reaches_text = text != nil and
    text[:size] > 0 and
    (
      not given[:keep_unreached] or
      filter(
        (r) -> r[:sym][:section] == ".text",
        append(get(rels, s[:name]) or [], rels[".text"] or [])
      ) != []
    )
  main = linked_section(s, rels, 0, main_slots)
  sub = if reaches_text
    linked_section(text, rels, main_slots, main_slots)
  else
    {insns: [], relocs: []}
  end
  info = info_of(o, s[:name], main_slots)
  keep = if reaches_text
    info[:func_info]
  else
    filter((f) -> f[:at] < main_slots, info[:func_info])
  end
  maps = append(maps_of(o), data_maps_of(o))
  blob = section_of(o, ".BTF")
  whole = {
    insns: append(main[:insns], sub[:insns]),
    relocs: append(main[:relocs], sub[:relocs]),
    fields: fields_of(o, s[:name], main_slots),
    slots: main_slots +
      if reaches_text
        floor(text[:size] / 8)
      else
        0
      end,
    labels: {},
    maps:,
    kind: section_kind(s[:name]),
    name: s[:name],
    funcs: if info[:funcs].nil?
      nil
    else
      filter((f) -> f[:at] < main_slots or reaches_text, info[:funcs])
    end,
    btf: if blob.nil?
      nil
    else
      {
        bytes: fixed_blob(o, blob[:bytes]),
        func_info: keep,
        map_types: reduce(
          fn(acc, m)
            assoc(
              acc,
              to_s(m[:name]),
              {key: m[:key_type], value: m[:value_type]}
            )
          end,
          {},
          maps
        )
      }
    end
  }
  linked = if given[:keep_unreached] or not reaches_text
    whole
  else
    linked_only(whole, function_starts(o, info, main_slots))
  end
  refused_unlinked(linked[:insns])
  fields_patchable(linked[:fields], linked[:insns])
  linked
end

@doc """
assoc_machine: a decoded object said to be for another machine, to show `program_of` refuses it.

    assoc_machine({header: {}})[:header][:machine] #=> 62
"""
def assoc_machine(o)
  assoc(o, :header, assoc(o[:header], :machine, 62))
end

@doc """
sample_program: a compiled program with a map and a global subprogram, for tests and examples.

    size(sample_program[:funcs]) #=> 2
"""
def sample_program()
  compiled = kaaneru::bpf::compile_forms(
    read_forms("(define %root/M (kaaneru/bpf/declare_map :counts :array 4 8 4)) (define (%root/g a b) (+ a b)) (define (%root/e c) (begin (kaaneru/bpf/map_add %root/M 1 2) (%root/g 40 2)))"),
    {entry: :e, kind: :xdp, on_fault: 0, global: [:g]}
  )
  compiled
end

test "an empty program has an empty section and nothing else breaks"
  bytes = object(kaaneru::bpf::assemble([]), {section: "xdp"})
  o = decode(bytes)
  assert section_of(o, "xdp")[:size] == 0
  assert section_of(o, ".text")[:size] == 0
  assert section_of(o, ".maps").nil?
  assert maps_of(o) == []
end

test "a written object reads back: the same instructions, relocations, maps and functions"
  p = sample_program
  o = decode(object(p))
  back = program_of(o)
  assert kaaneru::bpf::encode(back) == kaaneru::bpf::encode(p)
  assert size(back[:funcs]) == 2
  assert map((f) -> f[:name], back[:funcs]) == %w[e g]
  assert first(back[:maps])[:name] == "counts"
  assert first(back[:maps])[:kind] == :array
  assert first(back[:maps])[:value_size] == 8
  assert first(back[:relocs])[:map] == "counts"
  assert back[:kind] == :xdp
  assert kaaneru::bpf::run(back, {maps: back[:maps]}).ret == 42
  assert kaaneru::bpf::run(p, {maps: p[:maps]}).ret == 42
end

test "the bytes of the header and of a relocation are those the format states, checked by hand"
  o = object(
    assoc(
      kaaneru::bpf::assemble(
        [kaaneru::bpf::map_ref(1, :m), kaaneru::bpf::exit_program]
      ),
      :maps,
      [kaaneru::bpf::declare_map(:m, :array, 4, 8, 1)]
    ),
    {section: "xdp", license: "GPL"}
  )
  assert slice_bytes(o, 0, 8) == [127, 69, 76, 70, 2, 1, 1, 0]
  assert slice_bytes(o, 16, 4) == [1, 0, 247, 0]
  assert slice_bytes(o, 52, 2) == [64, 0]
  assert slice_bytes(o, 58, 2) == [64, 0]
  decoded = decode(o)
  assert section_of(decoded, "license")[:bytes] == [71, 80, 76, 0]
  assert section_of(decoded, "xdp")[:flags] == 6
  assert section_of(decoded, ".text")[:align] == 4
  assert section_of(decoded, ".relxdp").nil? == false
  assert section_of(decoded, ".relxdp")[:info] ==
    section_of(decoded, "xdp")[:index]
  assert section_of(decoded, ".relxdp")[:entsize] == 16
  rel = first(decoded[:rels]["xdp"])
  assert rel[:at] == 0
  assert rel[:type] == 1
  assert slice_bytes(section_of(decoded, "xdp")[:bytes], 0, 8) ==
    [24, 1, 0, 0, 0, 0, 0, 0]
end

test "a global call holds -1 and names its target, and symbols order locals first"
  p = sample_program
  o = decode(object(p))
  calls = o[:rels]["xdp"]
  named = find(calls, (r) -> r[:symbol] == "g")
  assert named[:type] == 10
  at = floor(named[:at] / 8)
  called = kaaneru::bpf::decode(section_of(o, "xdp")[:bytes])
  assert get(kaaneru::bpf::slot_table(called), at)[:imm] == -1
  symtab = section_of(o, ".symtab")
  assert symtab[:info] == 1
  assert first(rest(o[:symbols]))[:bind] == :global
  assert map((s) -> s[:name], rest(o[:symbols])) == %w[e g counts _license]
end

test "a static callback is reached through .text, and a reader links it back"
  p = kaaneru::bpf::with_funcs(
    kaaneru::bpf::assemble(
      [
        kaaneru::bpf::alu(:mov, 1, 3),
        kaaneru::bpf::func_ref(2, :cb),
        kaaneru::bpf::alu(:mov, 3, 0),
        kaaneru::bpf::alu(:mov, 4, 0),
        kaaneru::bpf::call(:loop),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:cb),
        kaaneru::bpf::alu(:mov, 0, 0),
        kaaneru::bpf::exit_program
      ]
    ),
    [
      {name: "e", linkage: :global, params: [:ctx]},
      {name: "cb", label: :cb, linkage: :static, params: %i[int int]}
    ]
  )
  back = program_of(decode(object(assoc(p, :kind, :xdp))))
  assert kaaneru::bpf::encode(back) == kaaneru::bpf::encode(p)
  assert kaaneru::bpf::run(back).ret == 3
end

test "a kernel field in an object holds its local offset, its relocation reads back, and a reader binds it as bind_fields does"
  p = assoc(
    kaaneru::bpf::assemble(
      [
        assoc(
          kaaneru::bpf::alu(:add, 3, 0),
          :field,
          {struct: "task", path: ["pid"], size: 4}
        ),
        assoc(
          kaaneru::bpf::alu(:add, 3, 0),
          :field,
          {struct: "task", path: ["tgid"], size: 4}
        ),
        kaaneru::bpf::exit_program
      ]
    ),
    :kind,
    :tracing
  )
  o = decode(object(p, {section: "fentry/x"}))
  got = kaaneru::btf::read_core(
    section_of(o, ".BTF.ext")[:bytes],
    section_of(o, ".BTF")[:bytes]
  )
  assert first(got)[:section] == "fentry/x"
  assert map((r) -> [r[:at], r[:access], r[:kind]], first(got)[:relos]) ==
    [[0, "0:0", 0], [8, "0:1", 0]]
  held = kaaneru::bpf::decode(section_of(o, "fentry/x")[:bytes])
  assert map((i) -> i[:imm], take(2, held)) == [0, 4]
  back = program_of(o)
  assert map((f) -> f[:path], back[:fields]) == [["pid"], ["tgid"]]
  assert first(back[:fields])[:struct] == "task"
  assert first(back[:fields])[:size] == 4
  bound = kaaneru::bpf::bind_fields(
    back,
    fn(_s, path)
      if path == ["pid"]
        {offset: 100, size: 4}
      else
        {offset: 200, size: 4}
      end
    end
  )
  assert map((i) -> i[:imm], take(2, bound[:insns])) == [100, 200]
  assert bound[:fields] == []
end

test "a CO-RE relocation at an instruction with no immediate, or of another kind, stops the reader by name"
  assert (fields_patchable(
    [{at: 0, struct: "s", path: ["f"]}],
    [kaaneru::bpf::load(:w, 0, 1, 0)]
  ) rescue
    :refused) == :refused
  good = fields_patchable(
    [{at: 0, struct: "s", path: ["f"]}],
    [kaaneru::bpf::alu(:mov, 1, 4)]
  )
  assert size(good) == 1
  table = kaaneru::btf::read(
    kaaneru::btf::encode(
      [
        kaaneru::btf::int_type("int", 4),
        kaaneru::btf::sized_type(
          :struct,
          "s",
          4,
          [{name: "f", type: 1, bits: 0}]
        )
      ]
    )
  )
  assert field_of_core(table, {kind: 0, access: "0:0", type: 2}, 3) ==
    {at: 3, struct: "s", path: ["f"], size: 4}
  assert (field_of_core(table, {kind: 3, access: "0:0", type: 2}, 3) rescue
    :refused) == :refused
end

test "a reference into a map's value becomes a data section libbpf reads, with its offset in the instruction, and reads back"
  m = kaaneru::bpf::declare_map(:g, :array, 4, 16, 1)
  p = assoc(
    assoc(
      kaaneru::bpf::assemble(
        [
          kaaneru::bpf::map_value_ref(1, :g, 8),
          kaaneru::bpf::load(:dw, 0, 1, 0),
          kaaneru::bpf::exit_program
        ]
      ),
      :maps,
      [m]
    ),
    :kind,
    :xdp
  )
  o = decode(object(p))
  part = section_of(o, ".data.g")
  assert part[:size] == 16
  assert part[:flags] == 3
  assert section_of(o, ".maps").nil?
  rel = first(o[:rels]["xdp"])
  assert rel[:symbol] == "g"
  assert rel[:type] == 1
  held = kaaneru::bpf::decode(section_of(o, "xdp")[:bytes])
  assert first(held)[:src] == 0
  assert first(held)[:imm] == 8
  back = program_of(o)
  assert first(back[:insns])[:src] == 2
  assert first(back[:insns])[:imm2] == 8
  assert first(back[:maps])[:value_size] == 16
  assert first(back[:relocs])[:map] == "g"
  assert kaaneru::bpf::encode(back) == kaaneru::bpf::encode(p)
end

test "a map named both ways, or of a shape libbpf cannot make from a section, refuses by name"
  both = assoc(
    kaaneru::bpf::assemble(
      [
        kaaneru::bpf::map_value_ref(1, :g, 0),
        kaaneru::bpf::map_ref(2, :g),
        kaaneru::bpf::exit_program
      ]
    ),
    :maps,
    [kaaneru::bpf::declare_map(:g, :array, 4, 8, 1)]
  )
  assert (object(both, {section: "xdp"}) rescue :refused) == :refused
  many = assoc(
    kaaneru::bpf::assemble(
      [kaaneru::bpf::map_value_ref(1, :g, 0), kaaneru::bpf::exit_program]
    ),
    :maps,
    [kaaneru::bpf::declare_map(:g, :array, 4, 8, 2)]
  )
  assert (object(many, {section: "xdp"}) rescue :refused) == :refused
end

test "a compiled program's source lines reach .BTF.ext in its object, and the switch leaves them out"
  q = assoc(
    kaaneru::bpf::compile_forms(
      read_forms("(define (%root/e c) (%line 2 3 7))"),
      {entry: :e, kind: :xdp}
    ),
    :source,
    {file: "f.b", text: ["def e(c)", "  7"]}
  )
  o = decode(object(q))
  got = kaaneru::btf::read_lines(
    section_of(o, ".BTF.ext")[:bytes],
    section_of(o, ".BTF")[:bytes]
  )
  assert first(first(got)[:lines])[:text] == "  7"
  off = decode(object(q, {line_info: false}))
  assert kaaneru::btf::read_lines(
    section_of(off, ".BTF.ext")[:bytes],
    section_of(off, ".BTF")[:bytes]
  ) == []
end

test "a function nothing reaches is dropped from the link, and the rest still run"
  p = kaaneru::bpf::with_funcs(
    kaaneru::bpf::assemble(
      [
        kaaneru::bpf::alu(:mov, 1, 40),
        kaaneru::bpf::call_local(:live),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:dead),
        kaaneru::bpf::alu(:mov, 0, 9),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:live),
        kaaneru::bpf::alu(:mov, 0, kaaneru::bpf::r(1)),
        kaaneru::bpf::alu(:add, 0, 2),
        kaaneru::bpf::exit_program
      ]
    ),
    [
      {name: "e", linkage: :global, params: [:ctx]},
      {name: "dead", label: :dead, linkage: :global, params: []},
      {name: "live", label: :live, linkage: :global, params: [:int]}
    ]
  )
  o = decode(object(assoc(p, :kind, :xdp)))
  back = program_of(o)
  assert map((f) -> f[:name], back[:funcs]) == %w[e live]
  assert back[:slots] == 6
  assert map((f) -> f[:at], back[:btf][:func_info]) == [0, 3]
  assert kaaneru::bpf::run(back).ret == 42
  whole = program_of(o, nil, {keep_unreached: true})
  assert whole[:slots] == 8
  assert map((f) -> f[:name], whole[:funcs]) == %w[e dead live]
  assert kaaneru::bpf::run(whole).ret == 42
end

test "a callback a program reaches only by reference is kept, and a call from a kept function keeps its target"
  p = kaaneru::bpf::with_funcs(
    kaaneru::bpf::assemble(
      [
        kaaneru::bpf::call_local(:outer),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:dead),
        kaaneru::bpf::alu(:mov, 0, 9),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:outer),
        kaaneru::bpf::alu(:mov, 1, 3),
        kaaneru::bpf::func_ref(2, :turn),
        kaaneru::bpf::alu(:mov, 3, 0),
        kaaneru::bpf::alu(:mov, 4, 0),
        kaaneru::bpf::call(:loop),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:turn),
        kaaneru::bpf::alu(:mov, 0, 0),
        kaaneru::bpf::exit_program
      ]
    ),
    [
      {name: "e", linkage: :global, params: [:ctx]},
      {name: "dead", label: :dead, linkage: :global, params: []},
      {name: "outer", label: :outer, linkage: :global, params: []},
      {name: "turn", label: :turn, linkage: :static, params: %i[int int]}
    ]
  )
  back = program_of(decode(object(assoc(p, :kind, :xdp))))
  assert map((f) -> f[:name], back[:funcs]) == %w[e outer turn]
  assert kaaneru::bpf::run(back).ret == 3
end

test "an object whose program reaches nothing in .text links none of it, and one with no symbols there keeps what it reaches whole"
  plain = program_of(
    decode(
      object(
        assoc(
          kaaneru::bpf::assemble(
            [kaaneru::bpf::alu(:mov, 0, 2), kaaneru::bpf::exit_program]
          ),
          :kind,
          :xdp
        )
      )
    )
  )
  assert plain[:slots] == 2
  assert function_starts({symbols: []}, {funcs: nil}, 2) == [0, 2]
  only_dead = kaaneru::bpf::with_funcs(
    kaaneru::bpf::assemble(
      [
        kaaneru::bpf::alu(:mov, 0, 2),
        kaaneru::bpf::exit_program,
        kaaneru::bpf::label(:dead),
        kaaneru::bpf::alu(:mov, 0, 9),
        kaaneru::bpf::exit_program
      ]
    ),
    [
      {name: "e", linkage: :global, params: [:ctx]},
      {name: "dead", label: :dead, linkage: :global, params: []}
    ]
  )
  o = decode(object(assoc(only_dead, :kind, :xdp)))
  assert program_of(o)[:slots] == 2
  assert program_of(o, nil, {keep_unreached: true})[:slots] == 2
end

test "a relocation this reader cannot link stops the link only when the function holding it is reached"
  row = {sym: {section: ".rodata", value: 0}, symbol: "s"}
  got = linked_rel(kaaneru::bpf::alu(:mov, 0, 0), row, 3, 0, 9)
  assert contains?(got[:unlinked], "cannot link")
  assert (refused_unlinked([got]) rescue :refused) == :refused
  assert refused_unlinked([kaaneru::bpf::exit_program]).nil?
end

test "a function list reads in slot order whichever section .BTF.ext names first, as clang writes .text first"
  names = %w[xdp .text]
  types = [
    kaaneru::btf::proto_type(0, []),
    kaaneru::btf::linked_type(:func, "e", 1, :global),
    kaaneru::btf::linked_type(:func, "g", 1, :global)
  ]
  sections = [
    {section: ".text", funcs: [{at: 0, type: 3}]},
    {section: "xdp", funcs: [{at: 0, type: 2}]}
  ]
  o = decode(
    encode(
      [
        {
          name: ".BTF",
          type: :progbits,
          flags: [],
          align: 4,
          bytes: kaaneru::btf::encode(types, names)
        },
        {
          name: ".BTF.ext",
          type: :progbits,
          flags: [],
          align: 4,
          bytes: kaaneru::btf::encode_ext(types, names, sections)
        }
      ],
      []
    )
  )
  got = info_of(o, "xdp", 5)
  assert got[:func_info] == [{at: 0, type: 2}, {at: 5, type: 3}]
  assert map((f) -> f[:name], got[:funcs]) == %w[e g]
end

test "bytes that are no ELF, a big-endian ELF, a truncated one and another machine each refuse by name"
  assert (decode([]) rescue :refused) == :refused
  assert (decode(repeat(0, 80)) rescue :refused) == :refused
  good = object(
    kaaneru::bpf::assemble([kaaneru::bpf::exit_program]),
    {section: "xdp"}
  )
  big = replaced(good, 5, 2)
  assert (decode(big) rescue :refused) == :refused
  short = slice_bytes(good, 0, 100)
  assert (decode(short) rescue :refused) == :refused
  assert (program_of(assoc_machine(decode(good))) rescue :refused) == :refused
end

test "a program with unbound kernel fields under {core: false}, a reference into no map's value and a section that is none each refuse by name"
  unbound = assoc(
    kaaneru::bpf::assemble(
      [
        assoc(
          kaaneru::bpf::alu(:add, 3, 0),
          :field,
          {struct: "s", path: ["f"], size: 4}
        ),
        kaaneru::bpf::exit_program
      ]
    ),
    :kind,
    :tracing
  )
  assert (object(unbound, {section: "fentry/x", core: false}) rescue
    :refused) == :refused
  valued = kaaneru::bpf::assemble(
    [kaaneru::bpf::map_value_ref(1, :m, 0), kaaneru::bpf::exit_program]
  )
  assert (object(valued, {section: "xdp"}) rescue :refused) == :refused
  named = kaaneru::bpf::assemble(
    [kaaneru::bpf::map_ref(1, :absent), kaaneru::bpf::exit_program]
  )
  assert (object(named, {section: "xdp"}) rescue :refused) == :refused
  assert (program_of(decode(encode([], [])), "gone") rescue :refused) ==
    :refused
end
