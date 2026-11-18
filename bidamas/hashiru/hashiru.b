@moduledoc """
hashiru (走る) — blue code that runs: kuzushi's A-normal form compiled to x86-64 instructions (kikaigo) inside a static executable (erufu), with no other language in the path (docs/PURE-BLUE.md B3).

This first code generator is the simplest correct one: every named value lives in its own stack slot below rbp, every operation loads its atoms into rax and rcx, computes in rax and stores the result back. A comparison leaves 1 or 0; an if tests its condition against 0 and jumps; a program's value becomes its exit status. Register allocation replaces the slots later; the slots are the oracle it must agree with.

    length(compile(read_forms("(+ 1 2)")[0])) > 120 #=> true
"""

use("kaaneru/erufu", [:executable])
use("kikaigo", %i[assemble le64])
use("kuzushi", %i[anf closure_convert head_is? perceus_program whole])
use("retsu", %i[drop_n first flat_map index_of last rest slice take_n])
use("shisutemu", %i[status_of stdout_of])

legacy_names(
  "0.1.0",
  [
    %w[rc_call hashiru::call_code hashiru::tagged_atom],
    %w[run_exit hashiru::run_status hashiru::compile],
    %w[run_closures_exit hashiru::run_status hashiru::compile_closures]
  ]
)

@doc """
bound_names: every name a term binds with let, in its branches too, in first-bound order.

    bound_names(anf(read_forms("(+ 1 2)")[0])) #=> ["t__0"]
"""
def bound_names(term)
  if head_is?(term, "ret")
    []
  else
    b = term[1]
    inner = if head_is?(b[1], "if")
      append(bound_names(b[1][2]), bound_names(b[1][3]))
    elsif head_is?(b[1], "try")
      bound_names(b[1][1])
    else
      []
    end
    append(append([to_s(b[0])], inner), bound_names(term[2]))
  end
end

@doc """
slot: the rbp displacement of a name's stack slot.

    slot(["a", "b"], "b") #=> -16
"""
def slot(slots, name)
  i = index_of(slots, name)
  if i < 0
    raise(:unbound, "hashiru: `#{name}` has no slot")
  else
    -8 * (i + 1)
  end
end

@doc """
SYSCALL_REGS: where a Linux x86-64 system call takes its number and its six arguments, in order.

    SYSCALL_REGS[4] #=> "r10"
"""
SYSCALL_REGS = %w[rax rdi rsi rdx r10 r8 r9]

@doc """
load_atom: the instructions that put an atom's value in a register: an integer or a boolean as an immediate, a name from its slot.

    load_atom([], 7, "rax") #=> [{op: "mov", dst: "rax", imm: 7}]
"""
def load_atom(slots, a, r)
  if symbol?(a)
    [{op: "load", dst: r, disp: slot(slots, to_s(a))}]
  elsif a == true
    [{op: "mov", dst: r, imm: 1}]
  elsif a == false or a.nil?
    [{op: "mov", dst: r, imm: 0}]
  else
    [{op: "mov", dst: r, imm: a}]
  end
end

@doc """
compare: the instructions that leave 1 or 0 in rax for a comparison of rax with rcx.

    length(compare("l")) #=> 3
"""
def compare(code)
  [{op: "cmp", dst: "rax", src: "rcx"}, {op: "set", cond: code}, {op: "movzx"}]
end

@doc """
op_code: the instructions for a primitive over its atoms, leaving the answer in rax.

    length(op_code([], "+", [1, 2])) #=> 3
"""
def op_code(slots, op, args)
  two = append(
    load_atom(slots, args[0], "rax"),
    load_atom(slots, args[1], "rcx")
  )
  if op == "+"
    append(two, [{op: "add", dst: "rax", src: "rcx"}])
  elsif op == "-"
    append(two, [{op: "sub", dst: "rax", src: "rcx"}])
  elsif op == "*"
    append(two, [{op: "imul", dst: "rax", src: "rcx"}])
  elsif op == "<"
    append(two, compare("l"))
  elsif op == ">"
    append(two, compare("g"))
  elsif op == "equal?"
    append(two, compare("e"))
  elsif op == "syscall6"
    append(
      flat_map(
        range(0, length(args)),
        (k) -> load_atom(slots, args[k], SYSCALL_REGS[k])
      ),
      [{op: "syscall"}]
    )
  elsif op == "load_word"
    append(load_atom(slots, args[0], "rcx"), [{op: "load_at", dst: "rax"}])
  elsif op == "store_word"
    append(
      append(
        load_atom(slots, args[0], "rcx"),
        load_atom(slots, args[1], "rax")
      ),
      [{op: "store_at", src: "rax"}]
    )
  elsif op == "id" or op == "dup"
    load_atom(slots, args[0], "rax")
  elsif op == "drop"
    []
  else
    raise(:unsupported, "hashiru: no code for `#{op}` yet")
  end
end

@doc """
gen: the instructions of a term and the label counter after it; at its ret the value is stored into the slot of `into`, or, when `into` is nil, becomes the exit status.

    gen([], read_forms("(ret 3)")[0], nil, 0)[1] #=> 0
"""
def gen(slots, term, into, n)
  if head_is?(term, "ret")
    value = load_atom(slots, term[1], "rax")
    tail = if into == :return
      [{op: "mov", dst: "rsp", src: "rbp"}, {op: "pop_rbp"}, {op: "ret"}]
    elsif into.nil?
      [
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "mov", dst: "rax", imm: 60},
        {op: "syscall"}
      ]
    else
      [{op: "store", src: "rax", disp: slot(slots, into)}]
    end
    [append(value, tail), n]
  else
    b = term[1]
    v = to_s(b[0])
    rhs = b[1]
    here = if head_is?(rhs, "if")
      no = "else_#{to_s(n)}"
      out = "end_#{to_s(n)}"
      yes = gen(slots, rhs[2], v, n + 1)
      other = gen(slots, rhs[3], v, yes[1])
      [
        append(
          *[
            load_atom(slots, rhs[1], "rax"),
            [{op: "cmp", dst: "rax", imm: 0}, {op: "j", cond: "e", label: no}],
            yes[0],
            [{op: "jmp", label: out}, {op: "label", name: no}],
            other[0],
            [{op: "label", name: out}]
          ]
        ),
        other[1]
      ]
    else
      [
        append(
          rhs_code(slots, rhs),
          [{op: "store", src: "rax", disp: slot(slots, v)}]
        ),
        n
      ]
    end
    k = gen(slots, term[2], into, here[1])
    [append(here[0], k[0]), k[1]]
  end
end

@doc """
program: the instructions of a whole program: a frame with a slot per bound name, then the term, ending in exit.

    program(anf(read_forms("7")[0]))[0] #=> {op: "push_rbp"}
"""
def program(term)
  slots = bound_names(term)
  frame = 8 * length(slots)
  append(
    [
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: frame}
    ],
    gen(slots, term, nil, 0)[0]
  )
end

@doc """
compile: a core form as the bytes of a static x86-64 executable whose exit status is the form's value.

    compile(read_forms("7")[0])[0] #=> 127
"""
def compile(form)
  executable(assemble(program(anf(form))))
end

@doc """
linux_x86?: whether this machine can run what compile makes.

    boolean?(linux_x86?) #=> true
"""
def linux_x86?()
  r = exec_capture("uname", "-sm")
  status_of(r) == 0 and contains?(stdout_of(r), "Linux x86_64")
end

@doc """
run_status: compile a form with `compiler`, run it as a static executable, and answer its exit status.

    integer?(1) #=> true
"""
def run_status(form, compiler)
  path = path_join(temp_dir("hashiru"), "a.out")
  write_bytes(path, compiler(form))
  exec_capture("chmod", "+x", path)
  status_of(exec_capture(path))
end

@doc """
PROGRAMS: core programs and the exit status each must give when compiled and run.

    PROGRAMS[1][1] #=> 42
"""
PROGRAMS = [
  ["(+ 1 2)", 3],
  ["(* 6 7)", 42],
  ["(- 50 8)", 42],
  ["(if (< 1 2) 10 20)", 10],
  ["(if (> 1 2) 10 20)", 20],
  ["(+ 1 (if (equal? 2 2) (* 3 4) 0))", 13],
  ["(let ((a 5)) (* a a))", 25],
  ["(let ((a 3)) (let ((b (+ a 4))) (- (* b b) a)))", 46],
  ["(begin (+ 1 1) (+ 2 3))", 5],
  [
    "(let ((p (syscall6 9 0 4096 3 34 -1 0))) (begin (store_word p 42) (load_word p)))",
    42
  ],
  [
    "(let ((p (syscall6 9 0 4096 3 34 -1 0))) (begin (store_word p 40) (store_word (+ p 8) 2) (+ (load_word p) (load_word (+ p 8)))))",
    42
  ]
]

test "every program's exit status is its value when run on x86-64 Linux", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      (p) -> assert run_status(read_forms(p[0])[0], compile) == p[1],
      PROGRAMS
    )
  end
end

test "the generated program frames a slot per name, enters, and exits through the exit syscall"
  insns = program(anf(read_forms("(+ 1 2)")[0]))
  assert insns[0] == {op: "push_rbp"}
  assert insns[2] == {op: "sub", dst: "rsp", imm: 8}
  assert insns[length(insns) - 1] == {op: "syscall"}
  assert insns[length(insns) - 2] == {op: "mov", dst: "rax", imm: 60}
end

test "an if becomes a compare with zero, a jump past its yes branch, and two labels"
  insns = program(anf(read_forms("(if (< 1 2) 10 20)")[0]))
  ops = map((i) -> i[:op], insns)
  assert length(filter((o) -> o == "label", ops)) == 2
  assert length(filter((o) -> o == "j", ops)) == 1
  assert length(filter((o) -> o == "jmp", ops)) == 1
end

test "the helpers are exercised by name"
  assert bound_names(anf(read_forms("(+ 1 (+ 2 3))")[0])) == %w[t__0 t__1]
  assert slot(["a"], "a") == -8
  assert load_atom(["a"], read_forms("a")[0], "rcx") ==
    [{op: "load", dst: "rcx", disp: -8}]
  assert load_atom([], true, "rax") == [{op: "mov", dst: "rax", imm: 1}]
  assert compare("e")[1] == {op: "set", cond: "e"}
  assert length(op_code([], "*", [2, 3])) == 3
  assert gen([], read_forms("(ret 3)")[0], nil, 0)[0][0] ==
    {op: "mov", dst: "rax", imm: 3}
  assert compile(read_forms("1")[0])[1] == 69
  assert length(PROGRAMS) == 11
  assert SYSCALL_REGS[0] == "rax"
  assert length(op_code([], "syscall6", [60, 0, 0, 0, 0, 0, 0])) == 8
  assert op_code([], "load_word", [8])[1] == {op: "load_at", dst: "rax"}
end

test "linux_x86? answers whether this host runs what compile makes", {
  kind: :integration,
  allow: [:process]
}
  assert boolean?(linux_x86?)
end

test "a name with no slot is refused as :unbound"
  k = begin
    slot(["a"], "b")
  rescue e
    e.kind
  end
  assert k == :unbound
end

test "an unsupported op is refused by name"
  k = begin
    op_code([], "list", [1, 2])
  rescue e
    e.kind
  end
  assert k == :unsupported
end

@doc """
ARG_REGS: where a call passes its first six arguments; the closure itself goes in r11.

    ARG_REGS[0] #=> "rdi"
"""
ARG_REGS = %w[rdi rsi rdx rcx r8 r9]

@doc """
rhs_code: the instructions for a right-hand side that is not an if: a closure allocates its record, a call runs through one, anything else is a primitive.

    length(rhs_code([], read_forms("(+ 1 2)")[0])) #=> 3
"""
def rhs_code(slots, rhs)
  if head_is?(rhs, "closure")
    closure_code(slots, rhs[1], rest(rest(rhs)))
  elsif head_is?(rhs, "call")
    call_code(slots, rhs[1], rest(rest(rhs)), load_atom)
  else
    op_code(slots, to_s(first(rhs)), rest(rhs))
  end
end

@doc """
closure_code: allocate a closure record at r15, its code address first and then each captured value, answering its address in rax.

    length(closure_code([], "f", [])) #=> 4
"""
def closure_code(slots, label, captured)
  append(
    *[
      [
        {op: "lea_label", label:},
        {op: "store", src: "rax", base: "r15", disp: 0}
      ],
      flat_map(
        range(0, length(captured)),
        fn(k)
          append(
            load_atom(slots, captured[k], "rax"),
            [{op: "store", src: "rax", base: "r15", disp: 8 * (k + 1)}]
          )
        end
      ),
      [
        {op: "mov", dst: "rax", src: "r15"},
        {op: "add", dst: "r15", imm: 8 * (length(captured) + 1)}
      ]
    ]
  )
end

@doc """
call_code: a call through a closure, each atom loaded by `load` (load_atom for raw values, tagged_atom for tagged ones): the arguments in ARG_REGS, the closure in r11, then a call through its code address; the answer comes back in rax.

    last(call_code(["f"], read_forms("f")[0], [1], load_atom))[:op] #=> "call_r11"
"""
def call_code(slots, f, args, load)
  if length(args) > 6
    raise(:unsupported, "hashiru: a call passes at most six arguments")
  end
  append(
    *[
      flat_map(
        range(0, length(args)),
        (k) -> load(slots, args[k], ARG_REGS[k])
      ),
      load(slots, f, "r11"),
      [{op: "call_r11"}]
    ]
  )
end

@doc """
function_code: one lifted function: its label, a frame with a slot per parameter, capture and bound name, the parameters stored from ARG_REGS, the captures read from the closure in r11, then its body returning in rax.

    function_code({label: "f", params: [], captured: [], body: read_forms("(ret 1)")[0]}, 0)[0][0] #=> {op: "label", name: "f"}
"""
def function_code(f, n)
  slots = append(append(f[:params], f[:captured]), bound_names(f[:body]))
  body = gen(slots, f[:body], :return, n)
  [
    append(
      *[
        [
          {op: "label", name: f[:label]},
          {op: "push_rbp"},
          {op: "mov", dst: "rbp", src: "rsp"},
          {op: "sub", dst: "rsp", imm: 8 * length(slots)}
        ],
        flat_map(
          range(0, length(f[:params])),
          fn(k)
            [{op: "store", src: ARG_REGS[k], disp: slot(slots, f[:params][k])}]
          end
        ),
        flat_map(
          range(0, length(f[:captured])),
          fn(k)
            [
              {op: "load", dst: "rax", base: "r11", disp: 8 * (k + 1)},
              {op: "store", src: "rax", disp: slot(slots, f[:captured][k])}
            ]
          end
        ),
        body[0]
      ]
    ),
    body[1]
  ]
end

@doc """
HEAP_BYTES: the size of the region a program maps at start for its records, bumped by r15.

    HEAP_BYTES #=> 1_048_576
"""
HEAP_BYTES = 1_048_576

@doc """
heap_start: map HEAP_BYTES read-write anonymous and keep its address in r15, the bump pointer.

    last(heap_start)[:src] #=> "rax"
"""
def heap_start()
  append(
    op_code([], "syscall6", [9, 0, HEAP_BYTES, 3, 34, -1, 0]),
    [{op: "mov", dst: "r15", src: "rax"}]
  )
end

@doc """
whole_program: the instructions of a closure-converted program: the main frame and heap, the main term ending in exit, then every lifted function.

    whole_program(closure_convert(anf(read_forms("7")[0])))[0] #=> {op: "push_rbp"}
"""
def whole_program(p)
  slots = bound_names(p[:main])
  main = gen(slots, p[:main], nil, 0)
  fns = reduce(
    fn(acc, f)
      c = function_code(f, acc[1])
      [append(acc[0], c[0]), c[1]]
    end,
    [[], main[1]],
    p[:fns]
  )
  append(
    *[
      [
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sub", dst: "rsp", imm: 8 * length(slots)}
      ],
      heap_start,
      main[0],
      fns[0]
    ]
  )
end

@doc """
compile_closures: a core form with lambdas as the bytes of a static executable whose exit status is its value.

    compile_closures(read_forms("7")[0])[0] #=> 127
"""
def compile_closures(form)
  executable(assemble(whole_program(closure_convert(anf(form)))))
end

@doc """
CLOSURE_PROGRAMS: programs with lambdas and the exit status each must give.

    CLOSURE_PROGRAMS[0][1] #=> 15
"""
CLOSURE_PROGRAMS = [
  ["(let ((k 10)) (let ((f (lambda (x) (+ x k)))) (f 5)))", 15],
  ["(let ((f (lambda (x) (lambda (y) (+ x y))))) (let ((g (f 3))) (g 4)))", 7],
  [
    "(let ((a 1)) (let ((f (lambda (x) (if (< x a) a x)))) (+ (f 0) (f 5))))",
    6
  ],
  [
    "(let ((twice (lambda (g x) (g (g x))))) (let ((inc (lambda (n) (+ n 1)))) (twice inc 5)))",
    7
  ],
  ["(let ((add3 (lambda (a b c) (+ a (+ b c))))) (add3 10 20 12))", 42]
]

test "closure programs exit with their value on x86-64 Linux", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      (p) -> assert run_status(read_forms(p[0])[0], compile_closures) == p[1],
      CLOSURE_PROGRAMS
    )
  end
end

test "a closure is a record at r15 and a call goes through r11"
  c = closure_code([], "f", [3])
  assert c[0] == {op: "lea_label", label: "f"}
  assert last(c) == {op: "add", dst: "r15", imm: 16}
  k = call_code(["g"], read_forms("g")[0], [1, 2], load_atom)
  assert k[0] == {op: "mov", dst: "rdi", imm: 1}
  assert last(k) == {op: "call_r11"}
  f = nth(
    0,
    function_code(
      {
        label: "h",
        params: ["x"],
        captured: ["k"],
        body: read_forms("(ret x)")[0]
      },
      0
    )
  )
  assert f[0] == {op: "label", name: "h"}
  assert last(f) == {op: "ret"}
  assert length(ARG_REGS) == 6
  assert HEAP_BYTES == 1_048_576
  assert last(heap_start)[:dst] == "r15"
  assert rhs_code([], read_forms("(+ 1 2)")[0])[2] ==
    {op: "add", dst: "rax", src: "rcx"}
  assert whole_program(closure_convert(anf(read_forms("1")[0])))[0] ==
    {op: "push_rbp"}
  assert compile_closures(read_forms("1")[0])[1] == 69
  assert length(CLOSURE_PROGRAMS) == 5
  refused = begin
    call_code([], 1, [1, 2, 3, 4, 5, 6, 7], load_atom)
  rescue e
    e.kind
  end
  assert refused == :unsupported
end

@doc """
times8: the instructions that multiply a register by 8, by three doublings.

    length(times8("rax")) #=> 3
"""
def times8(r)
  map((k) -> {op: "add", dst: r, src: r}, range(0, 3))
end

@doc """
RT_ALLOC: the runtime's allocator, in machine code. It takes a block of rdi words from the free list kept for that size at r14, or bumps r15 when the list is empty; it sets the block's count to 1 and records its size, counts it live at r14, and answers it in rax.

    RT_ALLOC[0] #=> {op: "label", name: "rt_alloc"}
"""
RT_ALLOC = append(
  *[
    [{op: "label", name: "rt_alloc"}, {op: "mov", dst: "rax", src: "rdi"}],
    times8("rax"),
    [
      {op: "add", dst: "rax", src: "r14"},
      {op: "load", dst: "rcx", base: "rax", disp: 0},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_alloc_bump"},
      {op: "load", dst: "rdx", base: "rcx", disp: 0},
      {op: "store", src: "rdx", base: "rax", disp: 0},
      {op: "mov", dst: "rax", src: "rcx"},
      {op: "jmp", label: "rt_alloc_init"},
      {op: "label", name: "rt_alloc_bump"},
      {op: "mov", dst: "rax", src: "r15"},
      {op: "mov", dst: "rcx", src: "rdi"}
    ],
    times8("rcx"),
    [
      {op: "add", dst: "r15", src: "rcx"},
      {op: "label", name: "rt_alloc_init"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 8},
      {op: "store", src: "rdi", base: "rax", disp: 16},
      {op: "load", dst: "rcx", base: "r14", disp: 0},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "r14", disp: 0},
      {op: "ret"}
    ]
  ]
)

@doc """
not_a_block: the instructions that jump to a label when rdi is no block: an odd word is an integer, and a word below 4096 is false, nil or true.

    length(not_a_block("x")) #=> 6
"""
def not_a_block(out)
  [
    {op: "mov", dst: "rax", src: "rdi"},
    {op: "and", dst: "rax", imm: 1},
    {op: "cmp", dst: "rax", imm: 0},
    {op: "j", cond: "ne", label: out},
    {op: "cmp", dst: "rdi", imm: 4096},
    {op: "j", cond: "l", label: out}
  ]
end

@doc """
RT_DUP: add one reference to the block in rdi; anything that is no block is left alone.

    RT_DUP[0] #=> {op: "label", name: "rt_dup"}
"""
RT_DUP = append(
  *[
    [{op: "label", name: "rt_dup"}],
    not_a_block("rt_dup_out"),
    [
      {op: "load", dst: "rcx", base: "rdi", disp: 8},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rdi", disp: 8},
      {op: "label", name: "rt_dup_out"},
      {op: "ret"}
    ]
  ]
)

@doc """
RT_DROP: take one reference from the block in rdi; at zero, drop every capture it holds, put it on the free list for its size and count it no longer live.

    RT_DROP[0] #=> {op: "label", name: "rt_drop"}
"""
RT_DROP = append(
  *[
    [{op: "label", name: "rt_drop"}],
    not_a_block("rt_drop_out"),
    [
      {op: "load", dst: "rcx", base: "rdi", disp: 8},
      {op: "sub", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rdi", disp: 8},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "ne", label: "rt_drop_out"},
      {op: "load", dst: "rdx", base: "rdi", disp: 16},
      {op: "load", dst: "rax", base: "rdi", disp: 0},
      {op: "cmp", dst: "rax", imm: 1},
      {op: "j", cond: "e", label: "rt_drop_free"},
      {op: "mov", dst: "rcx", imm: 3},
      {op: "label", name: "rt_drop_loop"},
      {op: "cmp", dst: "rcx", src: "rdx"},
      {op: "j", cond: "ge", label: "rt_drop_free"},
      {op: "push", src: "rdi"},
      {op: "push", src: "rcx"},
      {op: "push", src: "rdx"},
      {op: "mov", dst: "rax", src: "rcx"}
    ],
    times8("rax"),
    [
      {op: "add", dst: "rax", src: "rdi"},
      {op: "load", dst: "rdi", base: "rax", disp: 0},
      {op: "call_label", label: "rt_drop"},
      {op: "pop", dst: "rdx"},
      {op: "pop", dst: "rcx"},
      {op: "pop", dst: "rdi"},
      {op: "add", dst: "rcx", imm: 1},
      {op: "jmp", label: "rt_drop_loop"},
      {op: "label", name: "rt_drop_free"},
      {op: "mov", dst: "rax", src: "rdx"}
    ],
    times8("rax"),
    [
      {op: "add", dst: "rax", src: "r14"},
      {op: "load", dst: "rcx", base: "rax", disp: 0},
      {op: "store", src: "rcx", base: "rdi", disp: 0},
      {op: "store", src: "rdi", base: "rax", disp: 0},
      {op: "load", dst: "rcx", base: "r14", disp: 0},
      {op: "sub", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "r14", disp: 0},
      {op: "label", name: "rt_drop_out"},
      {op: "ret"}
    ]
  ]
)

@doc """
tagged_atom: the instructions that put an atom's runtime value in a register: an integer n as 2n + 1, false and nil as 0, true as 2, a name from its slot.

    tagged_atom([], 20, "rax") #=> [{op: "mov", dst: "rax", imm: 41}]
"""
def tagged_atom(slots, a, r)
  if keyword?(a)
    [{op: "lea_label", dst: r, label: kw_label(a)}]
  elsif string?(a)
    [{op: "lea_label", dst: r, label: str_label(a)}]
  elsif symbol?(a)
    [{op: "load", dst: r, disp: slot(slots, to_s(a))}]
  elsif a == true
    [{op: "mov", dst: r, imm: 2}]
  elsif a == false or a.nil?
    [{op: "mov", dst: r, imm: 0}]
  else
    [{op: "mov", dst: r, imm: 2 * a + 1}]
  end
end

@doc """
tagged_compare: a comparison of rax with rcx left in rax as true (2) or false (0).

    last(tagged_compare("e")) #=> {op: "add", dst: "rax", src: "rax"}
"""
def tagged_compare(code)
  append(compare(code), [{op: "add", dst: "rax", src: "rax"}])
end

@doc """
rc_op: the instructions for a primitive over tagged values, answering in rax: arithmetic corrects for the tag, a comparison answers a boolean, dup and drop call the runtime.

    length(rc_op([], "+", [1, 2])) #=> 4
"""
def rc_op(slots, op, args)
  two = append(
    tagged_atom(slots, args[0], "rax"),
    tagged_atom(slots, args[1], "rcx")
  )
  if op == "+"
    append(
      two,
      [{op: "add", dst: "rax", src: "rcx"}, {op: "sub", dst: "rax", imm: 1}]
    )
  elsif op == "-"
    append(
      two,
      [{op: "sub", dst: "rax", src: "rcx"}, {op: "add", dst: "rax", imm: 1}]
    )
  elsif op == "*"
    append(
      two,
      [
        {op: "sar1", dst: "rax"},
        {op: "sub", dst: "rcx", imm: 1},
        {op: "imul", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", imm: 1}
      ]
    )
  elsif op == "<"
    append(two, tagged_compare("l"))
  elsif op == ">"
    append(two, tagged_compare("g"))
  elsif op == "equal?"
    append(
      append(
        tagged_atom(slots, args[0], "rdi"),
        tagged_atom(slots, args[1], "rsi")
      ),
      [
        {op: "push", src: "rdi"},
        {op: "push", src: "rsi"},
        {op: "call_label", label: "rt_equal"},
        {op: "pop", dst: "rsi"},
        {op: "pop", dst: "rdi"},
        {op: "push", src: "rax"},
        {op: "push", src: "rsi"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rdi"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rax"}
      ]
    )
  elsif op == "concat"
    concat_code(slots, args)
  elsif op == "to_s"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [{op: "call_label", label: "rt_to_s"}]
    )
  elsif op == "cons"
    cons_code(
      tagged_atom(slots, args[0], "rcx"),
      tagged_atom(slots, args[1], "rbx")
    )
  elsif op == "list"
    list_code(slots, args)
  elsif op == "first"
    part_code(slots, args[0], 24)
  elsif op == "rest"
    part_code(slots, args[0], 32)
  elsif op == "raise"
    append(
      [{op: "push", src: "rbx"}],
      append(
        tagged_atom(slots, args[0], "rbx"),
        [
          {op: "mov", dst: "rdi", imm: 4},
          {op: "call_label", label: "rt_alloc"},
          {op: "mov", dst: "rcx", imm: 4},
          {op: "store", src: "rcx", base: "rax", disp: 0},
          {op: "store", src: "rbx", base: "rax", disp: 24},
          {op: "pop", dst: "rbx"}
        ]
      )
    )
  elsif op == "failed?"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [
        {op: "push", src: "rdi"},
        {op: "call_label", label: "rt_is_error"},
        {op: "pop", dst: "rdi"},
        {op: "push", src: "rax"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rax"}
      ]
    )
  elsif op == "hash-map"
    map_code(slots, args)
  elsif op == "assoc"
    append(
      [{op: "push", src: "rbx"}],
      append(
        tagged_atom(slots, args[0], "rbx"),
        append(entry_code(slots, args[1], args[2]), [{op: "pop", dst: "rbx"}])
      )
    )
  elsif op == "get"
    get_code(slots, args[0], args[1])
  elsif op == "string_length"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [
        {op: "load", dst: "rax", base: "rdi", disp: 24},
        {op: "add", dst: "rax", src: "rax"},
        {op: "add", dst: "rax", imm: 1},
        {op: "push", src: "rax"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rax"}
      ]
    )
  elsif op == "write_stdout"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [
        {op: "push", src: "rdi"},
        {op: "mov", dst: "rsi", src: "rdi"},
        {op: "add", dst: "rsi", imm: 32},
        {op: "load", dst: "rdx", base: "rdi", disp: 24},
        {op: "mov", dst: "rax", imm: 1},
        {op: "mov", dst: "rdi", imm: 1},
        {op: "syscall"},
        {op: "pop", dst: "rdi"},
        {op: "call_label", label: "rt_drop"},
        {op: "mov", dst: "rax", imm: 0}
      ]
    )
  elsif op == "exit_with"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [
        {op: "sar1", dst: "rdi"},
        {op: "mov", dst: "rax", imm: 60},
        {op: "syscall"}
      ]
    )
  elsif op == "length"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [
        {op: "push", src: "rdi"},
        {op: "call_label", label: "rt_length"},
        {op: "pop", dst: "rdi"},
        {op: "push", src: "rax"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rax"}
      ]
    )
  elsif op == "id"
    tagged_atom(slots, args[0], "rax")
  elsif op == "dup"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [{op: "call_label", label: "rt_dup"}]
    )
  elsif op == "drop"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [{op: "call_label", label: "rt_drop"}]
    )
  else
    raise(:unsupported, "hashiru: no reference-counted code for `#{op}` yet")
  end
end

@doc """
rc_closure: allocate a closure block of 3 + captures words through rt_alloc and fill it: its code address at word 0, each captured value from word 3; the captured references move into it.

    rc_closure([], "f", [])[0] #=> {op: "mov", dst: "rdi", imm: 3}
"""
def rc_closure(slots, label, captured)
  append(
    *[
      [
        {op: "mov", dst: "rdi", imm: 3 + length(captured)},
        {op: "call_label", label: "rt_alloc"},
        {op: "mov", dst: "rbx", src: "rax"},
        {op: "lea_label", label:},
        {op: "store", src: "rax", base: "rbx", disp: 0}
      ],
      flat_map(
        range(0, length(captured)),
        fn(k)
          append(
            tagged_atom(slots, captured[k], "rax"),
            [{op: "store", src: "rax", base: "rbx", disp: 8 * (k + 3)}]
          )
        end
      ),
      [{op: "mov", dst: "rax", src: "rbx"}]
    ]
  )
end

@doc """
rc_rhs: a right-hand side that is not an if, over tagged values.

    length(rc_rhs([], read_forms("(+ 1 2)")[0])) #=> 4
"""
def rc_rhs(slots, rhs)
  if head_is?(rhs, "closure")
    rc_closure(slots, rhs[1], rest(rest(rhs)))
  elsif head_is?(rhs, "call")
    call_code(slots, rhs[1], rest(rest(rhs)), tagged_atom)
  elsif head_is?(rhs, "gcall")
    rc_gcall(slots, rhs[1], rest(rest(rhs)))
  else
    rc_op(slots, to_s(first(rhs)), rest(rhs))
  end
end

@doc """
rc_gen: a term over tagged values; at its ret the value goes into a slot, returns from a function, or ends the program: as its untagged value, or, in leak mode, as the count of blocks still live after it is dropped.

    rc_gen([], read_forms("(ret 3)")[0], :exit, 0)[1] #=> 0
"""
def rc_gen(slots, term, into, n)
  if head_is?(term, "ret")
    value = tagged_atom(slots, term[1], "rax")
    tail = if into == :return
      [{op: "mov", dst: "rsp", src: "rbp"}, {op: "pop_rbp"}, {op: "ret"}]
    elsif into == :exit
      [
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "sar1", dst: "rdi"},
        {op: "mov", dst: "rax", imm: 60},
        {op: "syscall"}
      ]
    elsif into == :leaks
      [
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "call_label", label: "rt_drop"},
        {op: "load", dst: "rdi", base: "r14", disp: 0},
        {op: "mov", dst: "rax", imm: 60},
        {op: "syscall"}
      ]
    else
      [{op: "store", src: "rax", disp: slot(slots, into)}]
    end
    [append(value, tail), n]
  else
    b = term[1]
    v = to_s(b[0])
    rhs = b[1]
    here = if head_is?(rhs, "try")
      ok = "tryok_#{to_s(n)}"
      out = "tryend_#{to_s(n)}"
      body = rc_gen(slots, rhs[1], v, n + 1)
      [
        append(
          *[
            body[0],
            tagged_atom(slots, read_forms(v)[0], "rdi"),
            [
              {op: "call_label", label: "rt_is_error"},
              {op: "cmp", dst: "rax", imm: 0},
              {op: "j", cond: "e", label: ok}
            ],
            tagged_atom(slots, read_forms(v)[0], "rdi"),
            [
              {op: "call_label", label: "rt_payload"},
              {op: "mov", dst: "rdi", src: "rax"}
            ],
            tagged_atom(slots, rhs[2], "r11"),
            [
              {op: "call_r11"},
              {op: "store", src: "rax", disp: slot(slots, v)},
              {op: "jmp", label: out},
              {op: "label", name: ok}
            ],
            tagged_atom(slots, rhs[2], "rdi"),
            [{op: "call_label", label: "rt_drop"}, {op: "label", name: out}]
          ]
        ),
        body[1]
      ]
    elsif head_is?(rhs, "if")
      no = "else_#{to_s(n)}"
      out = "end_#{to_s(n)}"
      yes = rc_gen(slots, rhs[2], v, n + 1)
      other = rc_gen(slots, rhs[3], v, yes[1])
      [
        append(
          *[
            tagged_atom(slots, rhs[1], "rax"),
            [{op: "cmp", dst: "rax", imm: 0}, {op: "j", cond: "e", label: no}],
            yes[0],
            [{op: "jmp", label: out}, {op: "label", name: no}],
            other[0],
            [{op: "label", name: out}]
          ]
        ),
        other[1]
      ]
    elsif v == "_"
      [rc_rhs(slots, rhs), n]
    else
      [
        append(
          rc_rhs(slots, rhs),
          [{op: "store", src: "rax", disp: slot(slots, v)}]
        ),
        n
      ]
    end
    k = rc_gen(slots, term[2], into, here[1])
    [append(here[0], k[0]), k[1]]
  end
end

@doc """
rc_names: the slot names of a term, without the _ that binds a dup's or a drop's unused answer.

    rc_names(read_forms("(let (_ (dup x)) (ret 1))")[0]) #=> []
"""
def rc_names(term)
  filter((x) -> x != "_", bound_names(term))
end

@doc """
rc_function: one lifted function over tagged values: its frame, its parameters stored, each capture read from the closure in r11 and given its own reference, then the closure itself dropped (the call consumed it), then its body.

    rc_function({label: "f", params: [], captured: [], body: read_forms("(ret 1)")[0]}, 0)[0][0] #=> {op: "label", name: "f"}
"""
def rc_function(f, n)
  slots = append(append(f[:params], f[:captured]), rc_names(f[:body]))
  body = rc_gen(slots, f[:body], :return, n)
  [
    append(
      *[
        [
          {op: "label", name: f[:label]},
          {op: "push_rbp"},
          {op: "mov", dst: "rbp", src: "rsp"},
          {op: "sub", dst: "rsp", imm: 8 * length(slots)}
        ],
        flat_map(
          range(0, length(f[:params])),
          fn(k)
            [{op: "store", src: ARG_REGS[k], disp: slot(slots, f[:params][k])}]
          end
        ),
        flat_map(
          range(0, length(f[:captured])),
          fn(k)
            [
              {op: "load", dst: "rdi", base: "r11", disp: 8 * (k + 3)},
              {op: "store", src: "rdi", disp: slot(slots, f[:captured][k])},
              {op: "push", src: "r11"},
              {op: "call_label", label: "rt_dup"},
              {op: "pop", dst: "r11"}
            ]
          end
        ),
        [
          {op: "mov", dst: "rdi", src: "r11"},
          {op: "call_label", label: "rt_drop"}
        ],
        body[0]
      ]
    ),
    body[1]
  ]
end

@doc """
rc_program: a whole reference-counted program: the main frame, a heap whose first 512 bytes hold the live count and the free-list heads, the main term, every function, then the runtime.

    rc_program(perceus_program(closure_convert(anf(read_forms("7")[0]))), :exit)[0] #=> {op: "push_rbp"}
"""
def rc_program(p, mode)
  slots = rc_names(p[:main])
  main = rc_gen(slots, p[:main], mode, 0)
  fns = reduce(
    fn(acc, f)
      c = rc_function(f, acc[1])
      [append(acc[0], c[0]), c[1]]
    end,
    [[], main[1]],
    p[:fns]
  )
  append(
    *[
      [
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sub", dst: "rsp", imm: 8 * length(slots)}
      ],
      heap_start,
      [{op: "mov", dst: "r14", src: "r15"}, {op: "add", dst: "r15", imm: 512}],
      main[0],
      fns[0],
      RT_ALLOC,
      RT_DUP,
      RT_DROP,
      RT_LENGTH,
      RT_GET,
      RT_IS_ERROR,
      RT_PAYLOAD,
      RT_CONCAT,
      RT_EQUAL,
      RT_TO_S
    ]
  )
end

@doc """
compile_rc: a core form compiled through Perceus to a reference-counted executable; :exit ends with the value, :leaks with the count of blocks still live.

    compile_rc(read_forms("7")[0], :exit)[0] #=> 127
"""
def compile_rc(form, mode)
  executable(
    assemble(rc_program(perceus_program(closure_convert(anf(form))), mode))
  )
end

@doc """
rc_run: compile a form through Perceus to a reference-counted executable, run it in a mode, and answer its exit status.

    integer?(1) #=> true
"""
def rc_run(form, mode)
  run_status(form, (f) -> compile_rc(f, mode))
end

test "Perceus programs give their value and free every block on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    progs = append(take_n(PROGRAMS, 9), CLOSURE_PROGRAMS)
    map(
      fn(p)
        form = read_forms(p[0])[0]
        assert rc_run(form, :exit) == p[1]
        assert rc_run(form, :leaks) == 0
      end,
      progs
    )
  end
end

test "the reference-counted code tags, allocates and calls the runtime"
  assert tagged_atom([], 20, "rax") == [{op: "mov", dst: "rax", imm: 41}]
  assert tagged_atom([], false, "rax") == [{op: "mov", dst: "rax", imm: 0}]
  assert tagged_atom([], true, "rax") == [{op: "mov", dst: "rax", imm: 2}]
  assert last(rc_op([], "+", [1, 2])) == {op: "sub", dst: "rax", imm: 1}
  assert last(rc_op(["x"], "drop", [read_forms("x")[0]])) ==
    {op: "call_label", label: "rt_drop"}
  assert rc_op([], "dup", [1])[1] == {op: "call_label", label: "rt_dup"}
  assert rc_closure([], "f", [1])[1] == {op: "call_label", label: "rt_alloc"}
  assert last(call_code(["f"], read_forms("f")[0], [], tagged_atom)) ==
    {op: "call_r11"}
  assert length(rc_rhs([], read_forms("(* 2 3)")[0])) == 6
  assert rc_names(read_forms("(let (_ (dup x)) (ret 1))")[0]) == []
  assert rc_gen([], read_forms("(ret 3)")[0], :exit, 0)[0][0] ==
    {op: "mov", dst: "rax", imm: 7}
  assert nth(
    0,
    nth(
      0,
      rc_function(
        {label: "f", params: [], captured: [], body: read_forms("(ret 1)")[0]},
        0
      )
    )
  ) == {op: "label", name: "f"}
  assert RT_ALLOC[0] == {op: "label", name: "rt_alloc"}
  assert RT_DUP[0] == {op: "label", name: "rt_dup"}
  assert RT_DROP[0] == {op: "label", name: "rt_drop"}
  assert length(not_a_block("x")) == 6
  assert times8("rcx")[0] == {op: "add", dst: "rcx", src: "rcx"}
  assert last(tagged_compare("l")) == {op: "add", dst: "rax", src: "rax"}
  assert nth(
    0,
    rc_program(perceus_program(closure_convert(anf(read_forms("1")[0]))), :exit)
  ) == {op: "push_rbp"}
  assert compile_rc(read_forms("1")[0], :leaks)[1] == 69
  refused = begin
    rc_op([], "frob", [1])
  rescue e
    e.kind
  end
  assert refused == :unsupported
end

@doc """
cons_code: allocate a cons cell [kind, count, size, head, tail] with the head loaded by one sequence into rcx and the tail by another into rbx; the references move into the cell, answered in rax.

    cons_code([], [])[0] #=> {op: "mov", dst: "rdi", imm: 5}
"""
def cons_code(head, tail)
  append(
    *[
      [{op: "mov", dst: "rdi", imm: 5}, {op: "call_label", label: "rt_alloc"}],
      tail,
      [
        {op: "store", src: "rbx", base: "rax", disp: 32},
        {op: "push", src: "rax"}
      ],
      head,
      [
        {op: "pop", dst: "rax"},
        {op: "store", src: "rcx", base: "rax", disp: 24},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rax", disp: 0}
      ]
    ]
  )
end

@doc """
list_code: a list of atoms built from its last element to its first, each a cons onto the list so far, which stays in rbx; the empty list is 0.

    list_code([], []) #=> [{op: "mov", dst: "rax", imm: 0}]
"""
def list_code(slots, args)
  if length(args) == 0
    [{op: "mov", dst: "rax", imm: 0}]
  else
    append(
      [{op: "mov", dst: "rbx", imm: 0}],
      flat_map(
        reverse(args),
        fn(a)
          append(
            cons_code(tagged_atom(slots, a, "rcx"), []),
            [{op: "mov", dst: "rbx", src: "rax"}]
          )
        end
      )
    )
  end
end

@doc """
part_code: the head (offset 24) or the tail (offset 32) of a list: the part gets its own reference, then the list, which the operation consumed, is dropped.

    length(part_code([], 1, 24)) #=> 9
"""
def part_code(slots, l, offset)
  append(
    tagged_atom(slots, l, "rdi"),
    [
      {op: "load", dst: "rax", base: "rdi", disp: offset},
      {op: "push", src: "rax"},
      {op: "push", src: "rdi"},
      {op: "mov", dst: "rdi", src: "rax"},
      {op: "call_label", label: "rt_dup"},
      {op: "pop", dst: "rdi"},
      {op: "call_label", label: "rt_drop"},
      {op: "pop", dst: "rax"}
    ]
  )
end

@doc """
RT_LENGTH: the number of cells of the list in rdi, tagged, in rax; the list is only read.

    RT_LENGTH[0] #=> {op: "label", name: "rt_length"}
"""
RT_LENGTH = [
  {op: "label", name: "rt_length"},
  {op: "mov", dst: "rax", imm: 1},
  {op: "mov", dst: "rdx", src: "rdi"},
  {op: "label", name: "rt_length_loop"},
  {op: "cmp", dst: "rdx", imm: 0},
  {op: "j", cond: "e", label: "rt_length_out"},
  {op: "add", dst: "rax", imm: 2},
  {op: "load", dst: "rdx", base: "rdx", disp: 32},
  {op: "jmp", label: "rt_length_loop"},
  {op: "label", name: "rt_length_out"},
  {op: "ret"}
]

@doc """
LIST_PROGRAMS: programs over lists and the exit status each must give.

    LIST_PROGRAMS[0][1] #=> 7
"""
LIST_PROGRAMS = [
  ["(first (list 7 8 9))", 7],
  ["(first (rest (list 7 8 9)))", 8],
  ["(length (list 1 2 3 4))", 4],
  ["(let ((l (list 5 6))) (+ (first l) (length l)))", 7],
  ["(length (cons 1 (cons 2 (list))))", 2],
  [
    "(let ((l (list 1 2 3))) (let ((f (lambda (x) (+ x (length l))))) (f 10)))",
    13
  ],
  ["(let ((l (list 4 5))) (+ (first l) (first (rest l))))", 9]
]

test "list programs give their value and free every cell on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        form = read_forms(p[0])[0]
        assert rc_run(form, :exit) == p[1]
        assert rc_run(form, :leaks) == 0
      end,
      LIST_PROGRAMS
    )
  end
end

test "lists are cons cells built from the end, and a part keeps its own reference"
  assert list_code([], []) == [{op: "mov", dst: "rax", imm: 0}]
  assert list_code([], [1])[0] == {op: "mov", dst: "rbx", imm: 0}
  assert cons_code([], [])[1] == {op: "call_label", label: "rt_alloc"}
  p = part_code([], 1, 32)
  assert p[1] == {op: "load", dst: "rax", base: "rdi", disp: 32}
  assert member?({op: "call_label", label: "rt_dup"}, p)
  assert member?({op: "call_label", label: "rt_drop"}, p)
  assert RT_LENGTH[0] == {op: "label", name: "rt_length"}
  assert length(LIST_PROGRAMS) == 7
  assert member?(
    {op: "call_label", label: "rt_length"},
    rc_op([], "length", [1])
  )
end

@doc """
rc_gcall: a direct call to a global function: the arguments in ARG_REGS and a call to its label.

    last(rc_gcall([], "f", [1])) #=> {op: "call_label", label: "g_f"}
"""
def rc_gcall(slots, name, args)
  if length(args) > 6
    raise(:unsupported, "hashiru: a call passes at most six arguments")
  end
  append(
    flat_map(
      range(0, length(args)),
      (k) -> tagged_atom(slots, args[k], ARG_REGS[k])
    ),
    [{op: "call_label", label: "g_#{name}"}]
  )
end

@doc """
rc_global: one global function: its label, a frame with a slot per parameter and bound name, the parameters stored from ARG_REGS, then its body returning in rax.

    rc_global({name: "f", params: [], body: read_forms("(ret 1)")[0]}, 0)[0][0] #=> {op: "label", name: "g_f"}
"""
def rc_global(g, n)
  slots = append(g[:params], rc_names(g[:body]))
  body = rc_gen(slots, g[:body], :return, n)
  [
    append(
      *[
        [
          {op: "label", name: "g_#{g[:name]}"},
          {op: "push_rbp"},
          {op: "mov", dst: "rbp", src: "rsp"},
          {op: "sub", dst: "rsp", imm: 8 * length(slots)}
        ],
        flat_map(
          range(0, length(g[:params])),
          fn(k)
            [{op: "store", src: ARG_REGS[k], disp: slot(slots, g[:params][k])}]
          end
        ),
        body[0]
      ]
    ),
    body[1]
  ]
end

@doc """
rc_whole: the instructions of a program with global functions: rc_program's frame, heap, main and closures, then every global function, then the runtime.

    rc_whole(whole(read_forms("7")[0]), :exit)[0] #=> {op: "push_rbp"}
"""
def rc_whole(w, mode)
  base = rc_program({main: w[:main], fns: w[:fns]}, mode)
  start = length(base) -
    length(RT_ALLOC) -
    length(RT_DUP) -
    length(RT_DROP) -
    length(RT_LENGTH) -
    length(RT_GET) -
    length(RT_IS_ERROR) -
    length(RT_PAYLOAD) -
    length(RT_CONCAT) -
    length(RT_EQUAL) -
    length(RT_TO_S)
  globals = reduce(
    fn(acc, g)
      c = rc_global(g, acc[1])
      [append(acc[0], c[0]), c[1]]
    end,
    [[], 100_000],
    w[:globals]
  )
  append(
    *[
      take_n(base, start),
      globals[0],
      drop_n(base, start),
      static_data(
        append(
          literals_in(w[:main]),
          flat_map(append(w[:fns], w[:globals]), (f) -> literals_in(f[:body]))
        )
      )
    ]
  )
end

@doc """
compile_whole: a program with global functions compiled through Perceus to a reference-counted executable.

    compile_whole(read_forms("7")[0], :exit)[0] #=> 127
"""
def compile_whole(form, mode)
  executable(assemble(rc_whole(whole(form), mode)), true)
end

@doc """
RECURSIVE_PROGRAMS: programs with recursive global functions and the exit status each must give.

    RECURSIVE_PROGRAMS[0][1] #=> 120
"""
RECURSIVE_PROGRAMS = [
  [
    "(begin (define (fact n) (if (< n 2) 1 (* n (fact (- n 1))))) (fact 5))",
    120
  ],
  [
    "(begin (define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 10))",
    55
  ],
  [
    "(begin (define (sum l) (if (equal? (length l) 0) 0 (+ (first l) (sum (rest l))))) (sum (list 1 2 3 4)))",
    10
  ],
  [
    "(begin (define (count n acc) (if (equal? n 0) acc (count (- n 1) (+ acc 1)))) (count 200 0))",
    200
  ],
  [
    "(begin (define (twice f x) (f (f x))) (define (add k) (lambda (x) (+ x k))) (twice (add 20) 2))",
    42
  ]
]

test "recursive programs give their value and free every block on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "w.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_whole(form, :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
        write_bytes(path, compile_whole(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      RECURSIVE_PROGRAMS
    )
  end
end

test "a global function is a label called directly, its parameters from ARG_REGS"
  g = nth(
    0,
    rc_global({name: "f", params: ["x"], body: read_forms("(ret x)")[0]}, 0)
  )
  assert g[0] == {op: "label", name: "g_f"}
  assert g[4] == {op: "store", src: "rdi", disp: -8}
  assert last(rc_gcall([], "f", [1, 2])) == {op: "call_label", label: "g_f"}
  insns = rc_whole(whole(read_forms("(begin (define (f) 1) (f))")[0]), :exit)
  assert member?({op: "label", name: "g_f"}, insns)
  assert last(insns) == {op: "ret"}
  assert length(RECURSIVE_PROGRAMS) == 5
  assert compile_whole(read_forms("1")[0], :exit)[1] == 69
end

@doc """
str_label: the label of a string literal's static block, from its bytes, so equal literals share one block.

    str_label("hi") #=> "str_6869"
"""
def str_label(s)
  concat("str_", hex_encode(s))
end

@doc """
strings_in: every distinct string literal anywhere in a tree, in first-seen order.

    strings_in(["a", ["b", "a"], 3]) #=> ["a", "b"]
"""
def strings_in(x)
  if string?(x) or keyword?(x)
    [x]
  elsif list?(x)
    reduce(
      fn(acc, c)
        reduce(
          fn(a2, s)
            if member?(s, a2)
              a2
            else
              append(a2, [s])
            end
          end,
          acc,
          strings_in(c)
        )
      end,
      [],
      x
    )
  else
    []
  end
end

@doc """
IMMORTAL: the count a static block starts with, so high that no program's drops reach zero: a literal is never freed.

    IMMORTAL #=> 1_099_511_627_776
"""
IMMORTAL = 1_099_511_627_776

@doc """
string_block: the bytes of a static string block: kind 1, an immortal count, its size in words, its length in bytes, then its UTF-8 bytes padded to a word.

    length(string_block("hi")) #=> 40
"""
def string_block(s)
  b = text_bytes(s)
  words = floor((length(b) + 7) / 8)
  pad = map((k) -> 0, range(0, words * 8 - length(b)))
  append(*[le64(1), le64(IMMORTAL), le64(4 + words), le64(length(b)), b, pad])
end

@doc """
string_data: the data section of a program: each literal's label and its static block.

    string_data([])  #=> []
"""
def string_data(strings)
  flat_map(
    strings,
    fn(s)
      [{op: "label", name: str_label(s)}, {op: "bytes", bytes: string_block(s)}]
    end
  )
end

@doc """
STRING_PROGRAMS: programs over strings, with the exit status and the output each must give.

    STRING_PROGRAMS[1][1] #=> 4
"""
STRING_PROGRAMS = [
  [
    "(begin (write_stdout \"hello, world\\n\") 0)",
    0,
    unlines(["hello, world"])
  ],
  ["(string_length \"blue\")", 4, ""],
  ["(let ((s \"ab\")) (+ (string_length s) (string_length s)))", 4, ""],
  [
    "(begin (define (greet s) (write_stdout s)) (greet \"hi\\n\") (greet \"there\\n\") 7)",
    7,
    unlines(%w[hi there])
  ],
  [
    "(let ((f (lambda (x) (write_stdout x)))) (begin (f \"one\\n\") (f \"two\\n\") 2))",
    2,
    unlines(%w[one two])
  ]
]

test "string programs print, exit with their value and free all on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "s.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_whole(form, :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_whole(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      STRING_PROGRAMS
    )
  end
end

test "a string literal is one immortal static block, labelled by its bytes"
  assert str_label("hi") == "str_6869"
  assert strings_in(read_forms("(write_stdout \"a\") (f \"a\" \"b\")")) ==
    %w[a b]
  b = string_block("hi")
  assert slice(b, 0, 8) == le64(1)
  assert slice(b, 24, 8) == le64(2)
  assert slice(b, 32, 2) == [104, 105]
  assert length(b) % 8 == 0
  assert IMMORTAL > 1_000_000_000
  assert string_data(["x"])[0] == {op: "label", name: "str_78"}
  assert tagged_atom([], "x", "rcx") ==
    [{op: "lea_label", dst: "rcx", label: "str_78"}]
  assert member?({op: "syscall"}, rc_op([], "write_stdout", ["x"]))
  assert length(STRING_PROGRAMS) == 5
  assert literals_in(
    read_forms("(let (t (gcall \"f\" \"x\")) (ret \"y\"))")[0]
  ) == %w[x y]
end

@doc """
literals_in: the string literals a term uses as values, in first-seen order: the label of a closure and the name of a global call are names, not values, and are left out.

    literals_in(read_forms("(let (t (gcall \"f\" \"x\")) (ret t))")[0]) #=> ["x"]
"""
def literals_in(term)
  if head_is?(term, "ret")
    strings_in([term[1]])
  else
    rhs = term[1][1]
    here = if head_is?(rhs, "if")
      append(
        strings_in([rhs[1]]),
        append(literals_in(rhs[2]), literals_in(rhs[3]))
      )
    elsif head_is?(rhs, "closure") or head_is?(rhs, "gcall")
      strings_in(rest(rest(rhs)))
    else
      strings_in(rest(rhs))
    end
    strings_in([here, literals_in(term[2])])
  end
end

@doc """
kw_label: the label of a keyword's static block, from its name, so every use of one keyword is one block and keywords compare by identity.

    kw_label(:ab) #=> "kw_6162"
"""
def kw_label(k)
  "kw_#{hex_encode(replace(to_s(k), ":", ""))}"
end

@doc """
keyword_block: the bytes of a keyword's static block: kind 2, an immortal count, size 3; a keyword carries nothing but its identity.

    length(keyword_block) #=> 24
"""
def keyword_block()
  append(*[le64(2), le64(IMMORTAL), le64(3)])
end

@doc """
static_data: the data section: each string literal's block and each keyword's block, under its label.

    static_data([:a])[1] #=> {op: "label", name: "kw_61"}
"""
def static_data(values)
  flat_map(
    values,
    fn(v)
      if keyword?(v)
        [
          {op: "align", to: 8},
          {op: "label", name: kw_label(v)},
          {op: "bytes", bytes: keyword_block}
        ]
      else
        [
          {op: "align", to: 8},
          {op: "label", name: str_label(v)},
          {op: "bytes", bytes: string_block(v)}
        ]
      end
    end
  )
end

@doc """
entry_code: put a new entry (key . value) in front of the map held in rbx, answering the new map in rax and leaving it in rbx; the key, the value and the map move into it.

    entry_code([], :a, 1)[0] #=> {op: "push", src: "rbx"}
"""
def entry_code(slots, k, v)
  append(
    *[
      [{op: "push", src: "rbx"}],
      cons_code(tagged_atom(slots, k, "rcx"), tagged_atom(slots, v, "rbx")),
      [
        {op: "pop", dst: "rbx"},
        {op: "push", src: "rax"},
        {op: "mov", dst: "rdi", imm: 5},
        {op: "call_label", label: "rt_alloc"},
        {op: "store", src: "rbx", base: "rax", disp: 32},
        {op: "pop", dst: "rcx"},
        {op: "store", src: "rcx", base: "rax", disp: 24},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rax", disp: 0},
        {op: "mov", dst: "rbx", src: "rax"}
      ]
    ]
  )
end

@doc """
map_code: a map from key and value atoms, built from its last pair to its first, an association list of (key . value) cells; the empty map is 0.

    map_code([], [])[1] #=> {op: "mov", dst: "rbx", imm: 0}
"""
def map_code(slots, args)
  pairs = map(
    (k) -> [args[2 * k], args[2 * k + 1]],
    range(0, floor(length(args) / 2))
  )
  append(
    *[
      [{op: "push", src: "rbx"}, {op: "mov", dst: "rbx", imm: 0}],
      flat_map(reverse(pairs), (p) -> entry_code(slots, p[0], p[1])),
      [{op: "mov", dst: "rax", src: "rbx"}, {op: "pop", dst: "rbx"}]
    ]
  )
end

@doc """
get_code: the value a map holds for a key, or nil: the answer gets its own reference, then the map and the key, which the operation consumed, are dropped.

    last(get_code([], 1, :a)) #=> {op: "pop", dst: "rax"}
"""
def get_code(slots, m, k)
  append(
    *[
      tagged_atom(slots, m, "rdi"),
      tagged_atom(slots, k, "rsi"),
      [
        {op: "push", src: "rdi"},
        {op: "push", src: "rsi"},
        {op: "call_label", label: "rt_get"},
        {op: "push", src: "rax"},
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "call_label", label: "rt_dup"},
        {op: "pop", dst: "rax"},
        {op: "pop", dst: "rsi"},
        {op: "pop", dst: "rdi"},
        {op: "push", src: "rax"},
        {op: "push", src: "rsi"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rdi"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rax"}
      ]
    ]
  )
end

@doc """
RT_GET: the value the map in rdi holds for the key in rsi, compared by identity, or nil (0); the map is only read.

    RT_GET[0] #=> {op: "label", name: "rt_get"}
"""
RT_GET = [
  {op: "label", name: "rt_get"},
  {op: "mov", dst: "rdx", src: "rdi"},
  {op: "label", name: "rt_get_loop"},
  {op: "cmp", dst: "rdx", imm: 0},
  {op: "j", cond: "e", label: "rt_get_none"},
  {op: "load", dst: "rax", base: "rdx", disp: 24},
  {op: "load", dst: "rcx", base: "rax", disp: 24},
  {op: "cmp", dst: "rcx", src: "rsi"},
  {op: "j", cond: "e", label: "rt_get_hit"},
  {op: "load", dst: "rdx", base: "rdx", disp: 32},
  {op: "jmp", label: "rt_get_loop"},
  {op: "label", name: "rt_get_hit"},
  {op: "load", dst: "rax", base: "rax", disp: 32},
  {op: "ret"},
  {op: "label", name: "rt_get_none"},
  {op: "mov", dst: "rax", imm: 0},
  {op: "ret"}
]

@doc """
MAP_PROGRAMS: programs over maps and keywords and the exit status each must give.

    MAP_PROGRAMS[0][1] #=> 2
"""
MAP_PROGRAMS = [
  ["(get (hash-map :a 1 :b 2) :b)", 2],
  ["(let ((m (hash-map :x 40))) (+ (get m :x) (get (assoc m :y 2) :y)))", 42],
  ["(get (hash-map :a 1) :z)", 0],
  [
    "(let ((m (hash-map :k 5))) (let ((f (lambda (key) (get m key)))) (* (f :k) 2)))",
    10
  ],
  ["(let ((m (assoc (hash-map :a 1) :a 9))) (get m :a))", 9],
  [
    "(begin (define (pick m) (+ (get m :p) (get m :q))) (pick (hash-map :p 30 :q 12)))",
    42
  ]
]

test "map programs give their value and free every block on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "m.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_whole(form, :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
        write_bytes(path, compile_whole(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      MAP_PROGRAMS
    )
  end
end

test "keywords are static blocks by name, and a map is an association list"
  assert kw_label(:p) == "kw_70"
  assert slice(keyword_block, 0, 8) == le64(2)
  assert static_data([:a, "x"])[4] == {op: "label", name: "str_78"}
  assert tagged_atom([], :a, "rsi") ==
    [{op: "lea_label", dst: "rsi", label: "kw_61"}]
  assert map_code([], [])[0] == {op: "push", src: "rbx"}
  assert member?({op: "call_label", label: "rt_get"}, get_code([], 1, :a))
  assert entry_code([], :a, 1)[0] == {op: "push", src: "rbx"}
  assert RT_GET[0] == {op: "label", name: "rt_get"}
  assert strings_in(read_forms("(f :a \"b\")")) == [:a, "b"]
  assert length(MAP_PROGRAMS) == 6
end

@doc """
COND_PROGRAMS: programs with cond and case and the exit status each must give.

    COND_PROGRAMS[0][1] #=> 20
"""
COND_PROGRAMS = [
  ["(cond ((< 2 1) 10) ((< 1 2) 20) (else 30))", 20],
  [
    "(begin (define (grade n) (let ((case-subject n)) (cond ((equal? case-subject 1) 10) ((equal? case-subject 2) 20) (else 30)))) (+ (grade 2) (grade 7)))",
    50
  ],
  [
    "(begin (define (classify l) (cond ((equal? (length l) 0) 1) ((equal? (length l) 1) 2) (else 3))) (+ (classify (list)) (classify (list 5 6))))",
    4
  ]
]

test "cond programs give their value and free every block on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "k.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_whole(form, :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
        write_bytes(path, compile_whole(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      COND_PROGRAMS
    )
  end
end

test "cond compiles to the compares and jumps of nested ifs"
  insns = rc_whole(whole(read_forms(COND_PROGRAMS[0][0])[0]), :exit)
  assert length(filter((i) -> i[:op] == "j", insns)) >= 2
  assert length(COND_PROGRAMS) == 3
end

@doc """
RT_IS_ERROR: true (2) when rdi is an error block (kind 4), false (0) for anything else; the value is only read.

    RT_IS_ERROR[0] #=> {op: "label", name: "rt_is_error"}
"""
RT_IS_ERROR = append(
  *[
    [{op: "label", name: "rt_is_error"}],
    not_a_block("rt_is_error_no"),
    [
      {op: "load", dst: "rcx", base: "rdi", disp: 0},
      {op: "cmp", dst: "rcx", imm: 4},
      {op: "j", cond: "ne", label: "rt_is_error_no"},
      {op: "mov", dst: "rax", imm: 2},
      {op: "ret"},
      {op: "label", name: "rt_is_error_no"},
      {op: "mov", dst: "rax", imm: 0},
      {op: "ret"}
    ]
  ]
)

@doc """
RT_PAYLOAD: what the error block in rdi was raised with, with its own reference; the error block, consumed, is dropped.

    RT_PAYLOAD[0] #=> {op: "label", name: "rt_payload"}
"""
RT_PAYLOAD = [
  {op: "label", name: "rt_payload"},
  {op: "load", dst: "rax", base: "rdi", disp: 24},
  {op: "push", src: "rax"},
  {op: "push", src: "rdi"},
  {op: "mov", dst: "rdi", src: "rax"},
  {op: "call_label", label: "rt_dup"},
  {op: "pop", dst: "rdi"},
  {op: "call_label", label: "rt_drop"},
  {op: "pop", dst: "rax"},
  {op: "ret"}
]

@doc """
TRY_PROGRAMS: programs with raise and try, and the exit status each must give.

    TRY_PROGRAMS[2][1] #=> 141
"""
TRY_PROGRAMS = [
  ["(try (raise 7) (catch (e) (+ e 1)))", 8],
  ["(try (+ 1 2) (catch (e) 0))", 3],
  [
    "(begin (define (div a b) (if (equal? b 0) (raise 99) (* a b))) (+ (try (div 6 7) (catch (e) 0)) (try (div 1 0) (catch (e) e))))",
    141
  ],
  [
    "(begin (define (inner l) (if (equal? (length l) 0) (raise 5) (first l))) (define (outer l) (+ 1 (inner l))) (try (outer (list)) (catch (e) (* e 2))))",
    10
  ],
  [
    "(let ((l (list 1 2 3))) (try (begin (length l) (raise 4)) (catch (e) (+ e (length l)))))",
    7
  ]
]

test "try programs give their value and free all on every path on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "t.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_whole(form, :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
        write_bytes(path, compile_whole(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      TRY_PROGRAMS
    )
  end
end

test "an error is a kind-4 block, and a try calls its handler only on one"
  r = rc_op(["x"], "raise", [read_forms("x")[0]])
  assert member?({op: "mov", dst: "rdi", imm: 4}, r)
  assert member?(
    {op: "call_label", label: "rt_is_error"},
    rc_op(["x"], "failed?", [read_forms("x")[0]])
  )
  insns = rc_whole(whole(read_forms(TRY_PROGRAMS[0][0])[0]), :exit)
  assert member?({op: "call_label", label: "rt_payload"}, insns)
  assert member?({op: "call_r11"}, insns)
  assert RT_IS_ERROR[0] == {op: "label", name: "rt_is_error"}
  assert RT_PAYLOAD[0] == {op: "label", name: "rt_payload"}
  assert length(TRY_PROGRAMS) == 5
end

@doc """
PRELUDE: the list words every compiled program can call, written in blue's core forms and compiled with it: what blue's runtime gives as builtins, here as ordinary global functions over cons, first, rest and length, freed by Perceus like any other code.

    length(PRELUDE) > 0 #=> true
"""
PRELUDE = [
  "(define (append a b) (if (equal? (length a) 0) b (cons (first a) (append (rest a) b))))",
  "(define (nth i l) (if (equal? i 0) (first l) (nth (- i 1) (rest l))))",
  "(define (reverse_onto l acc) (if (equal? (length l) 0) acc (reverse_onto (rest l) (cons (first l) acc))))",
  "(define (reverse l) (reverse_onto l (list)))",
  "(define (map f l) (if (equal? (length l) 0) (list) (cons (f (first l)) (map f (rest l)))))",
  "(define (filter f l) (if (equal? (length l) 0) (list) (if (f (first l)) (cons (first l) (filter f (rest l))) (filter f (rest l)))))",
  "(define (reduce f acc l) (if (equal? (length l) 0) acc (reduce f (f acc (first l)) (rest l))))"
]

@doc """
with_prelude: a program with the prelude's definitions placed before its own, so it can call them by name.

    head_is?(with_prelude(read_forms("7")[0]), "begin") #=> true
"""
def with_prelude(form)
  defs = map((s) -> read_forms(s)[0], PRELUDE)
  body = if head_is?(form, "begin")
    rest(form)
  else
    [form]
  end
  cons(read_forms("begin")[0], append(defs, body))
end

@doc """
compile_program: a program compiled with the prelude through Perceus to a reference-counted executable.

    compile_program(read_forms("7")[0], :exit)[0] #=> 127
"""
def compile_program(form, mode)
  compile_whole(with_prelude(form), mode)
end

@doc """
PRELUDE_PROGRAMS: programs over the prelude's list words and the exit status each must give.

    PRELUDE_PROGRAMS[0][1] #=> 4
"""
PRELUDE_PROGRAMS = [
  ["(length (append (list 1 2) (list 3 4)))", 4],
  ["(nth 2 (list 10 20 30 40))", 30],
  ["(first (reverse (list 1 2 3)))", 3],
  [
    "(reduce (lambda (a x) (+ a x)) 0 (map (lambda (x) (* x 2)) (list 1 2 3 4 5 6)))",
    42
  ],
  ["(length (filter (lambda (x) (> x 2)) (list 1 2 3 4 5)))", 3],
  [
    "(let ((k 3)) (reduce (lambda (a x) (+ a x)) 0 (map (lambda (x) (* x k)) (list 1 2 3))))",
    18
  ]
]

test "prelude programs give their value and free every block on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "p.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_program(form, :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
        write_bytes(path, compile_program(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      PRELUDE_PROGRAMS
    )
  end
end

test "the prelude's words are global functions placed before the program"
  p = with_prelude(read_forms("(begin (define (f) 1) (f))")[0])
  assert head_is?(p, "begin")
  assert length(rest(p)) == length(PRELUDE) + 2
  w = whole(with_prelude(read_forms("(nth 0 (list 5))")[0]))
  assert member?("nth", map((g) -> g[:name], w[:globals]))
  assert length(PRELUDE_PROGRAMS) == 6
end

@doc """
copy_bytes: the instructions that copy a count of bytes, the count in one register, from the address in rdx to the address in r11, both advancing; rcx is used for each byte.

    length(copy_bytes("r8", "x")) #=> 10
"""
def copy_bytes(count, tag)
  [
    {op: "label", name: "#{tag}_loop"},
    {op: "cmp", dst: count, imm: 0},
    {op: "j", cond: "e", label: "#{tag}_done"},
    {op: "load_byte", dst: "rcx", base: "rdx"},
    {op: "store_byte", src: "rcx", base: "r11"},
    {op: "add", dst: "rdx", imm: 1},
    {op: "add", dst: "r11", imm: 1},
    {op: "sub", dst: count, imm: 1},
    {op: "jmp", label: "#{tag}_loop"},
    {op: "label", name: "#{tag}_done"}
  ]
end

@doc """
RT_CONCAT: a new string holding the bytes of the string in rdi then those of the string in rsi, answered in rax; both inputs, consumed, are dropped.

    RT_CONCAT[0] #=> {op: "label", name: "rt_concat"}
"""
RT_CONCAT = append(
  *[
    [
      {op: "label", name: "rt_concat"},
      {op: "load", dst: "r8", base: "rdi", disp: 24},
      {op: "load", dst: "r9", base: "rsi", disp: 24},
      {op: "mov", dst: "r10", src: "r8"},
      {op: "add", dst: "r10", src: "r9"},
      {op: "push", src: "rdi"},
      {op: "push", src: "rsi"},
      {op: "mov", dst: "rdi", src: "r10"},
      {op: "add", dst: "rdi", imm: 7},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "add", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "pop", dst: "rsi"},
      {op: "pop", dst: "rdi"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "store", src: "r10", base: "rax", disp: 24},
      {op: "mov", dst: "r11", src: "rax"},
      {op: "add", dst: "r11", imm: 32},
      {op: "mov", dst: "rdx", src: "rdi"},
      {op: "add", dst: "rdx", imm: 32}
    ],
    copy_bytes("r8", "rt_concat_a"),
    [{op: "mov", dst: "rdx", src: "rsi"}, {op: "add", dst: "rdx", imm: 32}],
    copy_bytes("r9", "rt_concat_b"),
    [
      {op: "push", src: "rax"},
      {op: "push", src: "rsi"},
      {op: "call_label", label: "rt_drop"},
      {op: "pop", dst: "rdi"},
      {op: "call_label", label: "rt_drop"},
      {op: "pop", dst: "rax"},
      {op: "ret"}
    ]
  ]
)

@doc """
RT_EQUAL: true (2) or false (0) for whether the values in rdi and rsi are equal: the same word is equal; two strings are equal when their bytes are; two lists are equal when their heads are equal and their tails are, element by element; anything else is compared by identity. Both values are only read.

    RT_EQUAL[0] #=> {op: "label", name: "rt_equal"}
"""
RT_EQUAL = [
  {op: "label", name: "rt_equal"},
  {op: "cmp", dst: "rdi", src: "rsi"},
  {op: "j", cond: "e", label: "rt_equal_yes"},
  {op: "mov", dst: "rax", src: "rdi"},
  {op: "and", dst: "rax", imm: 1},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ne", label: "rt_equal_no"},
  {op: "mov", dst: "rax", src: "rsi"},
  {op: "and", dst: "rax", imm: 1},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ne", label: "rt_equal_no"},
  {op: "cmp", dst: "rdi", imm: 4096},
  {op: "j", cond: "l", label: "rt_equal_no"},
  {op: "cmp", dst: "rsi", imm: 4096},
  {op: "j", cond: "l", label: "rt_equal_no"},
  {op: "load", dst: "rax", base: "rdi", disp: 0},
  {op: "load", dst: "rcx", base: "rsi", disp: 0},
  {op: "cmp", dst: "rax", src: "rcx"},
  {op: "j", cond: "ne", label: "rt_equal_no"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "e", label: "rt_equal_cells"},
  {op: "cmp", dst: "rax", imm: 1},
  {op: "j", cond: "ne", label: "rt_equal_no"},
  {op: "load", dst: "r8", base: "rdi", disp: 24},
  {op: "load", dst: "rax", base: "rsi", disp: 24},
  {op: "cmp", dst: "r8", src: "rax"},
  {op: "j", cond: "ne", label: "rt_equal_no"},
  {op: "mov", dst: "rdx", src: "rdi"},
  {op: "add", dst: "rdx", imm: 32},
  {op: "mov", dst: "r11", src: "rsi"},
  {op: "add", dst: "r11", imm: 32},
  {op: "label", name: "rt_equal_loop"},
  {op: "cmp", dst: "r8", imm: 0},
  {op: "j", cond: "e", label: "rt_equal_yes"},
  {op: "load_byte", dst: "rax", base: "rdx"},
  {op: "load_byte", dst: "rcx", base: "r11"},
  {op: "cmp", dst: "rax", src: "rcx"},
  {op: "j", cond: "ne", label: "rt_equal_no"},
  {op: "add", dst: "rdx", imm: 1},
  {op: "add", dst: "r11", imm: 1},
  {op: "sub", dst: "r8", imm: 1},
  {op: "jmp", label: "rt_equal_loop"},
  {op: "label", name: "rt_equal_cells"},
  {op: "push", src: "rdi"},
  {op: "push", src: "rsi"},
  {op: "load", dst: "rdi", base: "rdi", disp: 24},
  {op: "load", dst: "rsi", base: "rsi", disp: 24},
  {op: "call_label", label: "rt_equal"},
  {op: "pop", dst: "rsi"},
  {op: "pop", dst: "rdi"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "e", label: "rt_equal_no"},
  {op: "load", dst: "rdi", base: "rdi", disp: 32},
  {op: "load", dst: "rsi", base: "rsi", disp: 32},
  {op: "jmp", label: "rt_equal"},
  {op: "label", name: "rt_equal_yes"},
  {op: "mov", dst: "rax", imm: 2},
  {op: "ret"},
  {op: "label", name: "rt_equal_no"},
  {op: "mov", dst: "rax", imm: 0},
  {op: "ret"}
]

@doc """
concat_code: the strings of its arguments joined left to right, each join through rt_concat, which consumes both sides.

    last(concat_code([], ["a", "b"])) #=> {op: "call_label", label: "rt_concat"}
"""
def concat_code(slots, args)
  append(
    tagged_atom(slots, args[0], "rax"),
    flat_map(
      rest(args),
      fn(a)
        append(
          [{op: "mov", dst: "rdi", src: "rax"}],
          append(
            tagged_atom(slots, a, "rsi"),
            [{op: "call_label", label: "rt_concat"}]
          )
        )
      end
    )
  )
end

@doc """
CONCAT_PROGRAMS: programs that join and compare strings, with the exit status and output each must give.

    CONCAT_PROGRAMS[0][1] #=> 5
"""
CONCAT_PROGRAMS = [
  ["(string_length (concat \"ab\" \"cde\"))", 5, ""],
  [
    "(begin (write_stdout (concat \"hello, \" \"blue\" \"\\n\")) 0)",
    0,
    unlines(["hello, blue"])
  ],
  ["(if (equal? (concat \"a\" \"b\") \"ab\") 1 2)", 1, ""],
  ["(if (equal? \"x\" \"y\") 1 2)", 2, ""],
  [
    "(begin (define (rep s n) (if (equal? n 0) \"\" (concat s (rep s (- n 1))))) (string_length (rep \"ab\" 10)))",
    20,
    ""
  ],
  ["(if (equal? (list 1 (list 2 3)) (list 1 (list 2 3))) 1 2)", 1, ""],
  ["(if (equal? (list 1 2) (list 1 3)) 1 2)", 2, ""],
  ["(if (equal? (list \"a\" \"b\") (list \"a\" \"b\")) 1 2)", 1, ""]
]

test "string-joining programs print, exit and free all on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "c.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_program(form, :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_program(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      CONCAT_PROGRAMS
    )
  end
end

test "concat joins through rt_concat, and equality goes through rt_equal and drops both sides"
  assert length(concat_code([], %w[a b c])) == 7
  e = rc_op(%w[a b], "equal?", [read_forms("a")[0], read_forms("b")[0]])
  assert member?({op: "call_label", label: "rt_equal"}, e)
  assert length(filter((i) -> i == {op: "call_label", label: "rt_drop"}, e)) ==
    2
  assert copy_bytes("r9", "t")[0] == {op: "label", name: "t_loop"}
  assert RT_CONCAT[0] == {op: "label", name: "rt_concat"}
  assert RT_EQUAL[0] == {op: "label", name: "rt_equal"}
  assert length(CONCAT_PROGRAMS) == 8
end

@doc """
RT_TO_S: the text of the value in rdi, answered in rax: an integer as its decimal digits in a new string, a string as itself (the reference the operation consumed is handed on).

    RT_TO_S[0] #=> {op: "label", name: "rt_to_s"}
"""
RT_TO_S = append(
  *[
    [
      {op: "label", name: "rt_to_s"},
      {op: "mov", dst: "rax", src: "rdi"},
      {op: "and", dst: "rax", imm: 1},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_to_s_int"},
      {op: "mov", dst: "rax", src: "rdi"},
      {op: "ret"},
      {op: "label", name: "rt_to_s_int"},
      {op: "mov", dst: "rax", src: "rdi"},
      {op: "sar1", dst: "rax"},
      {op: "mov", dst: "r8", imm: 0},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ge", label: "rt_to_s_pos"},
      {op: "mov", dst: "r8", imm: 1},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "sub", dst: "rcx", src: "rax"},
      {op: "mov", dst: "rax", src: "rcx"},
      {op: "label", name: "rt_to_s_pos"},
      {op: "sub", dst: "rsp", imm: 32},
      {op: "mov", dst: "r11", src: "rsp"},
      {op: "mov", dst: "r9", imm: 0},
      {op: "label", name: "rt_to_s_digit"},
      {op: "cqo"},
      {op: "mov", dst: "rcx", imm: 10},
      {op: "idiv", src: "rcx"},
      {op: "add", dst: "rdx", imm: 48},
      {op: "store_byte", src: "rdx", base: "r11"},
      {op: "add", dst: "r11", imm: 1},
      {op: "add", dst: "r9", imm: 1},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_to_s_digit"},
      {op: "cmp", dst: "r8", imm: 0},
      {op: "j", cond: "e", label: "rt_to_s_alloc"},
      {op: "mov", dst: "rdx", imm: 45},
      {op: "store_byte", src: "rdx", base: "r11"},
      {op: "add", dst: "r11", imm: 1},
      {op: "add", dst: "r9", imm: 1},
      {op: "label", name: "rt_to_s_alloc"},
      {op: "mov", dst: "rdi", src: "r9"},
      {op: "add", dst: "rdi", imm: 7},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "add", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "store", src: "r9", base: "rax", disp: 24},
      {op: "mov", dst: "rdx", src: "rax"},
      {op: "add", dst: "rdx", imm: 32},
      {op: "label", name: "rt_to_s_copy"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_to_s_done"},
      {op: "sub", dst: "r11", imm: 1},
      {op: "load_byte", dst: "rcx", base: "r11"},
      {op: "store_byte", src: "rcx", base: "rdx"},
      {op: "add", dst: "rdx", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_to_s_copy"},
      {op: "label", name: "rt_to_s_done"},
      {op: "add", dst: "rsp", imm: 32},
      {op: "ret"}
    ]
  ]
)

@doc """
TO_S_PROGRAMS: programs that print numbers, with the exit status and output each must give.

    TO_S_PROGRAMS[0][2] #=> "n=42\n"
"""
TO_S_PROGRAMS = [
  [
    "(begin (write_stdout (concat \"n=\" (to_s 42) \"\\n\")) 0)",
    0,
    unlines(["n=42"])
  ],
  ["(string_length (to_s -1234))", 5, ""],
  ["(begin (print (to_s 0)) 0)", 0, "0"],
  [
    "(begin (define (fact n) (if (< n 2) 1 (* n (fact (- n 1))))) (write_stdout (concat \"10! = \" (to_s (fact 10)) \"\\n\")) 0)",
    0,
    unlines(["10! = 3628800"])
  ],
  [
    "(begin (write_stdout (concat (to_s (reduce (lambda (a x) (+ a x)) 0 (list 1 2 3))) \"\\n\")) 0)",
    0,
    unlines(["6"])
  ]
]

test "number-printing programs print and free every block on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "n.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_program(form, :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_program(form, :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      TO_S_PROGRAMS
    )
  end
end

test "to_s calls the runtime, which divides by ten for each digit"
  assert last(rc_op([], "to_s", [5])) == {op: "call_label", label: "rt_to_s"}
  assert member?({op: "idiv", src: "rcx"}, RT_TO_S)
  assert RT_TO_S[0] == {op: "label", name: "rt_to_s"}
  assert length(TO_S_PROGRAMS) == 5
end

test "every primitive the code generators know emits code beside them, and an unknown one is refused"
  raw = %w[+ - * < > equal? syscall6 load_word store_word id dup]
  assert filter((o) -> length(op_code([], o, [1, 2])) == 0, raw) == []
  assert op_code([], "drop", [1]) == []
  assert (op_code([], "nope", [1, 2]) rescue :refused) == :refused
  tagged = %w[
    +
    -
    *
    <
    >
    equal?
    concat
    to_s
    cons
    list
    first
    rest
    raise
    failed?
    hash-map
    assoc
    get
    string_length
    write_stdout
    exit_with
    length
    id
    dup
  ]
  assert filter((o) -> length(rc_op([], o, [1, 2])) == 0, tagged) == []
  assert length(rhs_code(["f"], read_forms("(closure f)")[0])) > 0
  assert length(rhs_code(["f"], read_forms("(call f 1)")[0])) > 0
  assert length(rhs_code([], read_forms("(+ 1 2)")[0])) > 0
  seven = [1, 2, 3, 4, 5, 6, 7]
  assert (rc_gcall([], "f", seven) rescue :refused) == :refused
  assert (call_code([], 1, seven, tagged_atom) rescue :refused) == :refused
end

@doc """
HOST_PROGRAMS: programs over host words (R4 of docs/PURE-BLUE.md), with the exit status and the output each must give. A program that leaves through exit_with leaves before any block count, so these are judged by status and output alone.

    HOST_PROGRAMS[0][1] #=> 3
"""
HOST_PROGRAMS = [
  ["(begin (write_stdout \"bye\\n\") (exit_with 3))", 3, unlines(["bye"])],
  ["(begin (exit_with 0) (write_stdout \"never\"))", 0, ""],
  ["(exit_with (+ 40 2))", 42, ""]
]

test "host programs leave with exit_with's status and write what write_stdout is given on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "h.out")
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
      end,
      HOST_PROGRAMS
    )
  end
end

test "exit_with untags its status and calls exit, and print is refused until it prints as blue does"
  code = rc_op([], "exit_with", [3])
  assert member?({op: "mov", dst: "rax", imm: 60}, code)
  assert member?({op: "sar1", dst: "rdi"}, code)
  assert (rc_op([], "print", ["x"]) rescue :refused) == :refused
end
