@moduledoc """
hashiru (走る) — blue code that runs: kuzushi's A-normal form compiled to x86-64 instructions (kikaigo) inside a static executable (erufu), with no other language in the path (docs/PURE-BLUE.md B3).

This first code generator is the simplest correct one: every named value lives in its own stack slot below rbp, every operation loads its atoms into rax and rcx, computes in rax and stores the result back. A comparison leaves 1 or 0; an if tests its condition against 0 and jumps; a program's value becomes its exit status. Register allocation replaces the slots later; the slots are the oracle it must agree with.

    length(compile(read_forms("(+ 1 2)")[0])) > 120 #=> true
"""

use("kaaneru/erufu", [:executable])
use("kikaigo", %i[assemble le64])
use("kuzushi", %i[anf closure_convert head_is? perceus_program whole whole_in])
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
FREE_CLASSES: how many block sizes, in words, keep a free list in the table at r14 (its first word is the live count). A block this size or larger is bumped and never recycled, so it can never index past the table.

    FREE_CLASSES #=> 64
"""
FREE_CLASSES = 64

@doc """
HEAP_EXHAUSTED: the exit status of a program whose heap is used up (ENOMEM), instead of a write past the heap's end.

    HEAP_EXHAUSTED #=> 12
"""
HEAP_EXHAUSTED = 12

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
  map((_k) -> {op: "add", dst: r, src: r}, range(0, 3))
end

@doc """
LARGE_ALLOC: rt_alloc's path for a block of FREE_CLASSES words or more: its own anonymous mapping (mmap), so a large block never uses up the heap; every register mmap takes is saved, since rt_alloc's callers keep values in rsi, rdx and r8-r10 across it. A refused mapping exits with HEAP_EXHAUSTED.

    LARGE_ALLOC[0] #=> {op: "label", name: "rt_alloc_large"}
"""
LARGE_ALLOC = append(
  *[
    [
      {op: "label", name: "rt_alloc_large"},
      {op: "push", src: "rsi"},
      {op: "push", src: "rdx"},
      {op: "push", src: "r8"},
      {op: "push", src: "r9"},
      {op: "push", src: "r10"},
      {op: "push", src: "rdi"},
      {op: "mov", dst: "rsi", src: "rdi"}
    ],
    times8("rsi"),
    [
      {op: "mov", dst: "rdi", imm: 0},
      {op: "mov", dst: "rdx", imm: 3},
      {op: "mov", dst: "r10", imm: 34},
      {op: "mov", dst: "r8", imm: -1},
      {op: "mov", dst: "r9", imm: 0},
      {op: "mov", dst: "rax", imm: 9},
      {op: "syscall"},
      {op: "pop", dst: "rdi"},
      {op: "pop", dst: "r10"},
      {op: "pop", dst: "r9"},
      {op: "pop", dst: "r8"},
      {op: "pop", dst: "rdx"},
      {op: "pop", dst: "rsi"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_alloc_full"},
      {op: "jmp", label: "rt_alloc_init"}
    ]
  ]
)

@doc """
LARGE_DROP: rt_drop's path for a block of FREE_CLASSES words or more: its mapping is returned (munmap), with rsi saved, then it is counted no longer live.

    LARGE_DROP[0] #=> {op: "label", name: "rt_drop_large"}
"""
LARGE_DROP = append(
  *[
    [
      {op: "label", name: "rt_drop_large"},
      {op: "push", src: "rsi"},
      {op: "mov", dst: "rsi", src: "rdx"}
    ],
    times8("rsi"),
    [
      {op: "mov", dst: "rax", imm: 11},
      {op: "syscall"},
      {op: "pop", dst: "rsi"},
      {op: "jmp", label: "rt_drop_count"}
    ]
  ]
)

@doc """
RT_ALLOC: the runtime's allocator, in machine code. It takes a block of rdi words from the free list kept for that size at r14, or bumps r15 when the list is empty; it sets the block's count to 1 and records its size, counts it live at r14, and answers it in rax.

    RT_ALLOC[0] #=> {op: "label", name: "rt_alloc"}
"""
RT_ALLOC = append(
  *[
    [
      {op: "label", name: "rt_alloc"},
      {op: "cmp", dst: "rdi", imm: FREE_CLASSES},
      {op: "j", cond: "ge", label: "rt_alloc_large"},
      {op: "mov", dst: "rax", src: "rdi"}
    ],
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
      {op: "mov", dst: "rcx", src: "r14"},
      {op: "add", dst: "rcx", imm: HEAP_BYTES},
      {op: "cmp", dst: "r15", src: "rcx"},
      {op: "j", cond: "g", label: "rt_alloc_full"},
      {op: "label", name: "rt_alloc_init"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 8},
      {op: "store", src: "rdi", base: "rax", disp: 16},
      {op: "load", dst: "rcx", base: "r14", disp: 0},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "r14", disp: 0},
      {op: "ret"},
      {op: "label", name: "rt_alloc_full"},
      {op: "mov", dst: "rdi", imm: HEAP_EXHAUSTED},
      {op: "mov", dst: "rax", imm: 60},
      {op: "syscall"}
    ],
    LARGE_ALLOC
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
      {op: "cmp", dst: "rdx", imm: FREE_CLASSES},
      {op: "j", cond: "ge", label: "rt_drop_large"},
      {op: "mov", dst: "rax", src: "rdx"}
    ],
    times8("rax"),
    [
      {op: "add", dst: "rax", src: "r14"},
      {op: "load", dst: "rcx", base: "rax", disp: 0},
      {op: "store", src: "rcx", base: "rdi", disp: 0},
      {op: "store", src: "rdi", base: "rax", disp: 0},
      {op: "label", name: "rt_drop_count"},
      {op: "load", dst: "rcx", base: "r14", disp: 0},
      {op: "sub", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "r14", disp: 0},
      {op: "label", name: "rt_drop_out"},
      {op: "ret"}
    ],
    LARGE_DROP
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
  elsif symbol?(a) and to_s(a) == "nil"
    [{op: "mov", dst: r, imm: 0}]
  elsif symbol?(a) and to_s(a) == "false"
    [{op: "mov", dst: r, imm: FALSE}]
  elsif symbol?(a) and to_s(a) == "true"
    [{op: "mov", dst: r, imm: 2}]
  elsif symbol?(a)
    [{op: "load", dst: r, disp: slot(slots, to_s(a))}]
  elsif a == true
    [{op: "mov", dst: r, imm: 2}]
  elsif a == false
    [{op: "mov", dst: r, imm: FALSE}]
  elsif a.nil?
    [{op: "mov", dst: r, imm: 0}]
  elsif 2 * a + 1 > 2_147_483_647 or 2 * a + 1 < -2_147_483_648
    [{op: "movabs", dst: r, imm: 2 * a + 1}]
  else
    [{op: "mov", dst: r, imm: 2 * a + 1}]
  end
end

@doc """
tagged_compare: a comparison of rax with rcx left in rax as true (2) or false (FALSE).

    last(tagged_compare("e")) #=> {op: "mov", dst: "rax", src: "rcx"}
"""
def tagged_compare(code)
  append(
    append(compare(code), [{op: "add", dst: "rax", src: "rax"}]),
    AS_BOOLEAN
  )
end

@doc """
FALSE: false natively, a word no number (odd) and no block (an address past 4096) can be, so false is not nil.

    FALSE #=> 4
"""
FALSE = 4

@doc """
EMPTY: the empty list natively, a word no number (odd), no block (an address past 4096), nil (0), true (2) or false (FALSE) can be, so [] is not nil. Inside a list the last tail stays 0, so a walker stops where it always did; EMPTY is the value of a list with no element, which (list), a rest that reaches the end and a routine that built nothing answer.

    EMPTY #=> 6
"""
EMPTY = 6

@doc """
MAP_KIND: the block kind of a native map: [kind, count, size 4, its entries], the entries a list of [key, value] lists kept sorted by key (key_lt) with one per key, so two equal maps are equal entry by entry.

    MAP_KIND #=> 7
"""
MAP_KIND = 7

@doc """
SHOW_FD_AT: where the program keeps the descriptor rt_show writes to, as an offset from r14: 1 (standard output), or the memfd rt_to_text gathers a value's text in.

    SHOW_FD_AT #=> 536
"""
SHOW_FD_AT = FREE_CLASSES * 8 + 24

@doc """
EXEC_MS_AT: where exec_within leaves its milliseconds plus one for rt_exec_capture, which turns it into a deadline on the monotonic clock; 0 is no deadline, as exec_capture runs.

    EXEC_MS_AT #=> 544
"""
EXEC_MS_AT = FREE_CLASSES * 8 + 32

@doc """
EXEC_TIMED_AT: where rt_exec_capture records whether the deadline passed (true, 2) or not (0), which exec_timed_out reads.

    EXEC_TIMED_AT #=> 552
"""
EXEC_TIMED_AT = FREE_CLASSES * 8 + 40

@doc """
now_ms_rax: the instructions that put the monotonic clock in milliseconds in rax, through a timespec at rbp-496 (rt_exec_capture's frame); rcx, rdx, rsi, rdi and r10 are used.

    length(now_ms_rax) #=> 14
"""
def now_ms_rax()
  [
    {op: "mov", dst: "rdi", imm: 1},
    {op: "mov", dst: "rsi", src: "rbp"},
    {op: "add", dst: "rsi", imm: -496},
    {op: "mov", dst: "rax", imm: 228},
    {op: "syscall"},
    {op: "load", dst: "rax", base: "rbp", disp: -496},
    {op: "mov", dst: "rcx", imm: 1000},
    {op: "imul", dst: "rax", src: "rcx"},
    {op: "mov", dst: "r10", src: "rax"},
    {op: "load", dst: "rax", base: "rbp", disp: -488},
    {op: "cqo"},
    {op: "mov", dst: "rcx", imm: 1_000_000},
    {op: "idiv", src: "rcx"},
    {op: "add", dst: "rax", src: "r10"}
  ]
end

@doc """
exec_deadline: rt_exec_capture's first step: the time out cleared, and, when exec_within left milliseconds, a deadline that many from now in their place; rdi, which the clock call takes, is the command list again after it, as argv_on_stack reads it there.

    exec_deadline[0] #=> {op: "mov", dst: "rcx", imm: 0}
"""
def exec_deadline()
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "r14", disp: EXEC_TIMED_AT},
        {op: "load", dst: "rcx", base: "r14", disp: EXEC_MS_AT},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "rt_xc_untimed"}
      ],
      now_ms_rax,
      [
        {op: "load", dst: "rcx", base: "r14", disp: EXEC_MS_AT},
        {op: "add", dst: "rax", src: "rcx"},
        {op: "store", src: "rax", base: "r14", disp: EXEC_MS_AT},
        {op: "label", name: "rt_xc_untimed"},
        {op: "load", dst: "rdi", base: "rbp", disp: -8}
      ]
    ]
  )
end

@doc """
exec_own_group: the child's first step under a deadline: a process group of its own (setpgid), so the deadline can end it and everything it started.

    exec_own_group[1] #=> {op: "cmp", dst: "rcx", imm: 0}
"""
def exec_own_group()
  [
    {op: "load", dst: "rcx", base: "r14", disp: EXEC_MS_AT},
    {op: "cmp", dst: "rcx", imm: 0},
    {op: "j", cond: "e", label: "rt_xc_one_group"},
    {op: "mov", dst: "rdi", imm: 0},
    {op: "mov", dst: "rsi", imm: 0},
    {op: "mov", dst: "rax", imm: 109},
    {op: "syscall"},
    {op: "label", name: "rt_xc_one_group"}
  ]
end

@doc """
exec_poll_until: the poll of rt_exec_capture's three pollfds, waiting as long as it takes, or under a deadline only until it; a poll that finds the deadline passed kills the child's process group, records the time out and drops the deadline, so the loop reads the pipes to their end.

    last(exec_poll_until)[:name] #=> "rt_xc_polled"
"""
def exec_poll_until()
  append(
    *[
      [
        {op: "mov", dst: "rdx", imm: -1},
        {op: "load", dst: "rcx", base: "r14", disp: EXEC_MS_AT},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "rt_xc_wait"}
      ],
      now_ms_rax,
      [
        {op: "load", dst: "rdx", base: "r14", disp: EXEC_MS_AT},
        {op: "sub", dst: "rdx", src: "rax"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "ge", label: "rt_xc_wait"},
        {op: "mov", dst: "rdx", imm: 0},
        {op: "label", name: "rt_xc_wait"},
        {op: "mov", dst: "rdi", src: "rbp"},
        {op: "add", dst: "rdi", imm: -432},
        {op: "mov", dst: "rsi", imm: 3},
        {op: "mov", dst: "rax", imm: 7},
        {op: "syscall"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "ne", label: "rt_xc_polled"},
        {op: "load", dst: "rcx", base: "r14", disp: EXEC_MS_AT},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "rt_xc_polled"},
        {op: "load", dst: "rcx", base: "rbp", disp: -160},
        {op: "mov", dst: "rdi", imm: 0},
        {op: "sub", dst: "rdi", src: "rcx"},
        {op: "mov", dst: "rsi", imm: 9},
        {op: "mov", dst: "rax", imm: 62},
        {op: "syscall"},
        {op: "mov", dst: "rcx", imm: 2},
        {op: "store", src: "rcx", base: "r14", disp: EXEC_TIMED_AT},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "r14", disp: EXEC_MS_AT},
        {op: "label", name: "rt_xc_polled"}
      ]
    ]
  )
end

@doc """
exec_status_when_timed: the status a child the deadline ended answers, -1 (tagged, still -1), in place of what wait4 read.

    exec_status_when_timed[1] #=> {op: "cmp", dst: "rcx", imm: 0}
"""
def exec_status_when_timed()
  [
    {op: "load", dst: "rcx", base: "r14", disp: EXEC_TIMED_AT},
    {op: "cmp", dst: "rcx", imm: 0},
    {op: "j", cond: "e", label: "rt_xc_on_time"},
    {op: "mov", dst: "rcx", imm: -1},
    {op: "store", src: "rcx", base: "rbp", disp: -200},
    {op: "label", name: "rt_xc_on_time"}
  ]
end

@doc """
swap_word: the instructions that turn the word from in reg into to, leaving any other word as it is, with no branch: tmp (kept on the stack) holds whether reg is from, and r11 the difference. tmp must be rax, which set and movzx write, and reg must not be.

    length(swap_word("rbx", EMPTY, 0, "rax")) #=> 9
"""
def swap_word(reg, from, to, tmp)
  [
    {op: "push", src: tmp},
    {op: "mov", dst: tmp, src: reg},
    {op: "cmp", dst: tmp, imm: from},
    {op: "set", cond: "e"},
    {op: "movzx"},
    {op: "mov", dst: "r11", imm: to - from},
    {op: "imul", dst: tmp, src: "r11"},
    {op: "add", dst: reg, src: tmp},
    {op: "pop", dst: tmp}
  ]
end

@doc """
empty_when_none: the instructions that turn a list a routine built at rbp+slot into EMPTY when it built nothing (it is still 0).

    length(empty_when_none(-40)) #=> 11
"""
def empty_when_none(slot)
  append(
    *[
      [{op: "load", dst: "rcx", base: "rbp", disp: slot}],
      swap_word("rcx", 0, EMPTY, "rax"),
      [{op: "store", src: "rcx", base: "rbp", disp: slot}]
    ]
  )
end

@doc """
AS_BOOLEAN: the instructions that turn a runtime answer of 2 or 0 in rax into blue's true (2) or false (FALSE), as 4 - rax.

    length(AS_BOOLEAN) #=> 3
"""
AS_BOOLEAN = [
  {op: "mov", dst: "rcx", imm: FALSE},
  {op: "sub", dst: "rcx", src: "rax"},
  {op: "mov", dst: "rax", src: "rcx"}
]

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
        {op: "pop", dst: "rax"},
        {op: "mov", dst: "rcx", imm: FALSE},
        {op: "sub", dst: "rcx", src: "rax"},
        {op: "mov", dst: "rax", src: "rcx"}
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
  elsif op == "map_alist"
    part_code(slots, args[0], 24)
  elsif op == "map_wrap"
    append(
      tagged_atom(slots, args[0], "rcx"),
      [
        {op: "push", src: "rcx"},
        {op: "mov", dst: "rdi", imm: 4},
        {op: "call_label", label: "rt_alloc"},
        {op: "mov", dst: "rcx", imm: MAP_KIND},
        {op: "store", src: "rcx", base: "rax", disp: 0},
        {op: "pop", dst: "rcx"},
        {op: "store", src: "rcx", base: "rax", disp: 24}
      ]
    )
  elsif op == "first"
    part_code(slots, args[0], 24)
  elsif op == "rest"
    append(
      *[
        part_code(slots, args[0], 32),
        [{op: "mov", dst: "rdx", src: "rax"}],
        swap_word("rdx", 0, EMPTY, "rax"),
        [{op: "mov", dst: "rax", src: "rdx"}]
      ]
    )
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
  elsif member?(op, CLOCK_WORDS)
    clock_code(slots, op, args)
  elsif op == "exec_ok?"
    append(
      *[
        list_code(slots, args),
        [
          {op: "mov", dst: "rdi", src: "rax"},
          {op: "call_label", label: "rt_exec_check"},
          {op: "mov", dst: "rcx", imm: 1}
        ],
        tagged_compare("e")
      ]
    )
  elsif op == "exec_check"
    append(
      list_code(slots, args),
      [
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "call_label", label: "rt_exec_check"}
      ]
    )
  elsif op == "exec_within_raw"
    append(
      *[
        tagged_atom(slots, args[0], "rcx"),
        [
          {op: "sar1", dst: "rcx"},
          {op: "add", dst: "rcx", imm: 1},
          {op: "store", src: "rcx", base: "r14", disp: EXEC_MS_AT}
        ],
        rc_op(slots, "exec_capture", rest(args))
      ]
    )
  elsif op == "exec_timed_out"
    append(
      [{op: "load", dst: "rax", base: "r14", disp: EXEC_TIMED_AT}],
      AS_BOOLEAN
    )
  elsif op == "exec_capture"
    append(
      list_code(slots, args),
      [
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "lea_label", dst: "rsi", label: kw_label(:status)},
        {op: "lea_label", dst: "rdx", label: kw_label(:stdout)},
        {op: "lea_label", dst: "rcx", label: kw_label(:stderr)},
        {op: "mov", dst: "r8", imm: 0},
        {op: "mov", dst: "r9", imm: 0},
        {op: "call_label", label: "rt_exec_capture"}
      ]
    )
  elsif op == "exec_with_stdin"
    append(
      *[
        list_code(slots, rest(args)),
        [{op: "mov", dst: "rdi", src: "rax"}],
        tagged_atom(slots, args[0], "r9"),
        [
          {op: "mov", dst: "r8", imm: 0},
          {op: "lea_label", dst: "rsi", label: kw_label(:status)},
          {op: "lea_label", dst: "rdx", label: kw_label(:stdout)},
          {op: "lea_label", dst: "rcx", label: kw_label(:stderr)},
          {op: "call_label", label: "rt_exec_capture"}
        ]
      ]
    )
  elsif op == "exec_with_env"
    append(
      *[
        list_code(slots, rest(args)),
        [{op: "mov", dst: "rdi", src: "rax"}],
        tagged_atom(slots, args[0], "r8"),
        swap_word("r8", EMPTY, 0, "rax"),
        [
          {op: "mov", dst: "r9", imm: 0},
          {op: "lea_label", dst: "rsi", label: kw_label(:status)},
          {op: "lea_label", dst: "rdx", label: kw_label(:stdout)},
          {op: "lea_label", dst: "rcx", label: kw_label(:stderr)},
          {op: "call_label", label: "rt_exec_capture"}
        ]
      ]
    )
  elsif op == "tcp_connect_ms"
    append(
      *[
        tagged_atom(slots, args[0], "rdi"),
        tagged_atom(slots, args[1], "rsi"),
        tagged_atom(slots, args[2], "rdx"),
        [
          {op: "lea_label", dst: "rcx", label: kw_label(:failed)},
          {op: "push", src: "rcx"},
          {op: "lea_label", dst: "rcx", label: kw_label(:error)},
          {op: "lea_label", dst: "r8", label: kw_label(:refused)},
          {op: "lea_label", dst: "r9", label: kw_label(:timeout)},
          {op: "lea_label", dst: "r10", label: kw_label(:unreachable)},
          {op: "lea_label", dst: "r11", label: kw_label(:unresolved)},
          {op: "call_label", label: "rt_tcp_connect"},
          {op: "pop", dst: "rcx"}
        ]
      ]
    )
  elsif op == "net_wait"
    net_wait_op(slots, args)
  elsif member?(op, map((w) -> w[0], ROUTINE_OPS))
    routine_op(slots, op, args)
  elsif op == "mod"
    append(
      append(
        tagged_atom(slots, args[0], "rdi"),
        tagged_atom(slots, args[1], "rsi")
      ),
      [{op: "call_label", label: "rt_mod"}]
    )
  elsif op == "put_int"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [{op: "call_label", label: "rt_put_int"}]
    )
  elsif op == "put_byte"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [{op: "call_label", label: "rt_put_byte"}]
    )
  elsif op == "is_terminal"
    append(
      tagged_atom(slots, args[0], "rdi"),
      append([{op: "call_label", label: "rt_is_terminal"}], AS_BOOLEAN)
    )
  elsif op == "read_line"
    [{op: "call_label", label: "rt_read_line"}]
  elsif op == "self_exe"
    [{op: "call_label", label: "rt_self_exe"}]
  elsif op == "write_bytes"
    append(
      append(
        tagged_atom(slots, args[0], "rdi"),
        tagged_atom(slots, args[1], "rsi")
      ),
      [{op: "call_label", label: "rt_write_bytes"}]
    )
  elsif op == "read_file"
    append(
      tagged_atom(slots, args[0], "rdi"),
      [{op: "call_label", label: "rt_read_file"}]
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
  elsif member?(op, map((p) -> p[0], KIND_PREDICATES))
    kind_predicate(slots, op, args)
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
  elsif head_is?(rhs, "tailcall")
    tail_jump(slots, rhs[1], rest(rest(rhs)))
  else
    rc_op(slots, to_s(first(rhs)), rest(rhs))
  end
end

@doc """
rc_gen: a term over tagged values; at its ret the value goes into a slot, returns from a function, or ends the program: as its untagged value, in :run mode dropped with exit status 0 as `blue run` ends a script, or, in leak mode, as the count of blocks still live after it is dropped.

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
    elsif into == :show
      [
        {op: "push", src: "rax"},
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "call_label", label: "rt_show"},
        {op: "pop", dst: "rdi"},
        {op: "call_label", label: "rt_drop"},
        {op: "mov", dst: "rdi", imm: 0},
        {op: "mov", dst: "rax", imm: 60},
        {op: "syscall"}
      ]
    elsif into == :run
      [
        {op: "mov", dst: "rdi", src: "rax"},
        {op: "call_label", label: "rt_drop"},
        {op: "mov", dst: "rdi", imm: 0},
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
            falsy_jump(no),
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
rc_program: a whole reference-counted program: the main frame, a heap whose first FREE_CLASSES words hold the live count and the free-list heads, the main term, every function, then the runtime.

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
      [
        {op: "mov", dst: "r14", src: "r15"},
        {op: "add", dst: "r15", imm: FREE_CLASSES * 8 + 48}
      ],
      save_envp,
      save_argv,
      save_stack_floor,
      [
        {op: "mov", dst: "rcx", imm: 1},
        {op: "store", src: "rcx", base: "r14", disp: SHOW_FD_AT}
      ],
      main[0],
      fns[0],
      runtime
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
  assert tagged_atom([], nil, "rax") == [{op: "mov", dst: "rax", imm: 0}]
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
  assert last(tagged_compare("l")) == {op: "mov", dst: "rax", src: "rcx"}
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
      swap_word("rbx", EMPTY, 0, "rax"),
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
list_code: a list of atoms built from its last element to its first, each a cons onto the list so far, which stays in rbx; the last tail is 0, and a list of no atom is EMPTY.

    list_code([], []) #=> [{op: "mov", dst: "rax", imm: EMPTY}]
"""
def list_code(slots, args)
  if length(args) == 0
    [{op: "mov", dst: "rax", imm: EMPTY}]
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
  {op: "cmp", dst: "rdx", imm: EMPTY},
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
  assert list_code([], [])[0][:imm] == EMPTY
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
  body = rc_gen(slots, mark_tail(g[:body], g[:name]), :return, n)
  [
    append(
      *[
        [
          {op: "label", name: "g_#{g[:name]}"},
          {op: "push_rbp"},
          {op: "mov", dst: "rbp", src: "rsp"},
          {op: "sub", dst: "rsp", imm: 8 * length(slots)},
          {op: "label", name: "g_#{g[:name]}_tail"}
        ],
        stack_guard("g_#{g[:name]}"),
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
ENVP_AT: where the program keeps its environment pointer, as an offset from r14: the word after the free-list table.

    ENVP_AT #=> 512
"""
ENVP_AT = FREE_CLASSES * 8

@doc """
save_envp: the instructions that keep the environment the kernel passed at entry (envp, after argc, argv and its ending nil on the entry stack, rbp + 24 + 8 * argc once the frame is pushed) at r14 + ENVP_AT, for a child process to inherit.

    last(save_envp)[:disp] #=> ENVP_AT
"""
def save_envp()
  append(
    *[
      [{op: "load", dst: "rcx", base: "rbp", disp: 8}],
      times8("rcx"),
      [
        {op: "add", dst: "rcx", src: "rbp"},
        {op: "add", dst: "rcx", imm: 24},
        {op: "store", src: "rcx", base: "r14", disp: ENVP_AT}
      ]
    ]
  )
end

@doc """
runtime: every runtime routine a reference-counted program carries, in order. rc_program places it after the program and rc_whole takes it back off to put the global functions before it, so both read this one list: a routine added here is never cut in half by one of them counting a shorter list.

    runtime[0] #=> {op: "label", name: "rt_alloc"}
"""
def runtime()
  append(
    *[
      RT_ALLOC,
      RT_DUP,
      RT_DROP,
      RT_LENGTH,
      RT_GET,
      RT_IS_ERROR,
      RT_PAYLOAD,
      RT_CONCAT,
      RT_EQUAL,
      RT_TO_S,
      RT_READ_FILE,
      RT_WRITE_BYTES,
      RT_SELF_EXE,
      RT_EXEC_CHECK,
      RT_EXEC_CAPTURE,
      RT_TCP_CONNECT,
      RT_READ_LINE,
      IS_TERMINAL,
      RT_HOSTS_LOOKUP,
      RT_DNS_LOOKUP,
      RT_PUT_INT,
      RT_PUT_BYTE,
      RT_MOD,
      RT_RESOLVE,
      RT_SOCKADDR,
      RT_TCP_LISTEN,
      RT_TCP_PORT,
      RT_TCP_ACCEPT,
      RT_TCP_OPEN,
      RT_TCP_READ,
      RT_TCP_WRITE,
      RT_TCP_CLOSE,
      RT_NET_WAIT,
      RT_SHOW,
      RT_KIND_OF,
      RT_ENV_LOOKUP,
      RT_GETENV,
      RT_ENV_REQUIRED,
      RT_PATH_JOIN,
      RT_PATH_BASENAME,
      RT_PATH_DIRNAME,
      RT_PATH_EXTENSION,
      FS_ROUTINES,
      PROCESS_ROUTINES,
      RT_LS_RAW,
      RT_STRING_LT,
      RT_TO_TEXT,
      RT_FLOOR_DIV
    ]
  )
end

@doc """
with_capture_keywords: a program's literals with the keywords exec_capture answers added once each, so its data section holds them whether or not the program names them.

    with_capture_keywords([:status]) #=> %i[status stdout stderr]
"""
def with_capture_keywords(literals)
  append(
    literals,
    filter((k) -> not member?(k, literals), %i[status stdout stderr])
  )
end

@doc """
with_runtime_keywords: a program's literals with the keywords the runtime's answers name (RUNTIME_KEYWORDS) added once each, so its data section holds them whether or not the program names them.

    with_runtime_keywords([:status])[0] #=> :status
"""
def with_runtime_keywords(literals)
  append(literals, filter((k) -> not member?(k, literals), RUNTIME_KEYWORDS))
end

@doc """
rc_whole: the instructions of a program with global functions: rc_program's frame, heap, main and closures, then every global function, then the runtime.

    rc_whole(whole(read_forms("7")[0]), :exit)[0] #=> {op: "push_rbp"}
"""
def rc_whole(w, mode)
  base = rc_program({main: w[:main], fns: w[:fns]}, mode)
  start = length(base) - length(runtime)
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
        with_runtime_keywords(
          append(
            literals_in(w[:main]),
            flat_map(append(w[:fns], w[:globals]), (f) -> literals_in(f[:body]))
          )
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
  compile_whole_in(form, mode, CONVENTION)
end

@doc """
CONVENTION: the calling convention compile_whole asks kuzushi for (whole_in): :owned, where a callee owns and drops every argument, or :borrow, where a parameter the callee only reads is lent and the caller drops it after the call. Both are kept; this names the one the native column proved.

    member?(CONVENTION, %i[owned borrow]) #=> true
"""
CONVENTION = :owned

@doc """
compile_whole_in: compile_whole under the calling convention named, :owned or :borrow.

    compile_whole_in(read_forms("7")[0], :exit, :borrow)[0] #=> 127
"""
def compile_whole_in(form, mode, convention)
  executable(
    assemble(rc_whole(whole_in(bare_calls(form), convention), mode)),
    true
  )
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

test "lent, recursive programs give the value they give owned", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      fn(p)
        path = path_join(temp_dir("hashiru"), "b.out")
        form = read_forms(p[0])[0]
        write_bytes(path, compile_whole_in(form, :exit, :borrow))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      RECURSIVE_PROGRAMS
    )
  end
end

test "the convention is a setting: compile_whole compiles under CONVENTION, and a parameter only read compiles another way under :borrow than under :owned"
  src = "(begin (define (big l) (> (length l) 2)) (big (list 1 2 3)))"
  form = read_forms(src)[0]
  assert member?(CONVENTION, %i[owned borrow])
  assert compile_whole(form, :exit) == compile_whole_in(form, :exit, CONVENTION)
  assert compile_whole_in(form, :exit, :borrow) !=
    compile_whole_in(form, :exit, :owned)
end

test "a global function is a label called directly, its parameters from ARG_REGS"
  g = nth(
    0,
    rc_global({name: "f", params: ["x"], body: read_forms("(ret x)")[0]}, 0)
  )
  assert g[0] == {op: "label", name: "g_f"}
  assert g[4] == {op: "label", name: "g_f_tail"}
  assert member?({op: "store", src: "rdi", disp: -8}, g)
  assert last(rc_gcall([], "f", [1, 2])) == {op: "call_label", label: "g_f"}
  insns = rc_whole(whole(read_forms("(begin (define (f) 1) (f))")[0]), :exit)
  assert member?({op: "label", name: "g_f"}, insns)
  data_at = index_of(map((i) -> i[:op], insns), "align")
  assert insns[data_at - 1] == {op: "ret"}
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
  pad = map((_k) -> 0, range(0, words * 8 - length(b)))
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
    elsif head_is?(rhs, "closure") or
        head_is?(rhs, "gcall") or
        head_is?(rhs, "tailcall")
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
keyword_block: the bytes of a keyword's static block: laid out as a string block (its name's length and bytes) under kind 2, so rt_show can name it; a keyword is still compared by its address.

    length(keyword_block(:ab)) #=> 40
"""
def keyword_block(k)
  b = string_block(to_s(k))
  append(le64(2), slice(b, 8, length(b) - 8))
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
          {op: "bytes", bytes: keyword_block(v)}
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
  assert slice(keyword_block(:ab), 0, 8) == le64(2)
  assert slice(keyword_block(:ab), 24, 8) == le64(2)
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
  "(define (nth i l) (if (< i 0) nil (if (equal? (length l) 0) nil (if (equal? i 0) (first l) (nth (- i 1) (rest l))))))",
  "(define (reverse_onto l acc) (if (equal? (length l) 0) acc (reverse_onto (rest l) (cons (first l) acc))))",
  "(define (reverse l) (reverse_onto l (list)))",
  "(define (map f l) (if (equal? (length l) 0) (list) (cons (f (first l)) (map f (rest l)))))",
  "(define (filter f l) (if (equal? (length l) 0) (list) (if (f (first l)) (cons (first l) (filter f (rest l))) (filter f (rest l)))))",
  "(define (reduce f acc l) (if (equal? (length l) 0) acc (reduce f (f acc (first l)) (rest l))))",
  "(define (every? f l) (if (equal? (length l) 0) true (if (f (first l)) (every? f (rest l)) false)))",
  "(define (any? f l) (if (equal? (length l) 0) false (if (f (first l)) true (any? f (rest l)))))",
  "(define (insert_string s l) (if (equal? (length l) 0) (list s) (if (string_lt s (first l)) (cons s l) (cons (first l) (insert_string s (rest l))))))",
  "(define (sort_strings l) (reduce (lambda (acc s) (insert_string s acc)) (list) l))",
  "(define (list_drop n l) (if (< n 1) l (if (equal? (length l) 0) l (list_drop (- n 1) (rest l)))))",
  "(define (key_lt a b) (if (integer? a) (if (integer? b) (< a b) true) (if (integer? b) false (if (string? a) (if (string? b) (string_lt a b) true) (if (string? b) false (string_lt a b))))))",
  "(define (alist_put k v l) (if (equal? (length l) 0) (cons (list k v) (list)) (if (equal? (first (first l)) k) (cons (list k v) (rest l)) (if (key_lt k (first (first l))) (cons (list k v) l) (cons (first l) (alist_put k v (rest l)))))))",
  "(define (alist_get l k) (if (equal? (length l) 0) nil (if (equal? (first (first l)) k) (first (rest (first l))) (alist_get (rest l) k))))",
  "(define (map_get m k) (alist_get (map_alist m) k))",
  "(define (map_put m k v) (map_wrap (alist_put k v (map_alist m))))",
  "(define (take_n n l) (if (< n 1) (list) (if (equal? (length l) 0) (list) (cons (first l) (take_n (- n 1) (rest l))))))",
  "(define (bytes_slice l off n) (take_n n (list_drop off l)))",
  "(define (u32s l n) (if (< n 1) (list) (if (< (length l) 4) (list) (cons (+ (nth 0 l) (* 256 (+ (nth 1 l) (* 256 (+ (nth 2 l) (* 256 (nth 3 l))))))) (u32s (list_drop 4 l) (- n 1))))))",
  "(define (read_u32s f off n) (u32s (list_drop off (read_bytes f)) n))",
  "(define (walk_dir d) (reduce (lambda (acc p) (if (is_dir? p) (append acc (walk_dir p)) (append acc (list p)))) (list) (ls d)))",
  "(define (pad2 n) (if (< n 10) (concat \"0\" (to_s n)) (to_s n)))",
  "(define (rfc_clock s) (concat (concat (concat (concat (concat (pad2 (int_div s 3600)) \":\") (pad2 (mod (int_div s 60) 60))) \":\") (pad2 (mod s 60))) \"Z\"))",
  "(define (rfc_text m d y secs) (concat (concat (concat (concat (concat (concat (to_s (if (< m 3) (+ y 1) y)) \"-\") (pad2 m)) \"-\") (pad2 d)) \"T\") (rfc_clock secs)))",
  "(define (rfc_mp doy mp y secs) (rfc_text (if (< mp 10) (+ mp 3) (- mp 9)) (+ (- doy (int_div (+ (* 153 mp) 2) 5)) 1) y secs))",
  "(define (rfc_doy doy y secs) (rfc_mp doy (int_div (+ (* 5 doy) 2) 153) y secs))",
  "(define (rfc_yoe doe yoe era secs) (rfc_doy (- doe (- (+ (* 365 yoe) (int_div yoe 4)) (int_div yoe 100))) (+ yoe (* era 400)) secs))",
  "(define (rfc_doe doe era secs) (rfc_yoe doe (int_div (- (+ (- doe (int_div doe 1460)) (int_div doe 36524)) (int_div doe 146096)) 365) era secs))",
  "(define (rfc_civil z secs) (rfc_doe (- z (* (int_div z 146097) 146097)) (int_div z 146097) secs))",
  "(define (rfc3339 s) (rfc_civil (+ (int_div s 86400) 719468) (mod s 86400)))",
  "(define (now_rfc3339) (rfc3339 (now)))"
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
BOARD_WORDS: the board package's words hashiru compiles itself, so a program that names them in `use("kiban", ...)` needs nothing from the package (the words C3's corpus prints with).

    BOARD_WORDS #=> ["put_int", "put_byte"]
"""
BOARD_WORDS = %w[put_int put_byte]

@doc """
board_use?: whether a top-level form is a `use` of kiban that names only BOARD_WORDS. A `use` of another package, or of a kiban word hashiru has no code for, is refused by name.

    board_use?(read_forms("(use \"kiban\" (list :put_byte :put_int))")[0]) #=> true
    board_use?(read_forms("(f 1)")[0]) #=> false
    (board_use?(read_forms("(use \"kiban\" (list :reclaim))")[0]) rescue :refused) #=> :refused
"""
def board_use?(form)
  if not head_is?(form, "use")
    false
  else
    words = if length(form) > 2 and list?(form[2])
      map(to_s, rest(form[2]))
    else
      []
    end
    missing = filter((w) -> not member?(w, BOARD_WORDS), words)
    if form[1] != "kiban" or length(missing) > 0
      raise(
        :unsupported,
        "hashiru: no native code for use(#{to_s(form[1])}, #{to_s(missing)}); it compiles only kiban's #{to_s(BOARD_WORDS)}"
      )
    end
    true
  end
end

@doc """
typed_erased: a top-level form with its types erased, as hashiru's code is tagged and checks none: a `define-typed` is the `define` of the same name, parameters and body.

    typed_erased(read_forms("(define-typed (f (n Int) (m dyn)) Int (+ n m))")[0]) == read_forms("(define (f n m) (+ n m))")[0] #=> true
    typed_erased(read_forms("(f 1)")[0]) == read_forms("(f 1)")[0] #=> true
"""
def typed_erased(form)
  if head_is?(form, "define-typed") and length(form) > 3 and list?(form[1])
    sig = form[1]
    params = map(
      fn(p)
        if list?(p)
          first(p)
        else
          p
        end
      end,
      rest(sig)
    )
    append([read_forms("define")[0], cons(first(sig), params)], drop_n(form, 3))
  else
    form
  end
end

@doc """
front_erased: a program with its board `use` forms dropped and its typed definitions erased, top level only (see board_use? and typed_erased).

    front_erased(read_forms("(begin (use \"kiban\" (list :put_int)) (define-typed (f (n Int)) Int n) (f 1))")[0]) == read_forms("(begin (define (f n) n) (f 1))")[0] #=> true
"""
def front_erased(form)
  if head_is?(form, "begin")
    cons(
      first(form),
      map(typed_erased, filter((f) -> not board_use?(f), rest(form)))
    )
  else
    typed_erased(form)
  end
end

test "a board use is dropped, a typed definition erased, and any other use refused"
  p = nth(
    0,
    read_forms("(begin (use \"kiban\" (list :put_byte :put_int)) (define-typed (f (n Int)) Int (* n 2)) (f 21))")
  )
  assert front_erased(p) ==
    read_forms("(begin (define (f n) (* n 2)) (f 21))")[0]
  assert board_use?(read_forms("(use \"kiban\" (list :put_int))")[0])
  assert (board_use?(read_forms("(use \"moji\" (list :trim))")[0]) rescue
    :refused) == :refused
  assert typed_erased(read_forms("(define-typed (g (a dyn)) dyn a)")[0]) ==
    read_forms("(define (g a) a)")[0]
  assert member?("put_int", BOARD_WORDS)
end

test "a typed program with a board use gives its value on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-front"), "front.out")
    p = nth(
      0,
      read_forms("(begin (use \"kiban\" (list :put_int)) (define-typed (f (n Int)) Int (* n 2)) (f 21))")
    )
    write_bytes(path, compile_program(p, :exit))
    exec_capture("chmod", "+x", path)
    assert status_of(exec_capture(path)) == 42
  end
end

@doc """
compile_program: a program compiled with the prelude through Perceus to a reference-counted executable.

    compile_program(read_forms("7")[0], :exit)[0] #=> 127
"""
def compile_program(form, mode)
  compile_whole(
    shake(bare_calls(map_calls(with_prelude(front_erased(form))))),
    mode
  )
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
RT_EQUAL: true (2) or false (0) for whether the values in rdi and rsi are equal: the same word is equal; two strings are equal when their bytes are; two lists are equal when their heads are equal and their tails are, element by element; two maps are equal when their sorted entries are; anything else is compared by identity. Both values are only read.

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
  {op: "cmp", dst: "rax", imm: MAP_KIND},
  {op: "j", cond: "ne", label: "rt_equal_not_map"},
  {op: "load", dst: "rdi", base: "rdi", disp: 24},
  {op: "load", dst: "rsi", base: "rsi", disp: 24},
  {op: "jmp", label: "rt_equal"},
  {op: "label", name: "rt_equal_not_map"},
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
      {op: "cmp", dst: "rdi", imm: 4096},
      {op: "j", cond: "l", label: "rt_to_s_as_is"},
      {op: "load", dst: "rax", base: "rdi", disp: 0},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_to_text"},
      {op: "cmp", dst: "rax", imm: MAP_KIND},
      {op: "j", cond: "e", label: "rt_to_text"},
      {op: "label", name: "rt_to_s_as_is"},
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
  ["(begin (write_stdout (to_s 0)) 0)", 0, "0"],
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

test "host words exit and write natively on x86-64", {
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

@doc """
LARGE_PROGRAMS: programs whose blocks outgrow the free-list table, with the exit status each must give: a string of FREE_CLASSES words or more is its own mapping, so a 1 MiB string fits beside a 1 MiB heap, and a heap used up by small live blocks exits with HEAP_EXHAUSTED.

    LARGE_PROGRAMS[0][1] #=> 64
"""
LARGE_PROGRAMS = [
  [
    "(begin (define (rep n s) (if (equal? n 0) s (rep (- n 1) (concat s s)))) (string_length (rep 6 \"abcdefghi\")))",
    64
  ],
  [
    "(begin (define (rep n s) (if (equal? n 0) s (rep (- n 1) (concat s s)))) (string_length (rep 19 \"ab\")))",
    0
  ],
  [
    "(begin (define (build n acc) (if (equal? n 0) (length acc) (build (- n 1) (cons n acc)))) (build 40000 (list)))",
    HEAP_EXHAUSTED
  ]
]

test "large blocks map and unmap; a full heap exits ENOMEM on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru"), "l.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      LARGE_PROGRAMS
    )
    write_bytes(
      path,
      compile_whole(read_forms(LARGE_PROGRAMS[0][0])[0], :leaks)
    )
    exec_capture("chmod", "+x", path)
    assert status_of(exec_capture(path)) == 0
  end
end

test "the allocator maps a block of FREE_CLASSES words or more and checks the heap's end"
  assert member?({op: "cmp", dst: "rdi", imm: FREE_CLASSES}, RT_ALLOC)
  assert member?({op: "j", cond: "g", label: "rt_alloc_full"}, RT_ALLOC)
  assert member?({op: "mov", dst: "rdi", imm: HEAP_EXHAUSTED}, RT_ALLOC)
  assert member?({op: "cmp", dst: "rdx", imm: FREE_CLASSES}, RT_DROP)
  assert member?({op: "j", cond: "ge", label: "rt_alloc_large"}, RT_ALLOC)
  assert member?({op: "mov", dst: "rax", imm: 9}, LARGE_ALLOC)
  assert member?({op: "pop", dst: "r10"}, LARGE_ALLOC)
  assert member?({op: "mov", dst: "rax", imm: 11}, LARGE_DROP)
  assert member?({op: "j", cond: "ge", label: "rt_drop_large"}, RT_DROP)
  assert length(assemble(RT_ALLOC)) > 0
  assert length(assemble(RT_DROP)) > 0
end

@doc """
path_on_stack: the instructions that copy the string block at rdi to the stack with a NUL ending, leaving rsp at the copy and the bytes reserved in r9 (rt_read_file and rt_write_bytes give them back with add rsp, r9 after their open).

    path_on_stack("t")[0] #=> {op: "load", dst: "r8", base: "rdi", disp: 24}
"""
def path_on_stack(tag)
  append(
    *[
      [
        {op: "load", dst: "r8", base: "rdi", disp: 24},
        {op: "mov", dst: "r9", src: "r8"},
        {op: "add", dst: "r9", imm: 16},
        {op: "and", dst: "r9", imm: -16},
        {op: "sub", dst: "rsp", src: "r9"},
        {op: "mov", dst: "r11", src: "rsp"},
        {op: "mov", dst: "rdx", src: "rdi"},
        {op: "add", dst: "rdx", imm: 32}
      ],
      copy_bytes("r8", tag),
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store_byte", src: "rcx", base: "r11"}
      ]
    ]
  )
end

@doc """
errno_block: the instructions that turn the negative return of a refused system call in rax into an error block whose payload is its errno, stored at rbp+disp.

    length(errno_block(-24)) #=> 10
"""
def errno_block(disp)
  [
    {op: "mov", dst: "rcx", imm: 0},
    {op: "sub", dst: "rcx", src: "rax"},
    {op: "add", dst: "rcx", src: "rcx"},
    {op: "add", dst: "rcx", imm: 1},
    {op: "store", src: "rcx", base: "rbp", disp:},
    {op: "mov", dst: "rdi", imm: 4},
    {op: "call_label", label: "rt_alloc"},
    {op: "mov", dst: "rcx", imm: 4},
    {op: "store", src: "rcx", base: "rax", disp: 0},
    {op: "load", dst: "rcx", base: "rbp", disp:}
  ]
end

@doc """
RT_READ_FILE: read_file natively (R4 of docs/PURE-BLUE.md): the string block whose path is in rdi, consumed; answered in rax as a new string holding the file's bytes, or an error block whose payload is the errno when the file does not open. The path is copied to the stack with a NUL ending; open, fstat for the size, one block (rt_alloc maps a large one), read until the size or an end, close. Locals live in an rbp frame, since a memory operand cannot be based on rsp here.

    RT_READ_FILE[0] #=> {op: "label", name: "rt_read_file"}
"""
RT_READ_FILE = append(
  *[
    [
      {op: "label", name: "rt_read_file"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 32},
      {op: "store", src: "rdi", base: "rbp", disp: -8}
    ],
    path_on_stack("rt_rf_path"),
    [
      {op: "mov", dst: "rdi", src: "rsp"},
      {op: "mov", dst: "rsi", imm: 0},
      {op: "mov", dst: "rax", imm: 2},
      {op: "syscall"},
      {op: "add", dst: "rsp", src: "r9"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_rf_refused"},
      {op: "store", src: "rax", base: "rbp", disp: -16},
      {op: "sub", dst: "rsp", imm: 144},
      {op: "mov", dst: "rdi", src: "rax"},
      {op: "mov", dst: "rsi", src: "rsp"},
      {op: "mov", dst: "rax", imm: 5},
      {op: "syscall"},
      {op: "load", dst: "r10", base: "rsi", disp: 48},
      {op: "add", dst: "rsp", imm: 144},
      {op: "store", src: "r10", base: "rbp", disp: -24},
      {op: "mov", dst: "rdi", src: "r10"},
      {op: "add", dst: "rdi", imm: 7},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "add", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "store", src: "rax", base: "rbp", disp: -32},
      {op: "mov", dst: "r8", imm: 0},
      {op: "label", name: "rt_rf_loop"},
      {op: "load", dst: "r10", base: "rbp", disp: -24},
      {op: "cmp", dst: "r8", src: "r10"},
      {op: "j", cond: "ge", label: "rt_rf_done"},
      {op: "load", dst: "rdi", base: "rbp", disp: -16},
      {op: "load", dst: "rsi", base: "rbp", disp: -32},
      {op: "add", dst: "rsi", imm: 32},
      {op: "add", dst: "rsi", src: "r8"},
      {op: "mov", dst: "rdx", src: "r10"},
      {op: "sub", dst: "rdx", src: "r8"},
      {op: "mov", dst: "rax", imm: 0},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "le", label: "rt_rf_done"},
      {op: "add", dst: "r8", src: "rax"},
      {op: "jmp", label: "rt_rf_loop"},
      {op: "label", name: "rt_rf_done"},
      {op: "load", dst: "rax", base: "rbp", disp: -32},
      {op: "store", src: "r8", base: "rax", disp: 24},
      {op: "load", dst: "rdi", base: "rbp", disp: -16},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "jmp", label: "rt_rf_out"},
      {op: "label", name: "rt_rf_refused"}
    ],
    errno_block(-24),
    [
      {op: "store", src: "rcx", base: "rax", disp: 24},
      {op: "store", src: "rax", base: "rbp", disp: -32},
      {op: "label", name: "rt_rf_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rax", base: "rbp", disp: -32},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
read_programs: programs over read_file, given a small file holding "hello\n" and a big one of 5000 bytes, with the exit status and output each must give: the small file printed and measured, the big one measured (a mapped block), and a path that does not open caught as its errno (ENOENT, 2).

    length(read_programs("/s", "/b")) #=> 4
"""
def read_programs(small, big)
  [
    [
      "(begin (write_stdout (read_file \"#{small}\")) 0)",
      0,
      unlines(["hello"])
    ],
    ["(string_length (read_file \"#{small}\"))", 6, ""],
    ["(string_length (read_file \"#{big}\"))", 5000 % 256, ""],
    ["(try (read_file \"/no/such/file\") (catch (e) e))", 2, ""]
  ]
end

test "read_file reads, maps and refuses natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    dir = temp_dir("hashiru-rf")
    small = path_join(dir, "small.txt")
    big = path_join(dir, "big.txt")
    write_file(small, unlines(["hello"]))
    write_file(big, join(map((_k) -> "x", range(0, 5000)), ""))
    path = path_join(dir, "rf.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_whole(read_forms(p[0])[0], :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      read_programs(small, big)
    )
  end
end

test "read_file is a call to rt_read_file, which opens, sizes, reads and closes in an rbp frame"
  assert last(rc_op([], "read_file", ["p"])) ==
    {op: "call_label", label: "rt_read_file"}
  assert member?({op: "mov", dst: "rax", imm: 2}, RT_READ_FILE)
  assert member?({op: "mov", dst: "rax", imm: 5}, RT_READ_FILE)
  assert member?({op: "mov", dst: "rax", imm: 3}, RT_READ_FILE)
  assert member?({op: "push_rbp"}, RT_READ_FILE)
  stand_ins = [
    {op: "label", name: "rt_alloc"},
    {op: "ret"},
    {op: "label", name: "rt_drop"},
    {op: "ret"}
  ]
  assert length(assemble(append(RT_READ_FILE, stand_ins))) > 0
end

@doc """
RT_WRITE_BYTES: write_bytes natively (R4 of docs/PURE-BLUE.md): the list of byte values in rsi written to the path in rdi, both consumed; answers nil, or an error block whose payload is the errno when the file does not open. The bytes are gathered into one string block (rt_alloc maps a large one), the file opened to create or truncate (O_WRONLY|O_CREAT|O_TRUNC, mode 0644), written until done, and closed.

    RT_WRITE_BYTES[0] #=> {op: "label", name: "rt_write_bytes"}
"""
RT_WRITE_BYTES = append(
  *[
    [
      {op: "label", name: "rt_write_bytes"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -16},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "mov", dst: "rdx", src: "rsi"},
      {op: "label", name: "rt_wb_count"},
      {op: "cmp", dst: "rdx", imm: 0},
      {op: "j", cond: "e", label: "rt_wb_counted"},
      {op: "add", dst: "rcx", imm: 1},
      {op: "load", dst: "rdx", base: "rdx", disp: 32},
      {op: "jmp", label: "rt_wb_count"},
      {op: "label", name: "rt_wb_counted"},
      {op: "store", src: "rcx", base: "rbp", disp: -40},
      {op: "mov", dst: "rdi", src: "rcx"},
      {op: "add", dst: "rdi", imm: 7},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "add", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "store", src: "rax", base: "rbp", disp: -32},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "load", dst: "rcx", base: "rbp", disp: -40},
      {op: "store", src: "rcx", base: "rax", disp: 24},
      {op: "mov", dst: "r11", src: "rax"},
      {op: "add", dst: "r11", imm: 32},
      {op: "load", dst: "rdx", base: "rbp", disp: -16},
      {op: "label", name: "rt_wb_fill"},
      {op: "cmp", dst: "rdx", imm: 0},
      {op: "j", cond: "e", label: "rt_wb_filled"},
      {op: "load", dst: "rcx", base: "rdx", disp: 24},
      {op: "sar1", dst: "rcx"},
      {op: "store_byte", src: "rcx", base: "r11"},
      {op: "add", dst: "r11", imm: 1},
      {op: "load", dst: "rdx", base: "rdx", disp: 32},
      {op: "jmp", label: "rt_wb_fill"},
      {op: "label", name: "rt_wb_filled"},
      {op: "load", dst: "rdi", base: "rbp", disp: -8}
    ],
    path_on_stack("rt_wb_path"),
    [
      {op: "mov", dst: "rdi", src: "rsp"},
      {op: "mov", dst: "rsi", imm: 577},
      {op: "mov", dst: "rdx", imm: 420},
      {op: "mov", dst: "rax", imm: 2},
      {op: "syscall"},
      {op: "add", dst: "rsp", src: "r9"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_wb_refused"},
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "mov", dst: "r8", imm: 0},
      {op: "label", name: "rt_wb_loop"},
      {op: "load", dst: "r10", base: "rbp", disp: -40},
      {op: "cmp", dst: "r8", src: "r10"},
      {op: "j", cond: "ge", label: "rt_wb_done"},
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "load", dst: "rsi", base: "rbp", disp: -32},
      {op: "add", dst: "rsi", imm: 32},
      {op: "add", dst: "rsi", src: "r8"},
      {op: "mov", dst: "rdx", src: "r10"},
      {op: "sub", dst: "rdx", src: "r8"},
      {op: "mov", dst: "rax", imm: 1},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "le", label: "rt_wb_done"},
      {op: "add", dst: "r8", src: "rax"},
      {op: "jmp", label: "rt_wb_loop"},
      {op: "label", name: "rt_wb_done"},
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "jmp", label: "rt_wb_out"},
      {op: "label", name: "rt_wb_refused"}
    ],
    errno_block(-24),
    [
      {op: "store", src: "rcx", base: "rax", disp: 24},
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "label", name: "rt_wb_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -32},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rdi", base: "rbp", disp: -16},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rax", base: "rbp", disp: -24},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
write_programs: programs over write_bytes, given a directory to write in, with the exit status and output each must give: bytes written and read back, 600 bytes written (a mapped buffer) and measured, and a path that does not open caught as its errno (ENOENT, 2).

    length(write_programs("/d")) #=> 3
"""
def write_programs(dir)
  [
    [
      "(begin (write_bytes \"#{dir}/hi.txt\" (list 104 105 10)) (write_stdout (read_file \"#{dir}/hi.txt\")) 0)",
      0,
      unlines(["hi"])
    ],
    [
      "(begin (define (mk n acc) (if (equal? n 0) acc (mk (- n 1) (cons 120 acc)))) (write_bytes \"#{dir}/big.txt\" (mk 600 (list))) (string_length (read_file \"#{dir}/big.txt\")))",
      600 % 256,
      ""
    ],
    ["(try (write_bytes \"/no/such/dir/x\" (list 1)) (catch (e) e))", 2, ""]
  ]
end

test "write_bytes writes, maps and refuses natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    dir = temp_dir("hashiru-wb")
    path = path_join(dir, "wb.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_program(read_forms(p[0])[0], :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      write_programs(dir)
    )
  end
end

test "write_bytes is a call to rt_write_bytes, which gathers, opens to create, writes and closes"
  assert last(rc_op([], "write_bytes", %w[p b])) ==
    {op: "call_label", label: "rt_write_bytes"}
  assert member?({op: "mov", dst: "rsi", imm: 577}, RT_WRITE_BYTES)
  assert member?({op: "mov", dst: "rax", imm: 1}, RT_WRITE_BYTES)
  stand_ins = [
    {op: "label", name: "rt_alloc"},
    {op: "ret"},
    {op: "label", name: "rt_drop"},
    {op: "ret"}
  ]
  assert length(assemble(append(RT_WRITE_BYTES, stand_ins))) > 0
  assert length(path_on_stack("t")) > 0
  assert tagged_atom([], 1_700_000_000, "rax") ==
    [{op: "movabs", dst: "rax", imm: 3_400_000_001}]
  assert tagged_atom([], 7, "rax") == [{op: "mov", dst: "rax", imm: 15}]
  assert errno_block(-24)[4] ==
    {op: "store", src: "rcx", base: "rbp", disp: -24}
end

test "a program with global functions carries the runtime whole, after them, never cut by a global"
  insns = rc_whole(whole(read_forms("(begin (define (f) 1) (f))")[0]), :exit)
  at = index_of(insns, {op: "label", name: "rt_alloc"})
  assert at > index_of(insns, {op: "label", name: "g_f"})
  assert slice(insns, at, length(runtime)) == runtime
end

@doc """
CLOCK_WORDS: blue's clock words that compile natively (R4): the time since 1970 in seconds, milliseconds and nanoseconds, the nanoseconds since a now_ns, and a pause.

    member?("now_ms", CLOCK_WORDS) #=> true
"""
CLOCK_WORDS = %w[now now_ms now_ns elapsed_since sleep sleep_ms]

@doc """
clock_read: the instructions that read CLOCK_REALTIME (clock_gettime, 228) into a stack timespec, leaving its seconds in rax and its nanoseconds in rcx.

    clock_read[4] #=> {op: "mov", dst: "rax", imm: 228}
"""
def clock_read()
  [
    {op: "sub", dst: "rsp", imm: 16},
    {op: "mov", dst: "rdi", imm: 0},
    {op: "mov", dst: "rsi", src: "rsp"},
    {op: "push", src: "rsi"},
    {op: "mov", dst: "rax", imm: 228},
    {op: "syscall"},
    {op: "pop", dst: "rsi"},
    {op: "load", dst: "rax", base: "rsi", disp: 0},
    {op: "load", dst: "rcx", base: "rsi", disp: 8},
    {op: "add", dst: "rsp", imm: 16}
  ]
end

@doc """
nanos_in_rax: the instructions that turn clock_read's seconds and nanoseconds into nanoseconds in rax.

    length(nanos_in_rax) #=> 3
"""
def nanos_in_rax()
  [
    {op: "mov", dst: "rdx", imm: 1_000_000_000},
    {op: "imul", dst: "rax", src: "rdx"},
    {op: "add", dst: "rax", src: "rcx"}
  ]
end

@doc """
tag_rax: the instructions that tag the integer in rax (n is 2n + 1).

    tag_rax #=> [{op: "add", dst: "rax", src: "rax"}, {op: "add", dst: "rax", imm: 1}]
"""
def tag_rax()
  [{op: "add", dst: "rax", src: "rax"}, {op: "add", dst: "rax", imm: 1}]
end

@doc """
sleep_code: the instructions that pause for the milliseconds in rax (nanosleep, 35), answering nil.

    last(sleep_code) #=> {op: "mov", dst: "rax", imm: 0}
"""
def sleep_code()
  [
    {op: "cqo"},
    {op: "mov", dst: "r9", imm: 1000},
    {op: "idiv", src: "r9"},
    {op: "mov", dst: "r8", imm: 1_000_000},
    {op: "imul", dst: "rdx", src: "r8"},
    {op: "sub", dst: "rsp", imm: 16},
    {op: "mov", dst: "r10", src: "rsp"},
    {op: "store", src: "rax", base: "r10", disp: 0},
    {op: "store", src: "rdx", base: "r10", disp: 8},
    {op: "mov", dst: "rdi", src: "r10"},
    {op: "mov", dst: "rsi", imm: 0},
    {op: "mov", dst: "rax", imm: 35},
    {op: "syscall"},
    {op: "add", dst: "rsp", imm: 16},
    {op: "mov", dst: "rax", imm: 0}
  ]
end

@doc """
clock_code: one clock word natively: now, now_ms and now_ns read the clock; elapsed_since subtracts its argument from now_ns; sleep and sleep_ms pause and answer nil.

    clock_code([], "now", [])[4] #=> {op: "mov", dst: "rax", imm: 228}
"""
def clock_code(slots, op, args)
  if op == "now"
    append(clock_read, tag_rax)
  elsif op == "now_ns"
    append(*[clock_read, nanos_in_rax, tag_rax])
  elsif op == "now_ms"
    append(
      *[
        clock_read,
        [
          {op: "mov", dst: "rdx", imm: 1000},
          {op: "imul", dst: "rax", src: "rdx"},
          {op: "mov", dst: "r8", src: "rax"},
          {op: "mov", dst: "rax", src: "rcx"},
          {op: "cqo"},
          {op: "mov", dst: "r9", imm: 1_000_000},
          {op: "idiv", src: "r9"},
          {op: "add", dst: "rax", src: "r8"}
        ],
        tag_rax
      ]
    )
  elsif op == "elapsed_since"
    append(
      *[
        tagged_atom(slots, args[0], "r10"),
        [{op: "sar1", dst: "r10"}, {op: "push", src: "r10"}],
        clock_read,
        nanos_in_rax,
        [{op: "pop", dst: "r10"}, {op: "sub", dst: "rax", src: "r10"}],
        tag_rax
      ]
    )
  elsif op == "sleep"
    append(
      *[
        tagged_atom(slots, args[0], "rax"),
        [
          {op: "sar1", dst: "rax"},
          {op: "mov", dst: "rdx", imm: 1000},
          {op: "imul", dst: "rax", src: "rdx"}
        ],
        sleep_code
      ]
    )
  else
    append(
      tagged_atom(slots, args[0], "rax"),
      append([{op: "sar1", dst: "rax"}], sleep_code)
    )
  end
end

@doc """
CLOCK_PROGRAMS: programs over the clock words, with the exit status each must give: each checks a relation that holds whenever it runs, since the time itself does not repeat.

    length(CLOCK_PROGRAMS) #=> 4
"""
CLOCK_PROGRAMS = [
  ["(if (> (now) 1700000000) 1 0)", 1],
  [
    "(let ((a (now)) (b (now_ms))) (if (< (- b (* a 1000)) 2000) (if (> (- b (* a 1000)) -1) 1 0) 0))",
    1
  ],
  ["(let ((n (now_ns)) (s (now))) (if (> n (* s 1000000000)) 1 0))", 1],
  [
    "(let ((s (now_ns))) (begin (sleep_ms 20) (if (> (elapsed_since s) 15000000) 1 0)))",
    1
  ]
]

test "the clock words read the time and pause natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru"), "clock.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      CLOCK_PROGRAMS
    )
  end
end

test "every clock word has native code that assembles, and sleep pauses by nanosleep"
  bad = filter((w) -> length(clock_code([], w, [1])) == 0, CLOCK_WORDS)
  assert bad == []
  assert member?({op: "mov", dst: "rax", imm: 35}, sleep_code)
  assert length(assemble(clock_code([], "now_ms", []))) > 0
  assert length(assemble(clock_code([], "elapsed_since", [1]))) > 0
  assert length(assemble(clock_code([], "sleep", [1]))) > 0
  assert last(rc_op([], "now", [])) == {op: "add", dst: "rax", imm: 1}
end

@doc """
text_word: up to eight bytes of text as the little-endian word that holds them, zero-padded: what a store of one register writes as those bytes.

    text_word("ab") #=> 25185
"""
def text_word(text)
  reduce((acc, b) -> acc * 256 + b, 0, reverse(text_bytes(text)))
end

@doc """
RT_SELF_EXE: self_exe natively (R4 of docs/PURE-BLUE.md): the path of the running executable, read from /proc/self/exe (readlink, 89), a path built on the stack from two words (text_word), into a stack buffer of 4096 bytes and copied into a new string answered in rax.

    RT_SELF_EXE[0] #=> {op: "label", name: "rt_self_exe"}
"""
RT_SELF_EXE = append(
  *[
    [
      {op: "label", name: "rt_self_exe"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 4128},
      {op: "mov", dst: "r11", src: "rsp"},
      {op: "movabs", dst: "rcx", imm: text_word("/proc/se")},
      {op: "store", src: "rcx", base: "r11", disp: 4096},
      {op: "movabs", dst: "rcx", imm: text_word("lf/exe")},
      {op: "store", src: "rcx", base: "r11", disp: 4104},
      {op: "mov", dst: "rdi", src: "r11"},
      {op: "add", dst: "rdi", imm: 4096},
      {op: "mov", dst: "rsi", src: "rsp"},
      {op: "mov", dst: "rdx", imm: 4096},
      {op: "mov", dst: "rax", imm: 89},
      {op: "syscall"},
      {op: "store", src: "rax", base: "rbp", disp: -8},
      {op: "mov", dst: "rdi", src: "rax"},
      {op: "add", dst: "rdi", imm: 7},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "shr1", dst: "rdi"},
      {op: "add", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "load", dst: "r8", base: "rbp", disp: -8},
      {op: "store", src: "r8", base: "rax", disp: 24},
      {op: "mov", dst: "r11", src: "rax"},
      {op: "add", dst: "r11", imm: 32},
      {op: "mov", dst: "rdx", src: "rsp"},
      {op: "store", src: "rax", base: "rbp", disp: -16}
    ],
    copy_bytes("r8", "rt_self_exe_copy"),
    [
      {op: "load", dst: "rax", base: "rbp", disp: -16},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

test "self_exe reads the running executable's path natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-self"), "self.out")
    form = read_forms("(begin (write_stdout (self_exe)) 0)")[0]
    write_bytes(path, compile_whole(form, :exit))
    exec_capture("chmod", "+x", path)
    r = exec_capture(path)
    assert status_of(r) == 0
    assert stdout_of(r) == path
    write_bytes(path, compile_whole(form, :leaks))
    exec_capture("chmod", "+x", path)
    assert status_of(exec_capture(path)) == 0
  end
end

test "self_exe builds /proc/self/exe on the stack and readlinks it"
  assert text_word("ab") == 25185
  assert member?({op: "mov", dst: "rax", imm: 89}, RT_SELF_EXE)
  assert last(rc_op([], "self_exe", [])) ==
    {op: "call_label", label: "rt_self_exe"}
  stand_ins = [{op: "label", name: "rt_alloc"}, {op: "ret"}]
  assert length(assemble(append(RT_SELF_EXE, stand_ins))) > 0
end

@doc """
argv_on_stack: the instructions that build, below rbp, the argv of a command from the list of strings at rbp-8, the command first: argv at rbp-24 (rbp-16, -40 and -48 are its scratch), each argument copied NUL-ended, the array ending in nil. Labels are named from tag.

    argv_on_stack("t")[0] #=> {op: "mov", dst: "r10", imm: 0}
"""
def argv_on_stack(tag)
  append(
    *[
      [
        {op: "mov", dst: "r10", imm: 0},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "mov", dst: "rdx", src: "rdi"},
        {op: "label", name: "#{tag}_size"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_sized"},
        {op: "load", dst: "r8", base: "rdx", disp: 24},
        {op: "load", dst: "r9", base: "r8", disp: 24},
        {op: "add", dst: "rcx", src: "r9"},
        {op: "add", dst: "rcx", imm: 1},
        {op: "add", dst: "r10", imm: 1},
        {op: "load", dst: "rdx", base: "rdx", disp: 32},
        {op: "jmp", label: "#{tag}_size"},
        {op: "label", name: "#{tag}_sized"},
        {op: "mov", dst: "r9", src: "r10"},
        {op: "add", dst: "r9", imm: 1}
      ],
      times8("r9"),
      [
        {op: "store", src: "r9", base: "rbp", disp: -16},
        {op: "add", dst: "rcx", src: "r9"},
        {op: "add", dst: "rcx", imm: 31},
        {op: "and", dst: "rcx", imm: -16},
        {op: "sub", dst: "rsp", src: "rcx"},
        {op: "mov", dst: "r11", src: "rsp"},
        {op: "store", src: "r11", base: "rbp", disp: -24},
        {op: "add", dst: "r11", src: "r9"},
        {op: "load", dst: "rax", base: "rbp", disp: -24},
        {op: "store", src: "rax", base: "rbp", disp: -40},
        {op: "load", dst: "rdx", base: "rbp", disp: -8},
        {op: "label", name: "#{tag}_arg"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_argv_done"},
        {op: "store", src: "rdx", base: "rbp", disp: -48},
        {op: "load", dst: "rax", base: "rbp", disp: -40},
        {op: "store", src: "r11", base: "rax", disp: 0},
        {op: "add", dst: "rax", imm: 8},
        {op: "store", src: "rax", base: "rbp", disp: -40},
        {op: "load", dst: "r8", base: "rdx", disp: 24},
        {op: "load", dst: "r9", base: "r8", disp: 24},
        {op: "mov", dst: "rdx", src: "r8"},
        {op: "add", dst: "rdx", imm: 32}
      ],
      copy_bytes("r9", "#{tag}_copy"),
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store_byte", src: "rcx", base: "r11"},
        {op: "add", dst: "r11", imm: 1},
        {op: "load", dst: "rdx", base: "rbp", disp: -48},
        {op: "load", dst: "rdx", base: "rdx", disp: 32},
        {op: "jmp", label: "#{tag}_arg"},
        {op: "label", name: "#{tag}_argv_done"},
        {op: "load", dst: "rax", base: "rbp", disp: -40},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rax", disp: 0}
      ]
    ]
  )
end

@doc """
envp_with: the instructions that set the environment a child runs with, at rbp+out: the program's own (r14 + ENVP_AT) when the list at rbp+extra is empty, else a new one on the stack holding each [name, value] of that list as name=value, then every inherited entry whose name the list does not set, so a listed name replaces the inherited one as the reference does. rbp-280 to rbp-312 are its scratch; labels are named from tag.

    envp_with(-264, -272, "t")[0] #=> {op: "load", dst: "r9", base: "rbp", disp: -264}
"""
def envp_with(extra, out, tag)
  append(
    *[
      [
        {op: "load", dst: "r9", base: "rbp", disp: extra},
        {op: "cmp", dst: "r9", imm: 0},
        {op: "j", cond: "ne", label: "#{tag}_build"},
        {op: "load", dst: "rcx", base: "r14", disp: ENVP_AT},
        {op: "store", src: "rcx", base: "rbp", disp: out},
        {op: "jmp", label: "#{tag}_done"},
        {op: "label", name: "#{tag}_build"},
        {op: "load", dst: "r10", base: "r14", disp: ENVP_AT},
        {op: "mov", dst: "rax", imm: 0},
        {op: "label", name: "#{tag}_base"},
        {op: "load", dst: "rcx", base: "r10", disp: 0},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_based"},
        {op: "add", dst: "rax", imm: 1},
        {op: "add", dst: "r10", imm: 8},
        {op: "jmp", label: "#{tag}_base"},
        {op: "label", name: "#{tag}_based"},
        {op: "mov", dst: "r8", imm: 0},
        {op: "mov", dst: "r11", imm: 0},
        {op: "mov", dst: "rdx", src: "r9"},
        {op: "label", name: "#{tag}_size"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_sized"},
        {op: "load", dst: "rcx", base: "rdx", disp: 24},
        {op: "load", dst: "rsi", base: "rcx", disp: 24},
        {op: "load", dst: "rsi", base: "rsi", disp: 24},
        {op: "add", dst: "r11", src: "rsi"},
        {op: "load", dst: "rcx", base: "rcx", disp: 32},
        {op: "load", dst: "rcx", base: "rcx", disp: 24},
        {op: "load", dst: "rcx", base: "rcx", disp: 24},
        {op: "add", dst: "r11", src: "rcx"},
        {op: "add", dst: "r11", imm: 2},
        {op: "add", dst: "r8", imm: 1},
        {op: "load", dst: "rdx", base: "rdx", disp: 32},
        {op: "jmp", label: "#{tag}_size"},
        {op: "label", name: "#{tag}_sized"},
        {op: "mov", dst: "rcx", src: "rax"},
        {op: "add", dst: "rcx", src: "r8"},
        {op: "add", dst: "rcx", imm: 1}
      ],
      times8("rcx"),
      [
        {op: "mov", dst: "rsi", src: "rcx"},
        {op: "add", dst: "rsi", src: "r11"},
        {op: "add", dst: "rsi", imm: 15},
        {op: "and", dst: "rsi", imm: -16},
        {op: "sub", dst: "rsp", src: "rsi"},
        {op: "mov", dst: "r10", src: "rsp"},
        {op: "store", src: "r10", base: "rbp", disp: out},
        {op: "store", src: "r10", base: "rbp", disp: -288},
        {op: "mov", dst: "rsi", src: "rsp"},
        {op: "add", dst: "rsi", src: "rcx"},
        {op: "store", src: "rsi", base: "rbp", disp: -296},
        {op: "load", dst: "rdx", base: "rbp", disp: extra},
        {op: "label", name: "#{tag}_pair"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_paired"},
        {op: "store", src: "rdx", base: "rbp", disp: -280},
        {op: "load", dst: "r10", base: "rbp", disp: -288},
        {op: "load", dst: "r11", base: "rbp", disp: -296},
        {op: "store", src: "r11", base: "r10", disp: 0},
        {op: "add", dst: "r10", imm: 8},
        {op: "store", src: "r10", base: "rbp", disp: -288},
        {op: "load", dst: "rcx", base: "rdx", disp: 24},
        {op: "store", src: "rcx", base: "rbp", disp: -304},
        {op: "load", dst: "rsi", base: "rcx", disp: 24},
        {op: "load", dst: "r8", base: "rsi", disp: 24},
        {op: "mov", dst: "rdx", src: "rsi"},
        {op: "add", dst: "rdx", imm: 32}
      ],
      copy_bytes("r8", "#{tag}_name"),
      [
        {op: "mov", dst: "rcx", imm: 61},
        {op: "store_byte", src: "rcx", base: "r11"},
        {op: "add", dst: "r11", imm: 1},
        {op: "load", dst: "rcx", base: "rbp", disp: -304},
        {op: "load", dst: "rcx", base: "rcx", disp: 32},
        {op: "load", dst: "rsi", base: "rcx", disp: 24},
        {op: "load", dst: "r8", base: "rsi", disp: 24},
        {op: "mov", dst: "rdx", src: "rsi"},
        {op: "add", dst: "rdx", imm: 32}
      ],
      copy_bytes("r8", "#{tag}_value"),
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store_byte", src: "rcx", base: "r11"},
        {op: "add", dst: "r11", imm: 1},
        {op: "store", src: "r11", base: "rbp", disp: -296},
        {op: "load", dst: "rdx", base: "rbp", disp: -280},
        {op: "load", dst: "rdx", base: "rdx", disp: 32},
        {op: "jmp", label: "#{tag}_pair"},
        {op: "label", name: "#{tag}_paired"},
        {op: "load", dst: "rsi", base: "r14", disp: ENVP_AT},
        {op: "store", src: "rsi", base: "rbp", disp: -312},
        {op: "label", name: "#{tag}_copy"},
        {op: "load", dst: "rsi", base: "rbp", disp: -312},
        {op: "load", dst: "rcx", base: "rsi", disp: 0},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_finish"},
        {op: "load", dst: "rdx", base: "rbp", disp: extra},
        {op: "label", name: "#{tag}_shadow"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_keep"},
        {op: "load", dst: "r8", base: "rdx", disp: 24},
        {op: "load", dst: "r8", base: "r8", disp: 24},
        {op: "load", dst: "r9", base: "r8", disp: 24},
        {op: "add", dst: "r8", imm: 32},
        {op: "mov", dst: "r11", imm: 0},
        {op: "label", name: "#{tag}_byte"},
        {op: "cmp", dst: "r11", src: "r9"},
        {op: "j", cond: "e", label: "#{tag}_named"},
        {op: "mov", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", src: "r11"},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "mov", dst: "r10", src: "r8"},
        {op: "add", dst: "r10", src: "r11"},
        {op: "load_byte", dst: "r10", base: "r10"},
        {op: "cmp", dst: "rax", src: "r10"},
        {op: "j", cond: "ne", label: "#{tag}_other"},
        {op: "add", dst: "r11", imm: 1},
        {op: "jmp", label: "#{tag}_byte"},
        {op: "label", name: "#{tag}_named"},
        {op: "mov", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", src: "r9"},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "cmp", dst: "rax", imm: 61},
        {op: "j", cond: "e", label: "#{tag}_skip"},
        {op: "label", name: "#{tag}_other"},
        {op: "load", dst: "rdx", base: "rdx", disp: 32},
        {op: "jmp", label: "#{tag}_shadow"},
        {op: "label", name: "#{tag}_keep"},
        {op: "load", dst: "r10", base: "rbp", disp: -288},
        {op: "store", src: "rcx", base: "r10", disp: 0},
        {op: "add", dst: "r10", imm: 8},
        {op: "store", src: "r10", base: "rbp", disp: -288},
        {op: "label", name: "#{tag}_skip"},
        {op: "load", dst: "rsi", base: "rbp", disp: -312},
        {op: "add", dst: "rsi", imm: 8},
        {op: "store", src: "rsi", base: "rbp", disp: -312},
        {op: "jmp", label: "#{tag}_copy"},
        {op: "label", name: "#{tag}_finish"},
        {op: "load", dst: "r10", base: "rbp", disp: -288},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "r10", disp: 0},
        {op: "label", name: "#{tag}_done"}
      ]
    ]
  )
end

@doc """
PATH_PREFIX_MASK: the low five bytes of a word, the length of "PATH=", for finding the PATH entry of an environment by comparing one word.

    PATH_PREFIX_MASK #=> 1_099_511_627_775
"""
PATH_PREFIX_MASK = 1_099_511_627_775

@doc """
exec_child: the child's half of running a command, after the fork: argv is at rbp-24 and the environment it runs with at rbp+envp. A command holding a slash is run as given; any other is tried as dir/command for each directory of the environment's PATH, in order, as a shell finds it. A command that runs nowhere exits 127.

    exec_child("t", -64)[0] #=> {op: "load", dst: "r9", base: "rbp", disp: -24}
"""
def exec_child(tag, envp)
  execve = [
    {op: "load", dst: "rsi", base: "rbp", disp: -24},
    {op: "load", dst: "rdx", base: "rbp", disp: envp},
    {op: "mov", dst: "rax", imm: 59},
    {op: "syscall"}
  ]
  append(
    *[
      [
        {op: "load", dst: "r9", base: "rbp", disp: -24},
        {op: "load", dst: "r9", base: "r9", disp: 0},
        {op: "mov", dst: "r8", src: "r9"},
        {op: "label", name: "#{tag}_slash"},
        {op: "load_byte", dst: "rcx", base: "r8"},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_search"},
        {op: "cmp", dst: "rcx", imm: 47},
        {op: "j", cond: "e", label: "#{tag}_direct"},
        {op: "add", dst: "r8", imm: 1},
        {op: "jmp", label: "#{tag}_slash"},
        {op: "label", name: "#{tag}_direct"},
        {op: "mov", dst: "rdi", src: "r9"}
      ],
      execve,
      [
        {op: "jmp", label: "#{tag}_fail"},
        {op: "label", name: "#{tag}_search"},
        {op: "load", dst: "r10", base: "rbp", disp: envp},
        {op: "label", name: "#{tag}_env"},
        {op: "load", dst: "r8", base: "r10", disp: 0},
        {op: "cmp", dst: "r8", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_fail"},
        {op: "load", dst: "rax", base: "r8", disp: 0},
        {op: "movabs", dst: "rcx", imm: PATH_PREFIX_MASK},
        {op: "and", dst: "rax", src: "rcx"},
        {op: "movabs", dst: "rcx", imm: text_word("PATH=")},
        {op: "cmp", dst: "rax", src: "rcx"},
        {op: "j", cond: "e", label: "#{tag}_path"},
        {op: "add", dst: "r10", imm: 8},
        {op: "jmp", label: "#{tag}_env"},
        {op: "label", name: "#{tag}_path"},
        {op: "add", dst: "r8", imm: 5},
        {op: "sub", dst: "rsp", imm: 4096},
        {op: "label", name: "#{tag}_dir"},
        {op: "load_byte", dst: "rcx", base: "r8"},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_fail"},
        {op: "mov", dst: "rdx", src: "rsp"},
        {op: "label", name: "#{tag}_dir_byte"},
        {op: "load_byte", dst: "rcx", base: "r8"},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_dir_end"},
        {op: "cmp", dst: "rcx", imm: 58},
        {op: "j", cond: "e", label: "#{tag}_dir_end"},
        {op: "store_byte", src: "rcx", base: "rdx"},
        {op: "add", dst: "rdx", imm: 1},
        {op: "add", dst: "r8", imm: 1},
        {op: "jmp", label: "#{tag}_dir_byte"},
        {op: "label", name: "#{tag}_dir_end"},
        {op: "mov", dst: "rcx", imm: 47},
        {op: "store_byte", src: "rcx", base: "rdx"},
        {op: "add", dst: "rdx", imm: 1},
        {op: "load", dst: "r9", base: "rbp", disp: -24},
        {op: "load", dst: "r9", base: "r9", disp: 0},
        {op: "label", name: "#{tag}_cmd_byte"},
        {op: "load_byte", dst: "rcx", base: "r9"},
        {op: "store_byte", src: "rcx", base: "rdx"},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_built"},
        {op: "add", dst: "rdx", imm: 1},
        {op: "add", dst: "r9", imm: 1},
        {op: "jmp", label: "#{tag}_cmd_byte"},
        {op: "label", name: "#{tag}_built"},
        {op: "mov", dst: "rdi", src: "rsp"}
      ],
      execve,
      [
        {op: "load_byte", dst: "rcx", base: "r8"},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_fail"},
        {op: "add", dst: "r8", imm: 1},
        {op: "jmp", label: "#{tag}_dir"},
        {op: "label", name: "#{tag}_fail"},
        {op: "mov", dst: "rdi", imm: 127},
        {op: "mov", dst: "rax", imm: 60},
        {op: "syscall"}
      ]
    ]
  )
end

@doc """
RT_EXEC_CHECK: exec_check natively (R4 of docs/PURE-BLUE.md): the list of strings in rdi, a command and its arguments, consumed; the command runs with no shell and the program's own environment, its output passing through, and its exit status is answered in rax. The child finds the command as a shell does (exec_child: as given when it holds a slash, else on the environment's PATH); argv and each argument, NUL-ended, are built on the stack. A command that runs nowhere exits 127, as a shell reports it.

    RT_EXEC_CHECK[0] #=> {op: "label", name: "rt_exec_check"}
"""
RT_EXEC_CHECK = append(
  *[
    [
      {op: "label", name: "rt_exec_check"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 64},
      {op: "store", src: "rdi", base: "rbp", disp: -8}
    ],
    argv_on_stack("rt_ex"),
    [
      {op: "mov", dst: "rax", imm: 57},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_ex_parent"}
    ],
    [
      {op: "load", dst: "rcx", base: "r14", disp: ENVP_AT},
      {op: "store", src: "rcx", base: "rbp", disp: -64}
    ],
    exec_child("rt_ex", -64),
    [
      {op: "label", name: "rt_ex_parent"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -56},
      {op: "mov", dst: "rdi", src: "rax"},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -56},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "mov", dst: "r10", imm: 0},
      {op: "mov", dst: "rax", imm: 61},
      {op: "syscall"},
      {op: "load", dst: "rax", base: "rbp", disp: -56},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "shr1", dst: "rax"},
      {op: "and", dst: "rax", imm: 255},
      {op: "add", dst: "rax", src: "rax"},
      {op: "add", dst: "rax", imm: 1},
      {op: "store", src: "rax", base: "rbp", disp: -56},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rax", base: "rbp", disp: -56},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
exec_programs: programs over exec_check, with the exit status and output each must give: a command found on PATH whose status and output pass through, a failing one, and one that does not exist (127).

    length(exec_programs) #=> 3
"""
def exec_programs()
  [
    ["(exec_check \"echo\" \"hi\" \"there\")", 0, unlines(["hi there"])],
    ["(exec_check \"sh\" \"-c\" \"exit 3\")", 3, ""],
    ["(exec_check \"no-such-command-here\")", 127, ""]
  ]
end

test "exec_check runs a command natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-exec"), "exec.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
      end,
      exec_programs
    )
  end
end

test "exec_check forks, finds the command on PATH in the inherited environment and waits"
  assert member?({op: "mov", dst: "rax", imm: 57}, RT_EXEC_CHECK)
  assert member?({op: "mov", dst: "rax", imm: 59}, RT_EXEC_CHECK)
  assert member?({op: "mov", dst: "rax", imm: 61}, RT_EXEC_CHECK)
  assert member?(
    {op: "load", dst: "rcx", base: "r14", disp: ENVP_AT},
    RT_EXEC_CHECK
  )
  assert last(save_envp)[:disp] == ENVP_AT
  assert last(rc_op([], "exec_check", ["c"])) ==
    {op: "call_label", label: "rt_exec_check"}
  stand_ins = [{op: "label", name: "rt_drop"}, {op: "ret"}]
  assert length(assemble(append(RT_EXEC_CHECK, stand_ins))) > 0
end

@doc """
CAPTURE_BYTES: how much each captured stream may hold: its own mapping, committed only as it is written, so a large reservation costs nothing until used.

    CAPTURE_BYTES #=> 268_435_456
"""
CAPTURE_BYTES = 268_435_456

@doc """
CAPTURE_KEYWORDS: the keywords exec_capture's answer names, placed in the data section of every program built by rc_whole.

    CAPTURE_KEYWORDS #=> %i[status stdout stderr]
"""
CAPTURE_KEYWORDS = %i[status stdout stderr]

@doc """
NETWORK_KEYWORDS: the keywords tcp_connect_ms answers with when a connect fails: :error, then why.

    NETWORK_KEYWORDS[0] #=> :error
"""
NETWORK_KEYWORDS = %i[error refused timeout unreachable unresolved failed]

@doc """
NET_WAIT_KEYWORDS: the interests net_wait reads and the readiness it answers.

    NET_WAIT_KEYWORDS #=> %i[read write both closed]
"""
NET_WAIT_KEYWORDS = %i[read write both closed]

@doc """
RUNTIME_KEYWORDS: every keyword a runtime routine answers with, placed in the data section of every program rc_whole builds.

    length(RUNTIME_KEYWORDS) #=> 13
"""
RUNTIME_KEYWORDS = append(
  *[CAPTURE_KEYWORDS, NETWORK_KEYWORDS, NET_WAIT_KEYWORDS]
)

@doc """
split_fds: the instructions that split the two descriptors pipe wrote (two 32-bit words at rbp+at) into the read end at rbp+r and the write end at rbp+w.

    length(split_fds(-80, -96, -104)) > 32 #=> true
"""
def split_fds(at, r, w)
  append(
    *[
      [
        {op: "load", dst: "rax", base: "rbp", disp: at},
        {op: "mov", dst: "rcx", src: "rax"}
      ],
      map((_k) -> {op: "shr1", dst: "rcx"}, range(0, 32)),
      [
        {op: "store", src: "rcx", base: "rbp", disp: w},
        {op: "movabs", dst: "r8", imm: 4_294_967_296},
        {op: "imul", dst: "rcx", src: "r8"},
        {op: "sub", dst: "rax", src: "rcx"},
        {op: "store", src: "rax", base: "rbp", disp: r}
      ]
    ]
  )
end

@doc """
poll_word: the instructions that write one pollfd at rbp+slot for the descriptor at rbp+fd, waiting for events (1, POLLIN, to read; 4, POLLOUT, to write): a closed stream holds -1, which poll ignores.

    last(poll_word(-96, -184, 1)) #=> {op: "store", src: "rax", base: "rbp", disp: -184}
"""
def poll_word(fd, slot, events)
  [
    {op: "load", dst: "rax", base: "rbp", disp: fd},
    {op: "cmp", dst: "rax", imm: 0},
    {op: "j", cond: "ge", label: "rt_xc_fd#{to_s(-slot)}"},
    {op: "movabs", dst: "rax", imm: 4_294_967_295},
    {op: "label", name: "rt_xc_fd#{to_s(-slot)}"},
    {op: "movabs", dst: "rcx", imm: events * 4_294_967_296},
    {op: "add", dst: "rax", src: "rcx"},
    {op: "store", src: "rax", base: "rbp", disp: slot}
  ]
end

@doc """
drain_ready: the instructions that, when the pollfd at rbp+slot has events, read what its descriptor holds into the buffer at rbp+buf after its length at rbp+len; an end of stream closes the descriptor, marks it -1 and counts one stream fewer at rbp-192.

    length(drain_ready(-184, -96, -128, -136)) > 48 #=> true
"""
def drain_ready(slot, fd, buf, len)
  tag = "rt_xc_drain#{to_s(-slot)}"
  append(
    *[
      [{op: "load", dst: "rax", base: "rbp", disp: slot}],
      map((_k) -> {op: "shr1", dst: "rax"}, range(0, 48)),
      [
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_skip"},
        {op: "load", dst: "rdi", base: "rbp", disp: fd},
        {op: "load", dst: "rsi", base: "rbp", disp: buf},
        {op: "load", dst: "rcx", base: "rbp", disp: len},
        {op: "add", dst: "rsi", src: "rcx"},
        {op: "mov", dst: "rdx", imm: CAPTURE_BYTES},
        {op: "sub", dst: "rdx", src: "rcx"},
        {op: "mov", dst: "rax", imm: 0},
        {op: "syscall"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "le", label: "#{tag}_end"},
        {op: "load", dst: "rcx", base: "rbp", disp: len},
        {op: "add", dst: "rcx", src: "rax"},
        {op: "store", src: "rcx", base: "rbp", disp: len},
        {op: "jmp", label: "#{tag}_skip"},
        {op: "label", name: "#{tag}_end"},
        {op: "load", dst: "rdi", base: "rbp", disp: fd},
        {op: "mov", dst: "rax", imm: 3},
        {op: "syscall"},
        {op: "mov", dst: "rcx", imm: -1},
        {op: "store", src: "rcx", base: "rbp", disp: fd},
        {op: "load", dst: "rcx", base: "rbp", disp: -192},
        {op: "sub", dst: "rcx", imm: 1},
        {op: "store", src: "rcx", base: "rbp", disp: -192},
        {op: "label", name: "#{tag}_skip"}
      ]
    ]
  )
end

@doc """
sigpipe_to: the instructions that set what SIGPIPE does (rt_sigaction, 13) to handler: 1 ignores it, so writing to a pipe whose reader has gone answers an error instead of ending the program; 0 restores the default, which a child sets before it runs its command. The sigaction it passes is at rbp-472.

    sigpipe_to(1)[0] #=> {op: "mov", dst: "rcx", imm: 1}
"""
def sigpipe_to(handler)
  [
    {op: "mov", dst: "rcx", imm: handler},
    {op: "store", src: "rcx", base: "rbp", disp: -472},
    {op: "mov", dst: "rcx", imm: 0},
    {op: "store", src: "rcx", base: "rbp", disp: -464},
    {op: "store", src: "rcx", base: "rbp", disp: -456},
    {op: "store", src: "rcx", base: "rbp", disp: -448},
    {op: "mov", dst: "rdi", imm: 13},
    {op: "mov", dst: "rsi", src: "rbp"},
    {op: "add", dst: "rsi", imm: -472},
    {op: "mov", dst: "rdx", imm: 0},
    {op: "mov", dst: "r10", imm: 8},
    {op: "mov", dst: "rax", imm: 13},
    {op: "syscall"}
  ]
end

@doc """
stdin_pipe: the instructions that, when an input string is at rbp-328, make the pipe the child reads it from (read end at rbp-344, write end at rbp-352, bytes written so far at rbp-360); with no input both ends are -1 and the child keeps the program's stdin.

    stdin_pipe[0] #=> {op: "mov", dst: "rcx", imm: -1}
"""
def stdin_pipe()
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: -1},
        {op: "store", src: "rcx", base: "rbp", disp: -344},
        {op: "store", src: "rcx", base: "rbp", disp: -352},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -360},
        {op: "load", dst: "rcx", base: "rbp", disp: -328},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "rt_xc_no_input"},
        {op: "mov", dst: "rdi", src: "rbp"},
        {op: "add", dst: "rdi", imm: -336},
        {op: "mov", dst: "rax", imm: 22},
        {op: "syscall"}
      ],
      split_fds(-336, -344, -352),
      [{op: "label", name: "rt_xc_no_input"}]
    ]
  )
end

@doc """
PIPE_BUF: the bytes a pipe that poll reports writable is sure to take without blocking (Linux's PIPE_BUF), so one write of at most this much never waits on a reader that is itself waiting to be read.

    PIPE_BUF #=> 4096
"""
PIPE_BUF = 4096

@doc """
feed_ready: the instructions that, when the pollfd at rbp+slot shows the child's stdin ready, write the next part of the input at rbp-328 to it, at most PIPE_BUF bytes so the write cannot block, and close it once all is written or a write fails (the child has gone).

    length(feed_ready(-416)) > 48 #=> true
"""
def feed_ready(slot)
  append(
    *[
      [{op: "load", dst: "rax", base: "rbp", disp: slot}],
      map((_k) -> {op: "shr1", dst: "rax"}, range(0, 48)),
      [
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "rt_xc_feed_skip"},
        {op: "load", dst: "rdi", base: "rbp", disp: -352},
        {op: "cmp", dst: "rdi", imm: 0},
        {op: "j", cond: "l", label: "rt_xc_feed_skip"},
        {op: "load", dst: "rsi", base: "rbp", disp: -328},
        {op: "load", dst: "rdx", base: "rsi", disp: 24},
        {op: "load", dst: "rcx", base: "rbp", disp: -360},
        {op: "cmp", dst: "rcx", src: "rdx"},
        {op: "j", cond: "ge", label: "rt_xc_feed_close"},
        {op: "add", dst: "rsi", imm: 32},
        {op: "add", dst: "rsi", src: "rcx"},
        {op: "sub", dst: "rdx", src: "rcx"},
        {op: "cmp", dst: "rdx", imm: PIPE_BUF},
        {op: "j", cond: "le", label: "rt_xc_feed_write"},
        {op: "mov", dst: "rdx", imm: PIPE_BUF},
        {op: "label", name: "rt_xc_feed_write"},
        {op: "mov", dst: "rax", imm: 1},
        {op: "syscall"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "le", label: "rt_xc_feed_close"},
        {op: "load", dst: "rcx", base: "rbp", disp: -360},
        {op: "add", dst: "rcx", src: "rax"},
        {op: "store", src: "rcx", base: "rbp", disp: -360},
        {op: "load", dst: "rsi", base: "rbp", disp: -328},
        {op: "load", dst: "rdx", base: "rsi", disp: 24},
        {op: "cmp", dst: "rcx", src: "rdx"},
        {op: "j", cond: "l", label: "rt_xc_feed_skip"},
        {op: "label", name: "rt_xc_feed_close"},
        {op: "load", dst: "rdi", base: "rbp", disp: -352},
        {op: "mov", dst: "rax", imm: 3},
        {op: "syscall"},
        {op: "mov", dst: "rcx", imm: -1},
        {op: "store", src: "rcx", base: "rbp", disp: -352},
        {op: "label", name: "rt_xc_feed_skip"}
      ]
    ]
  )
end

@doc """
string_from_buffer: the instructions that copy the bytes at the buffer at rbp+buf, its length at rbp+len, into a new string block stored at rbp+dest.

    last(string_from_buffer(-128, -136, -248, "t")) #=> {op: "load", dst: "rax", base: "rbp", disp: -248}
"""
def string_from_buffer(buf, len, dest, tag)
  append(
    *[
      [
        {op: "load", dst: "rdi", base: "rbp", disp: len},
        {op: "add", dst: "rdi", imm: 7},
        {op: "shr1", dst: "rdi"},
        {op: "shr1", dst: "rdi"},
        {op: "shr1", dst: "rdi"},
        {op: "add", dst: "rdi", imm: 4},
        {op: "call_label", label: "rt_alloc"},
        {op: "mov", dst: "rcx", imm: 1},
        {op: "store", src: "rcx", base: "rax", disp: 0},
        {op: "load", dst: "r8", base: "rbp", disp: len},
        {op: "store", src: "r8", base: "rax", disp: 24},
        {op: "store", src: "rax", base: "rbp", disp: dest},
        {op: "mov", dst: "r11", src: "rax"},
        {op: "add", dst: "r11", imm: 32},
        {op: "load", dst: "rdx", base: "rbp", disp: buf}
      ],
      copy_bytes("r8", tag),
      [{op: "load", dst: "rax", base: "rbp", disp: dest}]
    ]
  )
end

@doc """
cell: the instructions that allocate one cons cell whose head is the word at rbp+head and whose tail is the word at rbp+tail (0 for nil), stored at rbp+dest.

    last(cell(-56, 0, -208)) #=> {op: "store", src: "rax", base: "rbp", disp: -208}
"""
def cell(head, tail, dest)
  append(
    *[
      [
        {op: "mov", dst: "rdi", imm: 5},
        {op: "call_label", label: "rt_alloc"},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rax", disp: 0}
      ],
      if tail == 0
        [{op: "mov", dst: "rcx", imm: 0}]
      else
        [{op: "load", dst: "rcx", base: "rbp", disp: tail}]
      end,
      [
        {op: "store", src: "rcx", base: "rax", disp: 32},
        {op: "load", dst: "rcx", base: "rbp", disp: head},
        {op: "store", src: "rcx", base: "rax", disp: 24},
        {op: "store", src: "rax", base: "rbp", disp: dest}
      ]
    ]
  )
end

@doc """
RT_EXEC_CAPTURE: exec_capture natively (R4 of docs/PURE-BLUE.md): the list of strings in rdi, a command and its arguments, consumed, with the keywords :status, :stdout and :stderr in rsi, rdx and rcx; answered in rax as [[:status, n], [:stdout, s], [:stderr, s]]. The child's stdout and stderr are pipes (dup2), read by poll until both end, so a child filling one cannot block on the other; each is gathered in its own CAPTURE_BYTES mapping, then copied into a string. The command is found and run as exec_check runs it (exec_child).

    RT_EXEC_CAPTURE[0] #=> {op: "label", name: "rt_exec_capture"}
"""
RT_EXEC_CAPTURE = append(
  *[
    [
      {op: "label", name: "rt_exec_capture"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 496},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -56},
      {op: "store", src: "rdx", base: "rbp", disp: -64},
      {op: "store", src: "rcx", base: "rbp", disp: -72},
      {op: "store", src: "r8", base: "rbp", disp: -264},
      {op: "store", src: "r9", base: "rbp", disp: -328}
    ],
    exec_deadline,
    argv_on_stack("rt_xc"),
    sigpipe_to(1),
    [
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: -80},
      {op: "mov", dst: "rax", imm: 22},
      {op: "syscall"},
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: -88},
      {op: "mov", dst: "rax", imm: 22},
      {op: "syscall"}
    ],
    split_fds(-80, -96, -104),
    split_fds(-88, -112, -120),
    stdin_pipe,
    envp_with(-264, -272, "rt_xc_env"),
    flat_map(
      [-128, -144],
      fn(slot)
        [
          {op: "mov", dst: "rdi", imm: 0},
          {op: "mov", dst: "rsi", imm: CAPTURE_BYTES},
          {op: "mov", dst: "rdx", imm: 3},
          {op: "mov", dst: "r10", imm: 34},
          {op: "mov", dst: "r8", imm: -1},
          {op: "mov", dst: "r9", imm: 0},
          {op: "mov", dst: "rax", imm: 9},
          {op: "syscall"},
          {op: "store", src: "rax", base: "rbp", disp: slot},
          {op: "mov", dst: "rcx", imm: 0},
          {op: "store", src: "rcx", base: "rbp", disp: slot - 8}
        ]
      end
    ),
    [
      {op: "mov", dst: "rax", imm: 57},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_xc_parent"}
    ],
    exec_own_group,
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -104},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "mov", dst: "rax", imm: 33},
      {op: "syscall"},
      {op: "load", dst: "rdi", base: "rbp", disp: -120},
      {op: "mov", dst: "rsi", imm: 2},
      {op: "mov", dst: "rax", imm: 33},
      {op: "syscall"},
      {op: "load", dst: "rdi", base: "rbp", disp: -344},
      {op: "cmp", dst: "rdi", imm: 0},
      {op: "j", cond: "l", label: "rt_xc_no_stdin"},
      {op: "mov", dst: "rsi", imm: 0},
      {op: "mov", dst: "rax", imm: 33},
      {op: "syscall"},
      {op: "label", name: "rt_xc_no_stdin"}
    ],
    flat_map(
      [-352, -344, -96, -112],
      fn(slot)
        [
          {op: "load", dst: "rdi", base: "rbp", disp: slot},
          {op: "cmp", dst: "rdi", imm: 0},
          {op: "j", cond: "l", label: "rt_xc_child_close#{to_s(-slot)}"},
          {op: "mov", dst: "rax", imm: 3},
          {op: "syscall"},
          {op: "label", name: "rt_xc_child_close#{to_s(-slot)}"}
        ]
      end
    ),
    sigpipe_to(0),
    exec_child("rt_xc", -272),
    [
      {op: "label", name: "rt_xc_parent"},
      {op: "store", src: "rax", base: "rbp", disp: -160},
      {op: "load", dst: "rdi", base: "rbp", disp: -104},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "load", dst: "rdi", base: "rbp", disp: -120},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "load", dst: "rdi", base: "rbp", disp: -344},
      {op: "cmp", dst: "rdi", imm: 0},
      {op: "j", cond: "l", label: "rt_xc_in_closed"},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "label", name: "rt_xc_in_closed"},
      {op: "mov", dst: "rcx", imm: 2},
      {op: "store", src: "rcx", base: "rbp", disp: -192},
      {op: "label", name: "rt_xc_poll"},
      {op: "load", dst: "rcx", base: "rbp", disp: -192},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_xc_read"}
    ],
    poll_word(-96, -432, 1),
    poll_word(-112, -424, 1),
    poll_word(-352, -416, 4),
    [],
    exec_poll_until,
    drain_ready(-432, -96, -128, -136),
    drain_ready(-424, -112, -144, -152),
    feed_ready(-416),
    [
      {op: "jmp", label: "rt_xc_poll"},
      {op: "label", name: "rt_xc_read"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "r14", disp: EXEC_MS_AT},
      {op: "load", dst: "rdi", base: "rbp", disp: -352},
      {op: "cmp", dst: "rdi", imm: 0},
      {op: "j", cond: "l", label: "rt_xc_in_done"},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "label", name: "rt_xc_in_done"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -168},
      {op: "load", dst: "rdi", base: "rbp", disp: -160},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -168},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "mov", dst: "r10", imm: 0},
      {op: "mov", dst: "rax", imm: 61},
      {op: "syscall"},
      {op: "load", dst: "rax", base: "rbp", disp: -168}
    ],
    map((_k) -> {op: "shr1", dst: "rax"}, range(0, 8)),
    [
      {op: "and", dst: "rax", imm: 255},
      {op: "add", dst: "rax", src: "rax"},
      {op: "add", dst: "rax", imm: 1},
      {op: "store", src: "rax", base: "rbp", disp: -200}
    ],
    exec_status_when_timed,
    string_from_buffer(-128, -136, -248, "rt_xc_out"),
    string_from_buffer(-144, -152, -256, "rt_xc_err"),
    flat_map(
      [-128, -144],
      fn(slot)
        [
          {op: "load", dst: "rdi", base: "rbp", disp: slot},
          {op: "mov", dst: "rsi", imm: CAPTURE_BYTES},
          {op: "mov", dst: "rax", imm: 11},
          {op: "syscall"}
        ]
      end
    ),
    cell(-256, 0, -208),
    cell(-72, -208, -216),
    cell(-248, 0, -208),
    cell(-64, -208, -224),
    cell(-200, 0, -208),
    cell(-56, -208, -232),
    cell(-216, 0, -240),
    cell(-224, -240, -240),
    cell(-232, -240, -240),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rdi", base: "rbp", disp: -264},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rdi", base: "rbp", disp: -328},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rax", base: "rbp", disp: -240},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
capture_programs: programs over exec_capture, with the exit status and output each must give: a command's status, stdout and stderr read back from its answer.

    length(capture_programs) #=> 3
"""
def capture_programs()
  [
    [
      "(let ((r (exec_capture \"sh\" \"-c\" \"echo out; echo err 1>&2; exit 4\"))) (begin (write_stdout (first (rest (first (rest r))))) (write_stdout (first (rest (first (rest (rest r)))))) (first (rest (first r)))))",
      4,
      unlines(%w[out err])
    ],
    [
      "(let ((r (exec_capture \"echo\" \"hi\"))) (if (equal? (first (first r)) :status) (first (rest (first r))) 9))",
      0,
      ""
    ],
    [
      "(let ((r (exec_capture \"sh\" \"-c\" \"head -c 200000 /dev/zero 1>&2; echo done\"))) (begin (write_stdout (first (rest (first (rest r))))) (if (equal? (string_length (first (rest (first (rest (rest r)))))) 200000) 0 1)))",
      0,
      unlines(["done"])
    ]
  ]
end

test "exec_capture captures a command natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-capture"), "capture.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_whole(read_forms(p[0])[0], :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      capture_programs
    )
  end
end

test "exec_capture pipes, polls, waits and builds its answer from cells"
  for_each = %i[status stdout stderr]
  assert take_n(with_runtime_keywords([:status]), 3) == for_each
  assert with_capture_keywords([:status]) == for_each
  assert member?({op: "mov", dst: "rax", imm: 22}, RT_EXEC_CAPTURE)
  assert member?({op: "mov", dst: "rax", imm: 33}, RT_EXEC_CAPTURE)
  assert member?({op: "mov", dst: "rax", imm: 7}, RT_EXEC_CAPTURE)
  assert CAPTURE_KEYWORDS == for_each
  assert length(split_fds(-80, -96, -104)) > 32
  assert last(poll_word(-96, -184, 1))[:disp] == -184
  assert length(drain_ready(-184, -96, -128, -136)) > 48
  assert last(string_from_buffer(-128, -136, -248, "t"))[:disp] == -248
  assert last(cell(-56, 0, -208))[:disp] == -208
  assert last(rc_op([], "exec_capture", ["c"])) ==
    {op: "call_label", label: "rt_exec_capture"}
  stand_ins = [
    {op: "label", name: "rt_alloc"},
    {op: "ret"},
    {op: "label", name: "rt_drop"},
    {op: "ret"}
  ]
  assert length(assemble(append(RT_EXEC_CAPTURE, stand_ins))) > 0
end

test "the clock and process helpers each do their one part"
  assert member?({op: "mov", dst: "rax", imm: 228}, clock_read)
  assert nanos_in_rax[0] == {op: "mov", dst: "rdx", imm: 1_000_000_000}
  assert last(tag_rax) == {op: "add", dst: "rax", imm: 1}
  assert argv_on_stack("t")[0] == {op: "mov", dst: "r10", imm: 0}
  assert PATH_PREFIX_MASK == 1_099_511_627_775
  assert member?(
    {op: "movabs", dst: "rcx", imm: PATH_PREFIX_MASK},
    exec_child("t", -64)
  )
  assert last(exec_child("t", -64)) == {op: "syscall"}
  assert CAPTURE_BYTES == 268_435_456
end

@doc """
env_programs: programs over exec_with_env, with the exit status and output each must give: an extra variable the command sees, one that wins over the same name inherited, and the inherited PATH still found.

    length(env_programs) #=> 2
"""
def env_programs()
  [
    [
      "(let ((r (exec_with_env (list (list \"BLUE_X\" \"hello\")) \"sh\" \"-c\" \"echo $BLUE_X\"))) (begin (write_stdout (first (rest (first (rest r))))) (first (rest (first r)))))",
      0,
      unlines(["hello"])
    ],
    [
      "(let ((r (exec_with_env (list (list \"HOME\" \"/nowhere\") (list \"B\" \"2\")) \"sh\" \"-c\" \"echo $HOME $B; exit 5\"))) (begin (write_stdout (first (rest (first (rest r))))) (first (rest (first r)))))",
      5,
      unlines(["/nowhere 2"])
    ]
  ]
end

test "exec_with_env adds variables natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-env"), "env.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_whole(read_forms(p[0])[0], :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      env_programs
    )
  end
end

test "exec_with_env passes its list to rt_exec_capture, which builds the environment from it"
  assert last(rc_op(["e"], "exec_with_env", [read_forms("e")[0], "c"])) ==
    {op: "call_label", label: "rt_exec_capture"}
  assert member?(
    {op: "mov", dst: "r8", imm: 0},
    rc_op([], "exec_capture", ["c"])
  )
  assert envp_with(-264, -272, "t")[0] ==
    {op: "load", dst: "r9", base: "rbp", disp: -264}
  assert member?({op: "mov", dst: "rcx", imm: 61}, envp_with(-264, -272, "t"))
end

@doc """
stdin_programs: programs over exec_with_stdin, with the exit status and output each must give: the input echoed by cat, an input larger than a pipe holds echoed whole while it is still being written, and a child that exits without reading.

    length(stdin_programs) #=> 3
"""
def stdin_programs()
  [
    [
      "(let ((r (exec_with_stdin \"hello\\n\" \"cat\"))) (begin (write_stdout (first (rest (first (rest r))))) (first (rest (first r)))))",
      0,
      unlines(["hello"])
    ],
    [
      "(begin (define (rep n s) (if (equal? n 0) s (rep (- n 1) (concat s s)))) (let ((r (exec_with_stdin (rep 17 \"ab\") \"cat\"))) (if (equal? (string_length (first (rest (first (rest r))))) 262144) 0 1)))",
      0,
      ""
    ],
    [
      "(first (rest (first (exec_with_stdin \"x\" \"sh\" \"-c\" \"exit 3\"))))",
      3,
      ""
    ]
  ]
end

test "exec_with_stdin feeds input natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-stdin"), "stdin.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
        write_bytes(path, compile_whole(read_forms(p[0])[0], :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
      end,
      stdin_programs
    )
  end
end

test "exec_with_stdin passes its input to rt_exec_capture, which pipes it in as the child reads"
  assert last(rc_op(["s"], "exec_with_stdin", [read_forms("s")[0], "c"])) ==
    {op: "call_label", label: "rt_exec_capture"}
  assert sigpipe_to(1)[0] == {op: "mov", dst: "rcx", imm: 1}
  assert stdin_pipe[0] == {op: "mov", dst: "rcx", imm: -1}
  assert length(feed_ready(-416)) > 48
  assert member?({op: "mov", dst: "rdx", imm: PIPE_BUF}, feed_ready(-416))
  assert member?(
    {op: "movabs", dst: "rcx", imm: 17_179_869_184},
    poll_word(-352, -416, 4)
  )
  assert member?({op: "mov", dst: "rax", imm: 13}, RT_EXEC_CAPTURE)
end

@doc """
classify_connect: the instructions that turn a refused connect's -errno in rax into the keyword slot its why names, stored at rbp-128: ECONNREFUSED (111) is :refused, ENETUNREACH (101) and EHOSTUNREACH (113) are :unreachable, any other is :failed.

    length(classify_connect) > 10 #=> true
"""
def classify_connect()
  [
    {op: "load", dst: "rcx", base: "rbp", disp: -72},
    {op: "cmp", dst: "rax", imm: -111},
    {op: "j", cond: "ne", label: "rt_tc_not_refused"},
    {op: "load", dst: "rcx", base: "rbp", disp: -40},
    {op: "label", name: "rt_tc_not_refused"},
    {op: "cmp", dst: "rax", imm: -101},
    {op: "j", cond: "ne", label: "rt_tc_not_net"},
    {op: "load", dst: "rcx", base: "rbp", disp: -56},
    {op: "label", name: "rt_tc_not_net"},
    {op: "cmp", dst: "rax", imm: -113},
    {op: "j", cond: "ne", label: "rt_tc_not_host"},
    {op: "load", dst: "rcx", base: "rbp", disp: -56},
    {op: "label", name: "rt_tc_not_host"},
    {op: "store", src: "rcx", base: "rbp", disp: -128},
    {op: "jmp", label: "rt_tc_fail"}
  ]
end

@doc """
parse_dotted: the instructions that read the r9 bytes at r8 as a dotted IPv4 address, answering in rax the word that holds its four bytes in network order (a in the low byte), or -1 when they are no such address. r8 and r9 are consumed; labels are named from tag.

    parse_dotted("t")[0] #=> {op: "mov", dst: "rdx", imm: 0}
"""
def parse_dotted(tag)
  append(
    *[
      [
        {op: "mov", dst: "rdx", imm: 0},
        {op: "mov", dst: "r10", imm: 0},
        {op: "mov", dst: "r11", imm: 0},
        {op: "label", name: "#{tag}_char"},
        {op: "cmp", dst: "r9", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_last"},
        {op: "load_byte", dst: "rax", base: "r8"},
        {op: "cmp", dst: "rax", imm: 46},
        {op: "j", cond: "e", label: "#{tag}_dot"},
        {op: "sub", dst: "rax", imm: 48},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "l", label: "#{tag}_bad"},
        {op: "cmp", dst: "rax", imm: 9},
        {op: "j", cond: "g", label: "#{tag}_bad"},
        {op: "mov", dst: "rcx", imm: 10},
        {op: "imul", dst: "rdx", src: "rcx"},
        {op: "add", dst: "rdx", src: "rax"},
        {op: "cmp", dst: "rdx", imm: 255},
        {op: "j", cond: "g", label: "#{tag}_bad"},
        {op: "jmp", label: "#{tag}_next"},
        {op: "label", name: "#{tag}_dot"},
        {op: "cmp", dst: "r10", imm: 3},
        {op: "j", cond: "ge", label: "#{tag}_bad"},
        {op: "mov", dst: "rcx", imm: 256},
        {op: "imul", dst: "r11", src: "rcx"},
        {op: "add", dst: "r11", src: "rdx"},
        {op: "add", dst: "r10", imm: 1},
        {op: "mov", dst: "rdx", imm: 0},
        {op: "label", name: "#{tag}_next"},
        {op: "add", dst: "r8", imm: 1},
        {op: "sub", dst: "r9", imm: 1},
        {op: "jmp", label: "#{tag}_char"},
        {op: "label", name: "#{tag}_last"},
        {op: "cmp", dst: "r10", imm: 3},
        {op: "j", cond: "ne", label: "#{tag}_bad"},
        {op: "mov", dst: "rcx", imm: 256},
        {op: "imul", dst: "r11", src: "rcx"},
        {op: "add", dst: "r11", src: "rdx"},
        {op: "mov", dst: "rax", imm: 0}
      ],
      flat_map(
        range(0, 4),
        fn(_k)
          append(
            [
              {op: "imul", dst: "rax", src: "rcx"},
              {op: "mov", dst: "rdx", src: "r11"},
              {op: "and", dst: "rdx", imm: 255},
              {op: "add", dst: "rax", src: "rdx"}
            ],
            map((_j) -> {op: "shr1", dst: "r11"}, range(0, 8))
          )
        end
      ),
      [
        {op: "jmp", label: "#{tag}_done"},
        {op: "label", name: "#{tag}_bad"},
        {op: "mov", dst: "rax", imm: -1},
        {op: "label", name: "#{tag}_done"}
      ]
    ]
  )
end

@doc """
RT_HOSTS_LOOKUP: the IPv4 address /etc/hosts gives the host string in rdi (borrowed, not consumed), as parse_dotted's word in rax, or -1 when no IPv4 line names it or the file does not open. The file is read with rt_read_file from a path block built on the stack, then each line is read: its first token as a dotted address (other lines, IPv6 ones among them, are passed over), its following tokens compared with the host up to a # or the line's end.

    RT_HOSTS_LOOKUP[0] #=> {op: "label", name: "rt_hosts_lookup"}
"""
RT_HOSTS_LOOKUP = append(
  *[
    [
      {op: "label", name: "rt_hosts_lookup"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 128},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: -1},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -64},
      {op: "movabs", dst: "rcx", imm: IMMORTAL},
      {op: "store", src: "rcx", base: "rbp", disp: -56},
      {op: "mov", dst: "rcx", imm: 6},
      {op: "store", src: "rcx", base: "rbp", disp: -48},
      {op: "mov", dst: "rcx", imm: 10},
      {op: "store", src: "rcx", base: "rbp", disp: -40},
      {op: "movabs", dst: "rcx", imm: text_word("/etc/hos")},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "movabs", dst: "rcx", imm: text_word("ts")},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: -64},
      {op: "call_label", label: "rt_read_file"},
      {op: "store", src: "rax", base: "rbp", disp: -72},
      {op: "load", dst: "rcx", base: "rax", disp: 0},
      {op: "cmp", dst: "rcx", imm: 4},
      {op: "j", cond: "e", label: "rt_hl_out"},
      {op: "mov", dst: "r8", src: "rax"},
      {op: "add", dst: "r8", imm: 32},
      {op: "load", dst: "r9", base: "rax", disp: 24},
      {op: "label", name: "rt_hl_line"},
      {op: "label", name: "rt_hl_lead"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_hl_out"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "e", label: "rt_hl_lead_skip"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "ne", label: "rt_hl_first"},
      {op: "label", name: "rt_hl_lead_skip"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_hl_lead"},
      {op: "label", name: "rt_hl_first"},
      {op: "mov", dst: "r10", src: "r8"},
      {op: "label", name: "rt_hl_first_byte"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_hl_first_end"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "e", label: "rt_hl_first_end"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "e", label: "rt_hl_first_end"},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_hl_first_end"},
      {op: "cmp", dst: "rax", imm: 35},
      {op: "j", cond: "e", label: "rt_hl_first_end"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_hl_first_byte"},
      {op: "label", name: "rt_hl_first_end"},
      {op: "store", src: "r8", base: "rbp", disp: -80},
      {op: "store", src: "r9", base: "rbp", disp: -88},
      {op: "mov", dst: "r9", src: "r8"},
      {op: "sub", dst: "r9", src: "r10"},
      {op: "mov", dst: "r8", src: "r10"}
    ],
    parse_dotted("rt_hl_ip"),
    [
      {op: "store", src: "rax", base: "rbp", disp: -96},
      {op: "load", dst: "r8", base: "rbp", disp: -80},
      {op: "load", dst: "r9", base: "rbp", disp: -88},
      {op: "cmp", dst: "rax", imm: -1},
      {op: "j", cond: "e", label: "rt_hl_skip_line"},
      {op: "label", name: "rt_hl_name"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_hl_out"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_hl_skip_line"},
      {op: "cmp", dst: "rax", imm: 35},
      {op: "j", cond: "e", label: "rt_hl_skip_line"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "e", label: "rt_hl_name_skip"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "ne", label: "rt_hl_token"},
      {op: "label", name: "rt_hl_name_skip"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_hl_name"},
      {op: "label", name: "rt_hl_token"},
      {op: "load", dst: "rsi", base: "rbp", disp: -8},
      {op: "load", dst: "r11", base: "rsi", disp: 24},
      {op: "add", dst: "rsi", imm: 32},
      {op: "mov", dst: "r10", imm: 0},
      {op: "label", name: "rt_hl_cmp"},
      {op: "cmp", dst: "r10", src: "r11"},
      {op: "j", cond: "e", label: "rt_hl_cmp_end"},
      {op: "cmp", dst: "r10", src: "r9"},
      {op: "j", cond: "ge", label: "rt_hl_mismatch"},
      {op: "mov", dst: "rax", src: "r8"},
      {op: "add", dst: "rax", src: "r10"},
      {op: "load_byte", dst: "rax", base: "rax"},
      {op: "mov", dst: "rcx", src: "rsi"},
      {op: "add", dst: "rcx", src: "r10"},
      {op: "load_byte", dst: "rcx", base: "rcx"},
      {op: "cmp", dst: "rax", src: "rcx"},
      {op: "j", cond: "ne", label: "rt_hl_mismatch"},
      {op: "add", dst: "r10", imm: 1},
      {op: "jmp", label: "rt_hl_cmp"},
      {op: "label", name: "rt_hl_cmp_end"},
      {op: "cmp", dst: "r10", src: "r9"},
      {op: "j", cond: "e", label: "rt_hl_found"},
      {op: "mov", dst: "rax", src: "r8"},
      {op: "add", dst: "rax", src: "r10"},
      {op: "load_byte", dst: "rax", base: "rax"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "e", label: "rt_hl_found"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "e", label: "rt_hl_found"},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_hl_found"},
      {op: "cmp", dst: "rax", imm: 35},
      {op: "j", cond: "e", label: "rt_hl_found"},
      {op: "label", name: "rt_hl_mismatch"},
      {op: "label", name: "rt_hl_token_skip"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_hl_out"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "e", label: "rt_hl_name"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "e", label: "rt_hl_name"},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_hl_name"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_hl_token_skip"},
      {op: "label", name: "rt_hl_found"},
      {op: "load", dst: "rcx", base: "rbp", disp: -96},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "jmp", label: "rt_hl_out"},
      {op: "label", name: "rt_hl_skip_line"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_hl_out"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_hl_line"},
      {op: "jmp", label: "rt_hl_skip_line"},
      {op: "label", name: "rt_hl_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -72},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rax", base: "rbp", disp: -16},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
skip_dns_name: the instructions that move r8 past one DNS name (labels, or a pointer) in a message ending at r9, jumping to fail when the name runs past the end.

    skip_dns_name("t", "bad")[0] #=> {op: "label", name: "t_label"}
"""
def skip_dns_name(tag, fail)
  [
    {op: "label", name: "#{tag}_label"},
    {op: "cmp", dst: "r8", src: "r9"},
    {op: "j", cond: "ge", label: fail},
    {op: "load_byte", dst: "rax", base: "r8"},
    {op: "cmp", dst: "rax", imm: 0},
    {op: "j", cond: "e", label: "#{tag}_root"},
    {op: "cmp", dst: "rax", imm: 192},
    {op: "j", cond: "ge", label: "#{tag}_pointer"},
    {op: "add", dst: "r8", src: "rax"},
    {op: "add", dst: "r8", imm: 1},
    {op: "jmp", label: "#{tag}_label"},
    {op: "label", name: "#{tag}_pointer"},
    {op: "add", dst: "r8", imm: 1},
    {op: "label", name: "#{tag}_root"},
    {op: "add", dst: "r8", imm: 1}
  ]
end

@doc """
dns_pair: the instructions that read the two bytes at r8+at as a big-endian number into dst.

    length(dns_pair("rdx", 0)) #=> 9
"""
def dns_pair(dst, at)
  [
    {op: "mov", dst: "rcx", src: "r8"},
    {op: "add", dst: "rcx", imm: at},
    {op: "load_byte", dst:, base: "rcx"},
    {op: "mov", dst: "r11", imm: 256},
    {op: "imul", dst:, src: "r11"},
    {op: "mov", dst: "rcx", src: "r8"},
    {op: "add", dst: "rcx", imm: at + 1},
    {op: "load_byte", dst: "rcx", base: "rcx"},
    {op: "add", dst:, src: "rcx"}
  ]
end

@doc """
DNS_QUERY: where rt_dns_lookup's frame holds the question it sends, 512 bytes up from rbp-600.

    DNS_QUERY #=> -600
"""
DNS_QUERY = -600

@doc """
DNS_ANSWER: where rt_dns_lookup's frame holds the answer it reads, 512 bytes up from rbp-1200 (first, the resolv.conf path block).

    DNS_ANSWER #=> -1200
"""
DNS_ANSWER = -1200

@doc """
RT_DNS_LOOKUP: the IPv4 address a DNS server gives the host string in rdi (borrowed, not consumed), as parse_dotted's word in rax, or -1. The server is the first IPv4 nameserver line of /etc/resolv.conf (read with rt_read_file); one A question goes to it over UDP port 53 on a connected socket, the answer is awaited up to 1500 ms with poll, and its first A record of four bytes is the address. No resolv.conf, no nameserver, a name with an empty or long label, no answer in time, a failing code or no A record each answer -1.

    RT_DNS_LOOKUP[0] #=> {op: "label", name: "rt_dns_lookup"}
"""
RT_DNS_LOOKUP = append(
  *[
    [
      {op: "label", name: "rt_dns_lookup"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 1216},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: -1},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "store", src: "rcx", base: "rbp", disp: -40},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_ANSWER},
      {op: "movabs", dst: "rcx", imm: IMMORTAL},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_ANSWER + 8},
      {op: "mov", dst: "rcx", imm: 6},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_ANSWER + 16},
      {op: "mov", dst: "rcx", imm: 16},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_ANSWER + 24},
      {op: "movabs", dst: "rcx", imm: text_word("/etc/res")},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_ANSWER + 32},
      {op: "movabs", dst: "rcx", imm: text_word("olv.conf")},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_ANSWER + 40},
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: DNS_ANSWER},
      {op: "call_label", label: "rt_read_file"},
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rax", disp: 0},
      {op: "cmp", dst: "rcx", imm: 4},
      {op: "j", cond: "e", label: "rt_dl_conf_done"},
      {op: "mov", dst: "r8", src: "rax"},
      {op: "add", dst: "r8", imm: 32},
      {op: "load", dst: "r9", base: "rax", disp: 24},
      {op: "label", name: "rt_dl_line"},
      {op: "cmp", dst: "r9", imm: 11},
      {op: "j", cond: "l", label: "rt_dl_conf_done"},
      {op: "load", dst: "rax", base: "r8", disp: 0},
      {op: "movabs", dst: "rcx", imm: text_word("nameserv")},
      {op: "cmp", dst: "rax", src: "rcx"},
      {op: "j", cond: "ne", label: "rt_dl_skip_line"},
      {op: "mov", dst: "rcx", src: "r8"},
      {op: "add", dst: "rcx", imm: 8},
      {op: "load_byte", dst: "rax", base: "rcx"},
      {op: "cmp", dst: "rax", imm: 101},
      {op: "j", cond: "ne", label: "rt_dl_skip_line"},
      {op: "mov", dst: "rcx", src: "r8"},
      {op: "add", dst: "rcx", imm: 9},
      {op: "load_byte", dst: "rax", base: "rcx"},
      {op: "cmp", dst: "rax", imm: 114},
      {op: "j", cond: "ne", label: "rt_dl_skip_line"},
      {op: "add", dst: "r8", imm: 10},
      {op: "sub", dst: "r9", imm: 10},
      {op: "label", name: "rt_dl_gap"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_dl_conf_done"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "e", label: "rt_dl_gap_next"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "ne", label: "rt_dl_server"},
      {op: "label", name: "rt_dl_gap_next"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_dl_gap"},
      {op: "label", name: "rt_dl_server"},
      {op: "mov", dst: "r10", src: "r8"},
      {op: "label", name: "rt_dl_server_byte"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_dl_server_end"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 32},
      {op: "j", cond: "le", label: "rt_dl_server_end"},
      {op: "cmp", dst: "rax", imm: 35},
      {op: "j", cond: "e", label: "rt_dl_server_end"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_dl_server_byte"},
      {op: "label", name: "rt_dl_server_end"},
      {op: "store", src: "r8", base: "rbp", disp: -48},
      {op: "store", src: "r9", base: "rbp", disp: -56},
      {op: "mov", dst: "r9", src: "r8"},
      {op: "sub", dst: "r9", src: "r10"},
      {op: "mov", dst: "r8", src: "r10"}
    ],
    parse_dotted("rt_dl_ip"),
    [
      {op: "load", dst: "r8", base: "rbp", disp: -48},
      {op: "load", dst: "r9", base: "rbp", disp: -56},
      {op: "cmp", dst: "rax", imm: -1},
      {op: "j", cond: "e", label: "rt_dl_skip_line"},
      {op: "store", src: "rax", base: "rbp", disp: -32},
      {op: "jmp", label: "rt_dl_conf_done"},
      {op: "label", name: "rt_dl_skip_line"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_dl_conf_done"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_dl_line"},
      {op: "jmp", label: "rt_dl_skip_line"},
      {op: "label", name: "rt_dl_conf_done"},
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "cmp", dst: "rcx", imm: -1},
      {op: "j", cond: "e", label: "rt_dl_out"},
      {op: "load", dst: "rsi", base: "rbp", disp: -8},
      {op: "load", dst: "r9", base: "rsi", disp: 24},
      {op: "cmp", dst: "r9", imm: 1},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "cmp", dst: "r9", imm: 253},
      {op: "j", cond: "g", label: "rt_dl_out"},
      {op: "mov", dst: "r8", src: "rsi"},
      {op: "add", dst: "r8", imm: 32},
      {op: "movabs", dst: "rcx", imm: 1_099_511_710_274},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_QUERY},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: DNS_QUERY + 8},
      {op: "mov", dst: "r11", src: "rbp"},
      {op: "add", dst: "r11", imm: DNS_QUERY + 12},
      {op: "mov", dst: "r10", src: "r11"},
      {op: "add", dst: "r10", imm: 1},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "label", name: "rt_dl_q_byte"},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_dl_q_end"},
      {op: "load_byte", dst: "rax", base: "r8"},
      {op: "cmp", dst: "rax", imm: 46},
      {op: "j", cond: "e", label: "rt_dl_q_dot"},
      {op: "store_byte", src: "rax", base: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "add", dst: "rdx", imm: 1},
      {op: "jmp", label: "rt_dl_q_next"},
      {op: "label", name: "rt_dl_q_dot"},
      {op: "cmp", dst: "rdx", imm: 1},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "cmp", dst: "rdx", imm: 63},
      {op: "j", cond: "g", label: "rt_dl_out"},
      {op: "store_byte", src: "rdx", base: "r11"},
      {op: "mov", dst: "r11", src: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "label", name: "rt_dl_q_next"},
      {op: "add", dst: "r8", imm: 1},
      {op: "sub", dst: "r9", imm: 1},
      {op: "jmp", label: "rt_dl_q_byte"},
      {op: "label", name: "rt_dl_q_end"},
      {op: "cmp", dst: "rdx", imm: 1},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "cmp", dst: "rdx", imm: 63},
      {op: "j", cond: "g", label: "rt_dl_out"},
      {op: "store_byte", src: "rdx", base: "r11"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store_byte", src: "rcx", base: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "store_byte", src: "rcx", base: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store_byte", src: "rcx", base: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store_byte", src: "rcx", base: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store_byte", src: "rcx", base: "r10"},
      {op: "add", dst: "r10", imm: 1},
      {op: "mov", dst: "rcx", src: "rbp"},
      {op: "add", dst: "rcx", imm: DNS_QUERY},
      {op: "sub", dst: "r10", src: "rcx"},
      {op: "store", src: "r10", base: "rbp", disp: -48},
      {op: "mov", dst: "rdi", imm: 2},
      {op: "mov", dst: "rsi", imm: 526_338},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "mov", dst: "rax", imm: 41},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "store", src: "rax", base: "rbp", disp: -40},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "movabs", dst: "rdx", imm: 4_294_967_296},
      {op: "imul", dst: "rcx", src: "rdx"},
      {op: "movabs", dst: "rdx", imm: 13568 * 65536 + 2},
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "store", src: "rcx", base: "rbp", disp: -72},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -64},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -72},
      {op: "mov", dst: "rdx", imm: 16},
      {op: "mov", dst: "rax", imm: 42},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_dl_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: DNS_QUERY},
      {op: "load", dst: "rdx", base: "rbp", disp: -48},
      {op: "mov", dst: "rax", imm: 1},
      {op: "syscall"},
      {op: "load", dst: "rcx", base: "rbp", disp: -48},
      {op: "cmp", dst: "rax", src: "rcx"},
      {op: "j", cond: "ne", label: "rt_dl_out"},
      {op: "load", dst: "rcx", base: "rbp", disp: -40},
      {op: "movabs", dst: "rdx", imm: 4_294_967_296},
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "store", src: "rcx", base: "rbp", disp: -80},
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: -80},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "mov", dst: "rdx", imm: 1500},
      {op: "mov", dst: "rax", imm: 7},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 1},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: DNS_ANSWER},
      {op: "mov", dst: "rdx", imm: 512},
      {op: "mov", dst: "rax", imm: 0},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 12},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "mov", dst: "r8", src: "rbp"},
      {op: "add", dst: "r8", imm: DNS_ANSWER},
      {op: "mov", dst: "r9", src: "r8"},
      {op: "add", dst: "r9", src: "rax"}
    ],
    dns_pair("rdx", 0),
    [
      {op: "cmp", dst: "rdx", imm: 16962},
      {op: "j", cond: "ne", label: "rt_dl_out"}
    ],
    dns_pair("rdx", 2),
    [
      {op: "and", dst: "rdx", imm: 15},
      {op: "cmp", dst: "rdx", imm: 0},
      {op: "j", cond: "ne", label: "rt_dl_out"}
    ],
    dns_pair("rdx", 6),
    [
      {op: "store", src: "rdx", base: "rbp", disp: -88},
      {op: "add", dst: "r8", imm: 12}
    ],
    skip_dns_name("rt_dl_qn", "rt_dl_out"),
    [
      {op: "add", dst: "r8", imm: 4},
      {op: "label", name: "rt_dl_record"},
      {op: "load", dst: "rcx", base: "rbp", disp: -88},
      {op: "cmp", dst: "rcx", imm: 1},
      {op: "j", cond: "l", label: "rt_dl_out"},
      {op: "sub", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -88}
    ],
    skip_dns_name("rt_dl_an", "rt_dl_out"),
    [
      {op: "mov", dst: "rcx", src: "r8"},
      {op: "add", dst: "rcx", imm: 10},
      {op: "cmp", dst: "rcx", src: "r9"},
      {op: "j", cond: "g", label: "rt_dl_out"}
    ],
    dns_pair("rdx", 0),
    dns_pair("r10", 8),
    [
      {op: "add", dst: "r8", imm: 10},
      {op: "mov", dst: "rcx", src: "r8"},
      {op: "add", dst: "rcx", src: "r10"},
      {op: "cmp", dst: "rcx", src: "r9"},
      {op: "j", cond: "g", label: "rt_dl_out"},
      {op: "cmp", dst: "rdx", imm: 1},
      {op: "j", cond: "ne", label: "rt_dl_next_record"},
      {op: "cmp", dst: "r10", imm: 4},
      {op: "j", cond: "ne", label: "rt_dl_next_record"},
      {op: "mov", dst: "rax", imm: 0},
      {op: "mov", dst: "r11", imm: 256}
    ],
    flat_map(
      [3, 2, 1, 0],
      fn(k)
        [
          {op: "imul", dst: "rax", src: "r11"},
          {op: "mov", dst: "rcx", src: "r8"},
          {op: "add", dst: "rcx", imm: k},
          {op: "load_byte", dst: "rcx", base: "rcx"},
          {op: "add", dst: "rax", src: "rcx"}
        ]
      end
    ),
    [
      {op: "store", src: "rax", base: "rbp", disp: -16},
      {op: "jmp", label: "rt_dl_out"},
      {op: "label", name: "rt_dl_next_record"},
      {op: "add", dst: "r8", src: "r10"},
      {op: "jmp", label: "rt_dl_record"},
      {op: "label", name: "rt_dl_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "cmp", dst: "rdi", imm: 0},
      {op: "j", cond: "l", label: "rt_dl_closed"},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "label", name: "rt_dl_closed"},
      {op: "load", dst: "rax", base: "rbp", disp: -16},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
RT_TCP_CONNECT: tcp_connect_ms natively (R4 of docs/PURE-BLUE.md): one TCP connection to the host string in rdi, port in rsi, within the timeout in rdx (milliseconds), closed at once; answered in rax as the milliseconds the handshake took, or [:error, why, host] with why :refused, :timeout, :unreachable, :unresolved or :failed (keywords passed in rcx, r8 to r11 and on the stack). The host is a dotted IPv4 address or a name the system's /etc/hosts gives an IPv4 address (rt_hosts_lookup), else the address a DNS server gives it (rt_dns_lookup); a name neither gives answers :unresolved. A port outside 1..65535 or a negative timeout is refused as an error, as the reference raises. The connect is non-blocking, waited for by poll, and judged by SO_ERROR.

    RT_TCP_CONNECT[0] #=> {op: "label", name: "rt_tcp_connect"}
"""
RT_TCP_CONNECT = append(
  *[
    [
      {op: "label", name: "rt_tcp_connect"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 192},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -16},
      {op: "store", src: "rdx", base: "rbp", disp: -24},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "store", src: "r8", base: "rbp", disp: -40},
      {op: "store", src: "r9", base: "rbp", disp: -48},
      {op: "store", src: "r10", base: "rbp", disp: -56},
      {op: "store", src: "r11", base: "rbp", disp: -64},
      {op: "load", dst: "rcx", base: "rbp", disp: 16},
      {op: "store", src: "rcx", base: "rbp", disp: -72},
      {op: "mov", dst: "rcx", imm: -1},
      {op: "store", src: "rcx", base: "rbp", disp: -80},
      {op: "load", dst: "rax", base: "rbp", disp: -16},
      {op: "sar1", dst: "rax"},
      {op: "cmp", dst: "rax", imm: 1},
      {op: "j", cond: "l", label: "rt_tc_bad"},
      {op: "cmp", dst: "rax", imm: 65535},
      {op: "j", cond: "g", label: "rt_tc_bad"},
      {op: "load", dst: "rcx", base: "rbp", disp: -24},
      {op: "sar1", dst: "rcx"},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "l", label: "rt_tc_bad"},
      {op: "mov", dst: "rcx", src: "rax"},
      {op: "and", dst: "rcx", imm: 255},
      {op: "mov", dst: "rdx", imm: 256},
      {op: "imul", dst: "rcx", src: "rdx"}
    ],
    map((_k) -> {op: "shr1", dst: "rax"}, range(0, 8)),
    [
      {op: "add", dst: "rcx", src: "rax"},
      {op: "mov", dst: "rdx", imm: 65536},
      {op: "imul", dst: "rcx", src: "rdx"},
      {op: "add", dst: "rcx", imm: 2},
      {op: "store", src: "rcx", base: "rbp", disp: -96},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -104},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_resolve"},
      {op: "cmp", dst: "rax", imm: -1},
      {op: "j", cond: "e", label: "rt_tc_unresolved"},
      {op: "movabs", dst: "rcx", imm: 4_294_967_296},
      {op: "imul", dst: "rax", src: "rcx"},
      {op: "load", dst: "rcx", base: "rbp", disp: -96},
      {op: "add", dst: "rcx", src: "rax"},
      {op: "store", src: "rcx", base: "rbp", disp: -96},
      {op: "mov", dst: "rdi", imm: 2},
      {op: "mov", dst: "rsi", imm: 2049},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "mov", dst: "rax", imm: 41},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_tc_failed"},
      {op: "store", src: "rax", base: "rbp", disp: -80}
    ],
    clock_read,
    nanos_in_rax,
    [
      {op: "store", src: "rax", base: "rbp", disp: -88},
      {op: "load", dst: "rdi", base: "rbp", disp: -80},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -96},
      {op: "mov", dst: "rdx", imm: 16},
      {op: "mov", dst: "rax", imm: 42},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_tc_connected"},
      {op: "cmp", dst: "rax", imm: -115},
      {op: "j", cond: "ne", label: "rt_tc_classify"},
      {op: "load", dst: "rcx", base: "rbp", disp: -80},
      {op: "movabs", dst: "rdx", imm: 4 * 4_294_967_296},
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "store", src: "rcx", base: "rbp", disp: -136},
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: -136},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "load", dst: "rdx", base: "rbp", disp: -24},
      {op: "sar1", dst: "rdx"},
      {op: "mov", dst: "rax", imm: 7},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "g", label: "rt_tc_polled"},
      {op: "load", dst: "rcx", base: "rbp", disp: -48},
      {op: "store", src: "rcx", base: "rbp", disp: -128},
      {op: "jmp", label: "rt_tc_fail"},
      {op: "label", name: "rt_tc_polled"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -112},
      {op: "mov", dst: "rcx", imm: 4},
      {op: "store", src: "rcx", base: "rbp", disp: -120},
      {op: "load", dst: "rdi", base: "rbp", disp: -80},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "mov", dst: "rdx", imm: 4},
      {op: "mov", dst: "r10", src: "rbp"},
      {op: "add", dst: "r10", imm: -112},
      {op: "mov", dst: "r8", src: "rbp"},
      {op: "add", dst: "r8", imm: -120},
      {op: "mov", dst: "rax", imm: 55},
      {op: "syscall"},
      {op: "load", dst: "rcx", base: "rbp", disp: -112},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_tc_connected"},
      {op: "mov", dst: "rax", imm: 0},
      {op: "sub", dst: "rax", src: "rcx"},
      {op: "label", name: "rt_tc_classify"}
    ],
    classify_connect,
    [
      {op: "label", name: "rt_tc_connected"},
      {op: "load", dst: "rdi", base: "rbp", disp: -80},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"}
    ],
    clock_read,
    nanos_in_rax,
    [
      {op: "load", dst: "rcx", base: "rbp", disp: -88},
      {op: "sub", dst: "rax", src: "rcx"},
      {op: "cqo"},
      {op: "mov", dst: "r9", imm: 1_000_000},
      {op: "idiv", src: "r9"}
    ],
    tag_rax,
    [
      {op: "store", src: "rax", base: "rbp", disp: -160},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_drop"},
      {op: "jmp", label: "rt_tc_out"},
      {op: "label", name: "rt_tc_unresolved"},
      {op: "load", dst: "rcx", base: "rbp", disp: -64},
      {op: "store", src: "rcx", base: "rbp", disp: -128},
      {op: "jmp", label: "rt_tc_fail"},
      {op: "label", name: "rt_tc_failed"},
      {op: "load", dst: "rcx", base: "rbp", disp: -72},
      {op: "store", src: "rcx", base: "rbp", disp: -128},
      {op: "label", name: "rt_tc_fail"},
      {op: "load", dst: "rdi", base: "rbp", disp: -80},
      {op: "cmp", dst: "rdi", imm: 0},
      {op: "j", cond: "l", label: "rt_tc_unopened"},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "label", name: "rt_tc_unopened"}
    ],
    cell(-8, 0, -168),
    cell(-128, -168, -176),
    cell(-32, -176, -160),
    [
      {op: "jmp", label: "rt_tc_out"},
      {op: "label", name: "rt_tc_bad"},
      {op: "mov", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "mov", dst: "rcx", imm: 4},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "store", src: "rcx", base: "rax", disp: 24},
      {op: "store", src: "rax", base: "rbp", disp: -160},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_drop"},
      {op: "label", name: "rt_tc_out"},
      {op: "load", dst: "rax", base: "rbp", disp: -160},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
tcp_programs: programs over tcp_connect_ms, with the exit status each must give: a refused port answers [:error, :refused, …], a name native code cannot resolve answers :unresolved, a bad port is refused as an error, and a listening port answers a time, by an /etc/hosts name and by a name only DNS gives.

    length(tcp_programs) #=> 5
"""
def tcp_programs()
  [
    [
      "(if (equal? (first (rest (tcp_connect_ms \"127.0.0.1\" 1 500))) :refused) 0 1)",
      0
    ],
    [
      "(if (equal? (first (rest (tcp_connect_ms \"example.invalid\" 80 500))) :unresolved) 0 1)",
      0
    ],
    ["(try (tcp_connect_ms \"127.0.0.1\" 0 500) (catch (e) 7))", 7],
    ["(if (< (tcp_connect_ms \"localhost\" 22 2000) 2000) 0 1)", 0],
    ["(if (< (tcp_connect_ms \"dns.google\" 443 3000) 3000) 0 1)", 0]
  ]
end

test "tcp_connect_ms connects, times and refuses natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem network process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-tcp"), "tcp.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      take_n(tcp_programs, 3)
    )
  end
end

test "tcp_connect_ms passes its keywords to rt_tcp_connect, which polls a non-blocking connect"
  assert last(rc_op([], "tcp_connect_ms", ["h", 1, 500])) ==
    {op: "pop", dst: "rcx"}
  assert member?({op: "mov", dst: "rax", imm: 42}, RT_TCP_CONNECT)
  assert member?({op: "mov", dst: "rax", imm: 55}, RT_TCP_CONNECT)
  assert length(classify_connect) > 10
  assert NETWORK_KEYWORDS[0] == :error
  assert length(RUNTIME_KEYWORDS) == 13
  stand_ins = [
    {op: "label", name: "rt_alloc"},
    {op: "ret"},
    {op: "label", name: "rt_drop"},
    {op: "ret"},
    {op: "label", name: "rt_hosts_lookup"},
    {op: "ret"},
    {op: "label", name: "rt_read_file"},
    {op: "ret"},
    {op: "label", name: "rt_dns_lookup"},
    {op: "ret"},
    {op: "label", name: "rt_resolve"},
    {op: "ret"}
  ]
  assert length(assemble(append(RT_TCP_CONNECT, stand_ins))) > 0
  assert length(assemble(append(RT_HOSTS_LOOKUP, stand_ins))) > 0
  assert length(assemble(append(RT_DNS_LOOKUP, stand_ins))) > 0
  assert skip_dns_name("t", "bad")[0] == {op: "label", name: "t_label"}
  assert length(dns_pair("rdx", 0)) == 9
  assert DNS_QUERY - DNS_ANSWER == 600
  assert parse_dotted("t")[0] == {op: "mov", dst: "rdx", imm: 0}
end

@doc """
IS_TERMINAL: is_terminal natively (R4 of docs/PURE-BLUE.md), a routine so every call site shares its one label: whether the stream whose tagged number is in rdi (0 input, 1 output, 2 errors) is a terminal, as true (2) or false (0) in rax: TCGETS (ioctl 16, request 0x5401) succeeds on a terminal and on nothing else; any other number is false.

    IS_TERMINAL[0] #=> {op: "label", name: "rt_is_terminal"}
"""
IS_TERMINAL = [
  {op: "label", name: "rt_is_terminal"},
  {op: "sar1", dst: "rdi"},
  {op: "mov", dst: "rax", imm: 0},
  {op: "cmp", dst: "rdi", imm: 0},
  {op: "j", cond: "l", label: "rt_tty_no"},
  {op: "cmp", dst: "rdi", imm: 2},
  {op: "j", cond: "g", label: "rt_tty_no"},
  {op: "sub", dst: "rsp", imm: 64},
  {op: "mov", dst: "rdx", src: "rsp"},
  {op: "mov", dst: "rsi", imm: 21505},
  {op: "mov", dst: "rax", imm: 16},
  {op: "syscall"},
  {op: "add", dst: "rsp", imm: 64},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "mov", dst: "rax", imm: 0},
  {op: "j", cond: "ne", label: "rt_tty_no"},
  {op: "mov", dst: "rax", imm: 2},
  {op: "label", name: "rt_tty_no"},
  {op: "ret"}
]

@doc """
RT_READ_LINE: read_line natively (R4 of docs/PURE-BLUE.md): one line of standard input without its line break, as a new string in rax, or nil at the end of input. Bytes are read one at a time into a CAPTURE_BYTES mapping (committed only as written), so nothing past the line is taken from the stream.

    RT_READ_LINE[0] #=> {op: "label", name: "rt_read_line"}
"""
RT_READ_LINE = append(
  *[
    [
      {op: "label", name: "rt_read_line"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 64},
      {op: "mov", dst: "rdi", imm: 0},
      {op: "mov", dst: "rsi", imm: CAPTURE_BYTES},
      {op: "mov", dst: "rdx", imm: 3},
      {op: "mov", dst: "r10", imm: 34},
      {op: "mov", dst: "r8", imm: -1},
      {op: "mov", dst: "r9", imm: 0},
      {op: "mov", dst: "rax", imm: 9},
      {op: "syscall"},
      {op: "store", src: "rax", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "label", name: "rt_rl_byte"},
      {op: "load", dst: "rsi", base: "rbp", disp: -8},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "add", dst: "rsi", src: "rcx"},
      {op: "mov", dst: "rdi", imm: 0},
      {op: "mov", dst: "rdx", imm: 1},
      {op: "mov", dst: "rax", imm: 0},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "le", label: "rt_rl_end"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rsi", base: "rbp", disp: -8},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "add", dst: "rsi", src: "rcx"},
      {op: "load_byte", dst: "rax", base: "rsi"},
      {op: "cmp", dst: "rax", imm: 10},
      {op: "j", cond: "e", label: "rt_rl_line"},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "jmp", label: "rt_rl_byte"},
      {op: "label", name: "rt_rl_end"},
      {op: "load", dst: "rcx", base: "rbp", disp: -24},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "ne", label: "rt_rl_line"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "jmp", label: "rt_rl_unmap"},
      {op: "label", name: "rt_rl_line"}
    ],
    string_from_buffer(-8, -16, -32, "rt_rl_copy"),
    [
      {op: "label", name: "rt_rl_unmap"},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rsi", imm: CAPTURE_BYTES},
      {op: "mov", dst: "rax", imm: 11},
      {op: "syscall"},
      {op: "load", dst: "rax", base: "rbp", disp: -32},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
terminal_programs: programs over the terminal words, with the input each is given and the exit status and output each must give: a line read without its break, a line at the end of input with no break, the end of input as nil, and a stream that is no terminal.

    length(terminal_programs) #=> 4
"""
def terminal_programs()
  [
    ["(begin (write_stdout (read_line)) 0)", unlines(%w[abc def]), 0, "abc"],
    ["(begin (write_stdout (read_line)) 0)", "last", 0, "last"],
    ["(if (equal? (read_line) nil) 0 1)", "", 0, ""],
    ["(if (is_terminal 1) 1 (if (is_terminal 9) 2 0))", "", 0, ""]
  ]
end

test "read_line and is_terminal work natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-tty"), "tty.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_with_stdin(p[1], path)
        assert status_of(r) == p[2]
        assert stdout_of(r) == p[3]
        write_bytes(path, compile_whole(read_forms(p[0])[0], :leaks))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_with_stdin(p[1], path)) == 0
      end,
      terminal_programs
    )
  end
end

test "is_terminal asks TCGETS, and read_line reads a byte at a time into a mapping"
  assert member?({op: "mov", dst: "rsi", imm: 21505}, IS_TERMINAL)
  assert member?(
    {op: "call_label", label: "rt_is_terminal"},
    rc_op([], "is_terminal", [1])
  )
  assert tagged_atom([], read_forms("nil")[0], "rax") ==
    [{op: "mov", dst: "rax", imm: 0}]
  assert tagged_atom([], read_forms("true")[0], "rax") ==
    [{op: "mov", dst: "rax", imm: 2}]
  assert tagged_atom([], read_forms("false")[0], "rax") ==
    [{op: "mov", dst: "rax", imm: FALSE}]
  assert last(rc_op([], "read_line", [])) ==
    {op: "call_label", label: "rt_read_line"}
  assert member?({op: "mov", dst: "rdx", imm: 1}, RT_READ_LINE)
  stand_ins = [{op: "label", name: "rt_alloc"}, {op: "ret"}]
  assert length(assemble(append(RT_READ_LINE, stand_ins))) > 0
  assert length(assemble(append(IS_TERMINAL, []))) > 0
  twice = rc_whole(
    whole(read_forms("(if (is_terminal 1) 1 (if (is_terminal 9) 2 0))")[0]),
    :exit
  )
  assert length(filter((i) -> i == {op: "label", name: "rt_tty_no"}, twice)) ==
    1
end

test "run_status and rc_run run a compiled program and answer a status", {
  allow: %i[filesystem process]
}
  assert integer?(run_status(read_forms("7")[0], compile))
  assert integer?(rc_run(read_forms("7")[0], :exit))
  if linux_x86?
    assert run_status(read_forms("7")[0], compile) == 7
    assert rc_run(read_forms("7")[0], :exit) == 7
  end
end

@doc """
RT_PUT_INT: put_int natively (R4 of docs/PURE-BLUE.md, the word C3's corpus prints with): the tagged number in rdi to standard output in decimal, a minus sign first when it is negative, answered in rax. The digits are built backward in the routine's frame and go out in one write, so nothing is allocated.

    RT_PUT_INT[0] #=> {op: "label", name: "rt_put_int"}
"""
RT_PUT_INT = [
  {op: "label", name: "rt_put_int"},
  {op: "push_rbp"},
  {op: "mov", dst: "rbp", src: "rsp"},
  {op: "sub", dst: "rsp", imm: 48},
  {op: "store", src: "rdi", base: "rbp", disp: -8},
  {op: "mov", dst: "rax", src: "rdi"},
  {op: "sar1", dst: "rax"},
  {op: "mov", dst: "r8", src: "rbp"},
  {op: "add", dst: "r8", imm: -8},
  {op: "mov", dst: "r10", src: "r8"},
  {op: "mov", dst: "r9", imm: 0},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ge", label: "rt_pi_digit"},
  {op: "mov", dst: "r9", imm: 1},
  {op: "mov", dst: "rcx", imm: 0},
  {op: "sub", dst: "rcx", src: "rax"},
  {op: "mov", dst: "rax", src: "rcx"},
  {op: "label", name: "rt_pi_digit"},
  {op: "cqo"},
  {op: "mov", dst: "rcx", imm: 10},
  {op: "idiv", src: "rcx"},
  {op: "add", dst: "rdx", imm: 48},
  {op: "sub", dst: "r10", imm: 1},
  {op: "store_byte", src: "rdx", base: "r10"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ne", label: "rt_pi_digit"},
  {op: "cmp", dst: "r9", imm: 0},
  {op: "j", cond: "e", label: "rt_pi_write"},
  {op: "mov", dst: "rcx", imm: 45},
  {op: "sub", dst: "r10", imm: 1},
  {op: "store_byte", src: "rcx", base: "r10"},
  {op: "label", name: "rt_pi_write"},
  {op: "load", dst: "rdi", base: "r14", disp: SHOW_FD_AT},
  {op: "mov", dst: "rsi", src: "r10"},
  {op: "mov", dst: "rdx", src: "r8"},
  {op: "sub", dst: "rdx", src: "r10"},
  {op: "mov", dst: "rax", imm: 1},
  {op: "syscall"},
  {op: "load", dst: "rax", base: "rbp", disp: -8},
  {op: "mov", dst: "rsp", src: "rbp"},
  {op: "pop_rbp"},
  {op: "ret"}
]

@doc """
RT_PUT_BYTE: put_byte natively: the low byte of the tagged number in rdi to standard output, answered in rax.

    RT_PUT_BYTE[0] #=> {op: "label", name: "rt_put_byte"}
"""
RT_PUT_BYTE = [
  {op: "label", name: "rt_put_byte"},
  {op: "push_rbp"},
  {op: "mov", dst: "rbp", src: "rsp"},
  {op: "sub", dst: "rsp", imm: 16},
  {op: "store", src: "rdi", base: "rbp", disp: -8},
  {op: "mov", dst: "rcx", src: "rdi"},
  {op: "sar1", dst: "rcx"},
  {op: "mov", dst: "rsi", src: "rbp"},
  {op: "add", dst: "rsi", imm: -16},
  {op: "store_byte", src: "rcx", base: "rsi"},
  {op: "load", dst: "rdi", base: "r14", disp: SHOW_FD_AT},
  {op: "mov", dst: "rdx", imm: 1},
  {op: "mov", dst: "rax", imm: 1},
  {op: "syscall"},
  {op: "load", dst: "rax", base: "rbp", disp: -8},
  {op: "mov", dst: "rsp", src: "rbp"},
  {op: "pop_rbp"},
  {op: "ret"}
]

@doc """
RT_MOD: mod natively (blue's `%`, C3's corpus): the tagged number in rdi modulo the one in rsi, euclidean as blue's is (the answer is never negative), tagged in rax. The remainder of idiv takes the dividend's sign, so a negative one has the divisor's magnitude added. A zero divisor faults in idiv: the program dies by a signal, never with a value.

    RT_MOD[0] #=> {op: "label", name: "rt_mod"}
"""
RT_MOD = [
  {op: "label", name: "rt_mod"},
  {op: "mov", dst: "rax", src: "rdi"},
  {op: "sar1", dst: "rax"},
  {op: "mov", dst: "rcx", src: "rsi"},
  {op: "sar1", dst: "rcx"},
  {op: "cqo"},
  {op: "idiv", src: "rcx"},
  {op: "cmp", dst: "rdx", imm: 0},
  {op: "j", cond: "ge", label: "rt_mod_tag"},
  {op: "cmp", dst: "rcx", imm: 0},
  {op: "j", cond: "l", label: "rt_mod_neg"},
  {op: "add", dst: "rdx", src: "rcx"},
  {op: "jmp", label: "rt_mod_tag"},
  {op: "label", name: "rt_mod_neg"},
  {op: "sub", dst: "rdx", src: "rcx"},
  {op: "label", name: "rt_mod_tag"},
  {op: "add", dst: "rdx", src: "rdx"},
  {op: "add", dst: "rdx", imm: 1},
  {op: "mov", dst: "rax", src: "rdx"},
  {op: "ret"}
]

@doc """
mod_programs: programs over mod, with the exit status each must give: blue's euclidean answers for each sign of the dividend and the divisor.

    length(mod_programs) #=> 4
"""
def mod_programs()
  [["(mod 17 5)", 2], ["(mod -7 3)", 2], ["(mod 7 -3)", 1], ["(mod -7 -3)", 2]]
end

test "mod answers as blue's euclidean % does on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-mod"), "mod.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      mod_programs
    )
  end
end

test "a :run program exits 0 whatever its value, as blue run does", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-run"), "run.out")
    write_bytes(
      path,
      compile_whole(read_forms("(begin (put_int 7) 10)")[0], :run)
    )
    exec_capture("chmod", "+x", path)
    r = exec_capture(path)
    assert status_of(r) == 0
    assert stdout_of(r) == "7"
  end
end

test "a :run program drops its value and exits 0"
  tail = rc_gen([], read_forms("(ret 3)")[0], :run, 0)[0]
  assert member?({op: "call_label", label: "rt_drop"}, tail)
  assert member?({op: "mov", dst: "rdi", imm: 0}, tail)
end

test "mod calls its routine, which assembles"
  assert last(rc_op([], "mod", [7, 3])) == {op: "call_label", label: "rt_mod"}
  assert length(assemble(RT_MOD)) > 0
  assert map((p) -> p[1], mod_programs) == [17 % 5, -7 % 3, 7 % -3, -7 % -3]
end

@doc """
output_programs: programs over put_int and put_byte, with the exit status and output each must give: a number and a line break, a negative number, zero, and a value answered back as the status.

    length(output_programs) #=> 4
"""
def output_programs()
  [
    ["(begin (put_int 1234) (put_byte 10) 0)", 0, unlines(["1234"])],
    ["(begin (put_int -56) (put_byte 10) 0)", 0, unlines(["-56"])],
    ["(begin (put_int 0) 0)", 0, "0"],
    ["(put_byte (put_int 65))", 65, "65A"]
  ]
end

test "put_int and put_byte print natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-put"), "put.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == p[1]
        assert stdout_of(r) == p[2]
      end,
      output_programs
    )
  end
end

test "put_int builds its digits in its frame, and put_byte writes one byte"
  assert last(rc_op([], "put_int", [1])) ==
    {op: "call_label", label: "rt_put_int"}
  assert last(rc_op([], "put_byte", [10])) ==
    {op: "call_label", label: "rt_put_byte"}
  assert length(assemble(RT_PUT_INT)) > 0
  assert length(assemble(RT_PUT_BYTE)) > 0
  assert length(output_programs) == 4
end

@doc """
HANDLE_KIND: the block kind of a native socket handle: [kind, count, size 4, the descriptor as a tagged number], -1 once closed. rt_drop passes the descriptor by, as it is no block.

    HANDLE_KIND #=> 6
"""
HANDLE_KIND = 6

@doc """
TCP_OPS: each native TCP word and the routine it calls, its arguments in rdi then rsi.

    TCP_OPS[0] #=> ["tcp_listen", "rt_tcp_listen"]
"""
TCP_OPS = [
  %w[tcp_listen rt_tcp_listen],
  %w[tcp_port rt_tcp_port],
  %w[tcp_accept rt_tcp_accept],
  %w[tcp_connect rt_tcp_open],
  %w[tcp_read rt_tcp_read],
  %w[tcp_write rt_tcp_write],
  %w[tcp_close rt_tcp_close]
]

@doc """
routine_op: the instructions of a word one runtime routine answers (ROUTINE_OPS): its arguments in rdi and rsi, then a call to its routine.

    last(routine_op([], "tcp_port", [1])) #=> {op: "call_label", label: "rt_tcp_port"}
"""
def routine_op(slots, op, args)
  routine = filter((w) -> w[0] == op, ROUTINE_OPS)[0][1]
  append(
    *[
      flat_map(
        range(0, length(args)),
        (i) -> tagged_atom(slots, args[i], %w[rdi rsi][i])
      ),
      if length(args) == 1
        [{op: "mov", dst: "rsi", imm: 0}]
      else
        []
      end,
      [{op: "call_label", label: routine}]
    ]
  )
end

@doc """
new_handle: the instructions that allocate a handle holding the descriptor at rbp+fd, answered in rax.

    new_handle(-40)[0] #=> {op: "mov", dst: "rdi", imm: 4}
"""
def new_handle(fd)
  [
    {op: "mov", dst: "rdi", imm: 4},
    {op: "call_label", label: "rt_alloc"},
    {op: "mov", dst: "rcx", imm: HANDLE_KIND},
    {op: "store", src: "rcx", base: "rax", disp: 0},
    {op: "load", dst: "rcx", base: "rbp", disp: fd},
    {op: "mov", dst: "rdx", src: "rcx"},
    {op: "add", dst: "rcx", src: "rdx"},
    {op: "add", dst: "rcx", imm: 1},
    {op: "store", src: "rcx", base: "rax", disp: 24}
  ]
end

@doc """
error_from: the instructions that make an error block whose payload is the errno whose negation is in src (a refused system call's return), as errno_block carries it, answered in rax.

    error_from("rax")[0] #=> {op: "push", src: "rax"}
"""
def error_from(src)
  [
    {op: "push", src:},
    {op: "mov", dst: "rdi", imm: 4},
    {op: "call_label", label: "rt_alloc"},
    {op: "mov", dst: "rcx", imm: 4},
    {op: "store", src: "rcx", base: "rax", disp: 0},
    {op: "pop", dst: "rcx"},
    {op: "mov", dst: "rdx", src: "rcx"},
    {op: "add", dst: "rcx", src: "rdx"},
    {op: "add", dst: "rcx", imm: 1},
    {op: "store", src: "rcx", base: "rax", disp: 24}
  ]
end

@doc """
close_and_raise: the failure tail of a routine that may have opened the descriptor at rbp+fd: the errno in rax kept at rbp+tmp, the descriptor closed when it was opened, and an error block of the errno stored at rbp+out.

    close_and_raise("t", -40, -56, -48)[0] #=> {op: "label", name: "t_bad"}
"""
def close_and_raise(tag, fd, tmp, out)
  append(
    *[
      [
        {op: "label", name: "#{tag}_bad"},
        {op: "store", src: "rax", base: "rbp", disp: tmp},
        {op: "load", dst: "rdi", base: "rbp", disp: fd},
        {op: "cmp", dst: "rdi", imm: 0},
        {op: "j", cond: "l", label: "#{tag}_unopened"},
        {op: "mov", dst: "rax", imm: 3},
        {op: "syscall"},
        {op: "label", name: "#{tag}_unopened"},
        {op: "load", dst: "rax", base: "rbp", disp: tmp}
      ],
      error_from("rax"),
      [{op: "store", src: "rax", base: "rbp", disp: out}]
    ]
  )
end

@doc """
leave_with: a routine's end: the word at rbp+drop dropped, the word at rbp+answer in rax, the frame gone.

    last(leave_with(-8, -16)) #=> {op: "ret"}
"""
def leave_with(drop, answer)
  [
    {op: "load", dst: "rdi", base: "rbp", disp: drop},
    {op: "call_label", label: "rt_drop"},
    {op: "load", dst: "rax", base: "rbp", disp: answer},
    {op: "mov", dst: "rsp", src: "rbp"},
    {op: "pop_rbp"},
    {op: "ret"}
  ]
end

@doc """
RT_RESOLVE: the IPv4 address of the host string in rdi (borrowed), as parse_dotted's word in rax, or -1: a dotted address, else /etc/hosts (rt_hosts_lookup), else DNS (rt_dns_lookup).

    RT_RESOLVE[0] #=> {op: "label", name: "rt_resolve"}
"""
RT_RESOLVE = append(
  *[
    [
      {op: "label", name: "rt_resolve"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 16},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "r8", src: "rdi"},
      {op: "add", dst: "r8", imm: 32},
      {op: "load", dst: "r9", base: "rdi", disp: 24}
    ],
    parse_dotted("rt_rs_ip"),
    [
      {op: "cmp", dst: "rax", imm: -1},
      {op: "j", cond: "ne", label: "rt_rs_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_hosts_lookup"},
      {op: "cmp", dst: "rax", imm: -1},
      {op: "j", cond: "ne", label: "rt_rs_out"},
      {op: "load", dst: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_dns_lookup"},
      {op: "label", name: "rt_rs_out"},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
RT_SOCKADDR: the IPv4 socket address of the "host:port" string in rdi (borrowed), written as 16 bytes at rsi; rax is 0, or -1 when there is no colon, the port is not 0 to 65535 in digits, or the host does not resolve (rt_resolve, on a string of the host part).

    RT_SOCKADDR[0] #=> {op: "label", name: "rt_sockaddr"}
"""
RT_SOCKADDR = append(
  *[
    [
      {op: "label", name: "rt_sockaddr"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 64},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -16},
      {op: "load", dst: "r9", base: "rdi", disp: 24},
      {op: "mov", dst: "r8", src: "rdi"},
      {op: "add", dst: "r8", imm: 32},
      {op: "mov", dst: "r10", src: "r9"},
      {op: "label", name: "rt_sa_colon"},
      {op: "sub", dst: "r10", imm: 1},
      {op: "cmp", dst: "r10", imm: 0},
      {op: "j", cond: "l", label: "rt_sa_fail"},
      {op: "mov", dst: "rax", src: "r8"},
      {op: "add", dst: "rax", src: "r10"},
      {op: "load_byte", dst: "rax", base: "rax"},
      {op: "cmp", dst: "rax", imm: 58},
      {op: "j", cond: "ne", label: "rt_sa_colon"},
      {op: "store", src: "r10", base: "rbp", disp: -40},
      {op: "store", src: "r8", base: "rbp", disp: -48},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "mov", dst: "r11", src: "r10"},
      {op: "add", dst: "r11", imm: 1},
      {op: "cmp", dst: "r11", src: "r9"},
      {op: "j", cond: "e", label: "rt_sa_fail"},
      {op: "label", name: "rt_sa_digit"},
      {op: "cmp", dst: "r11", src: "r9"},
      {op: "j", cond: "e", label: "rt_sa_port"},
      {op: "mov", dst: "rax", src: "r8"},
      {op: "add", dst: "rax", src: "r11"},
      {op: "load_byte", dst: "rax", base: "rax"},
      {op: "sub", dst: "rax", imm: 48},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_sa_fail"},
      {op: "cmp", dst: "rax", imm: 9},
      {op: "j", cond: "g", label: "rt_sa_fail"},
      {op: "mov", dst: "rcx", imm: 10},
      {op: "imul", dst: "rdx", src: "rcx"},
      {op: "add", dst: "rdx", src: "rax"},
      {op: "cmp", dst: "rdx", imm: 65535},
      {op: "j", cond: "g", label: "rt_sa_fail"},
      {op: "add", dst: "r11", imm: 1},
      {op: "jmp", label: "rt_sa_digit"},
      {op: "label", name: "rt_sa_port"},
      {op: "store", src: "rdx", base: "rbp", disp: -32}
    ],
    string_from_buffer(-48, -40, -24, "rt_sa_copy"),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "call_label", label: "rt_resolve"},
      {op: "store", src: "rax", base: "rbp", disp: -56},
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "call_label", label: "rt_drop"},
      {op: "load", dst: "rax", base: "rbp", disp: -56},
      {op: "cmp", dst: "rax", imm: -1},
      {op: "j", cond: "e", label: "rt_sa_fail"},
      {op: "movabs", dst: "rcx", imm: 4_294_967_296},
      {op: "imul", dst: "rax", src: "rcx"},
      {op: "load", dst: "rdx", base: "rbp", disp: -32},
      {op: "mov", dst: "r10", src: "rdx"},
      {op: "and", dst: "r10", imm: 255},
      {op: "mov", dst: "rcx", imm: 256},
      {op: "imul", dst: "r10", src: "rcx"}
    ],
    map((_k) -> {op: "shr1", dst: "rdx"}, range(0, 8)),
    [
      {op: "add", dst: "r10", src: "rdx"},
      {op: "mov", dst: "rcx", imm: 65536},
      {op: "imul", dst: "r10", src: "rcx"},
      {op: "add", dst: "rax", src: "r10"},
      {op: "add", dst: "rax", imm: 2},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "store", src: "rax", base: "rcx", disp: 0},
      {op: "mov", dst: "rax", imm: 0},
      {op: "store", src: "rax", base: "rcx", disp: 8},
      {op: "jmp", label: "rt_sa_out"},
      {op: "label", name: "rt_sa_fail"},
      {op: "mov", dst: "rax", imm: -1},
      {op: "label", name: "rt_sa_out"},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
socket_open: the instructions that open a non-blocking, close-on-exec IPv4 stream socket and keep it at rbp+fd, jumping to the routine's bad tail (errno in rax) when it cannot.

    last(socket_open("t", -40))[:disp] #=> -40
"""
def socket_open(tag, fd)
  [
    {op: "mov", dst: "rdi", imm: 2},
    {op: "mov", dst: "rsi", imm: 526_337},
    {op: "mov", dst: "rdx", imm: 0},
    {op: "mov", dst: "rax", imm: 41},
    {op: "syscall"},
    {op: "cmp", dst: "rax", imm: 0},
    {op: "j", cond: "l", label: "#{tag}_bad"},
    {op: "store", src: "rax", base: "rbp", disp: fd}
  ]
end

@doc """
RT_TCP_LISTEN: tcp_listen natively (R4 of docs/PURE-BLUE.md): a listening handle bound to the "host:port" string in rdi (consumed; port 0 picks one), with SO_REUSEADDR and a backlog of 128, or an error carrying the negated errno (EINVAL, -22, for an address that does not parse or resolve).

    RT_TCP_LISTEN[0] #=> {op: "label", name: "rt_tcp_listen"}
"""
RT_TCP_LISTEN = append(
  *[
    [
      {op: "label", name: "rt_tcp_listen"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 80},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: -1},
      {op: "store", src: "rcx", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -32},
      {op: "call_label", label: "rt_sockaddr"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_tl_sock"},
      {op: "mov", dst: "rax", imm: -22},
      {op: "jmp", label: "rt_tl_bad"},
      {op: "label", name: "rt_tl_sock"}
    ],
    socket_open("rt_tl", -40),
    [
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -56},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "mov", dst: "rdx", imm: 2},
      {op: "mov", dst: "r10", src: "rbp"},
      {op: "add", dst: "r10", imm: -56},
      {op: "mov", dst: "r8", imm: 4},
      {op: "mov", dst: "rax", imm: 54},
      {op: "syscall"},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -32},
      {op: "mov", dst: "rdx", imm: 16},
      {op: "mov", dst: "rax", imm: 49},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_tl_bad"},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", imm: 128},
      {op: "mov", dst: "rax", imm: 50},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_tl_bad"}
    ],
    new_handle(-40),
    [
      {op: "store", src: "rax", base: "rbp", disp: -48},
      {op: "jmp", label: "rt_tl_out"}
    ],
    close_and_raise("rt_tl", -40, -56, -48),
    [{op: "label", name: "rt_tl_out"}],
    leave_with(-8, -48)
  ]
)

@doc """
RT_TCP_PORT: tcp_port natively: the port the handle in rdi (consumed) is bound to, read with getsockname, as a tagged number; an error (EBADF, -9) for a closed handle.

    RT_TCP_PORT[0] #=> {op: "label", name: "rt_tcp_port"}
"""
RT_TCP_PORT = append(
  *[
    [
      {op: "label", name: "rt_tcp_port"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "load", dst: "rcx", base: "rdi", disp: 24},
      {op: "sar1", dst: "rcx"},
      {op: "mov", dst: "rax", imm: -9},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "l", label: "rt_tp_bad"},
      {op: "mov", dst: "rax", imm: 16},
      {op: "store", src: "rax", base: "rbp", disp: -32},
      {op: "mov", dst: "rdi", src: "rcx"},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -24},
      {op: "mov", dst: "rdx", src: "rbp"},
      {op: "add", dst: "rdx", imm: -32},
      {op: "mov", dst: "rax", imm: 51},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_tp_bad"},
      {op: "mov", dst: "rcx", src: "rbp"},
      {op: "add", dst: "rcx", imm: -22},
      {op: "load_byte", dst: "rax", base: "rcx"},
      {op: "mov", dst: "rdx", imm: 256},
      {op: "imul", dst: "rax", src: "rdx"},
      {op: "mov", dst: "rcx", src: "rbp"},
      {op: "add", dst: "rcx", imm: -21},
      {op: "load_byte", dst: "rcx", base: "rcx"},
      {op: "add", dst: "rax", src: "rcx"},
      {op: "mov", dst: "rcx", src: "rax"},
      {op: "add", dst: "rax", src: "rcx"},
      {op: "add", dst: "rax", imm: 1},
      {op: "store", src: "rax", base: "rbp", disp: -40},
      {op: "jmp", label: "rt_tp_out"},
      {op: "label", name: "rt_tp_bad"}
    ],
    error_from("rax"),
    [
      {op: "store", src: "rax", base: "rbp", disp: -40},
      {op: "label", name: "rt_tp_out"}
    ],
    leave_with(-8, -40)
  ]
)

@doc """
RT_TCP_ACCEPT: tcp_accept natively: the next waiting connection on the listening handle in rdi (consumed) as a new handle, by accept4, non-blocking and close-on-exec; nil when none is waiting or the handle is closed. It never blocks.

    RT_TCP_ACCEPT[0] #=> {op: "label", name: "rt_tcp_accept"}
"""
RT_TCP_ACCEPT = append(
  *[
    [
      {op: "label", name: "rt_tcp_accept"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 32},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rdi", disp: 24},
      {op: "sar1", dst: "rcx"},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "l", label: "rt_ta_out"},
      {op: "mov", dst: "rdi", src: "rcx"},
      {op: "mov", dst: "rsi", imm: 0},
      {op: "mov", dst: "rdx", imm: 0},
      {op: "mov", dst: "r10", imm: 526_336},
      {op: "mov", dst: "rax", imm: 288},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_ta_out"},
      {op: "store", src: "rax", base: "rbp", disp: -16}
    ],
    new_handle(-16),
    [
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "label", name: "rt_ta_out"}
    ],
    leave_with(-8, -24)
  ]
)

@doc """
RT_TCP_OPEN: tcp_connect natively: a handle connected to the "host:port" string in rdi (consumed) within the tagged milliseconds in rsi: a non-blocking connect, poll for writable, SO_ERROR; an error carrying the negated errno when it cannot (EINVAL for an address that does not parse or resolve, ETIMEDOUT, -110, when the time runs out).

    RT_TCP_OPEN[0] #=> {op: "label", name: "rt_tcp_open"}
"""
RT_TCP_OPEN = append(
  *[
    [
      {op: "label", name: "rt_tcp_open"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 96},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -16},
      {op: "mov", dst: "rcx", imm: -1},
      {op: "store", src: "rcx", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -32},
      {op: "call_label", label: "rt_sockaddr"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_to_sock"},
      {op: "mov", dst: "rax", imm: -22},
      {op: "jmp", label: "rt_to_bad"},
      {op: "label", name: "rt_to_sock"}
    ],
    socket_open("rt_to", -40),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -32},
      {op: "mov", dst: "rdx", imm: 16},
      {op: "mov", dst: "rax", imm: 42},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_to_ok"},
      {op: "cmp", dst: "rax", imm: -115},
      {op: "j", cond: "ne", label: "rt_to_bad"},
      {op: "load", dst: "rcx", base: "rbp", disp: -40},
      {op: "movabs", dst: "rdx", imm: 4 * 4_294_967_296},
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "store", src: "rcx", base: "rbp", disp: -64},
      {op: "mov", dst: "rdi", src: "rbp"},
      {op: "add", dst: "rdi", imm: -64},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "load", dst: "rdx", base: "rbp", disp: -16},
      {op: "sar1", dst: "rdx"},
      {op: "mov", dst: "rax", imm: 7},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_to_bad"},
      {op: "j", cond: "g", label: "rt_to_check"},
      {op: "mov", dst: "rax", imm: -110},
      {op: "jmp", label: "rt_to_bad"},
      {op: "label", name: "rt_to_check"},
      {op: "mov", dst: "rax", imm: 0},
      {op: "store", src: "rax", base: "rbp", disp: -72},
      {op: "mov", dst: "rax", imm: 4},
      {op: "store", src: "rax", base: "rbp", disp: -80},
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", imm: 1},
      {op: "mov", dst: "rdx", imm: 4},
      {op: "mov", dst: "r10", src: "rbp"},
      {op: "add", dst: "r10", imm: -72},
      {op: "mov", dst: "r8", src: "rbp"},
      {op: "add", dst: "r8", imm: -80},
      {op: "mov", dst: "rax", imm: 55},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "l", label: "rt_to_bad"},
      {op: "load", dst: "rcx", base: "rbp", disp: -72},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_to_ok"},
      {op: "mov", dst: "rax", imm: 0},
      {op: "sub", dst: "rax", src: "rcx"},
      {op: "jmp", label: "rt_to_bad"},
      {op: "label", name: "rt_to_ok"}
    ],
    new_handle(-40),
    [
      {op: "store", src: "rax", base: "rbp", disp: -48},
      {op: "jmp", label: "rt_to_out"}
    ],
    close_and_raise("rt_to", -40, -56, -48),
    [{op: "label", name: "rt_to_out"}],
    leave_with(-8, -48)
  ]
)

@doc """
TCP_CHUNK: the most bytes one tcp_read or tcp_write moves, the size of the buffer in its frame.

    TCP_CHUNK #=> 4096
"""
TCP_CHUNK = 4096

@doc """
RT_TCP_READ: tcp_read natively: at most the tagged max in rsi bytes (and at most TCP_CHUNK) from the handle in rdi (consumed), as a list of numbers built from the last byte back. None ready, a closed handle or a max below 1 answer nil, which is also the empty list natively; when the peer has closed, the handle is closed too (its descriptor -1), so net_wait reports it :closed.

    RT_TCP_READ[0] #=> {op: "label", name: "rt_tcp_read"}
"""
RT_TCP_READ = append(
  *[
    [
      {op: "label", name: "rt_tcp_read"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: TCP_CHUNK + 64},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rdi", disp: 24},
      {op: "sar1", dst: "rcx"},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "l", label: "rt_tr_out"},
      {op: "sar1", dst: "rsi"},
      {op: "cmp", dst: "rsi", imm: 1},
      {op: "j", cond: "l", label: "rt_tr_out"},
      {op: "cmp", dst: "rsi", imm: TCP_CHUNK},
      {op: "j", cond: "le", label: "rt_tr_sized"},
      {op: "mov", dst: "rsi", imm: TCP_CHUNK},
      {op: "label", name: "rt_tr_sized"},
      {op: "mov", dst: "rdx", src: "rsi"},
      {op: "mov", dst: "rdi", src: "rcx"},
      {op: "mov", dst: "rsi", src: "rbp"},
      {op: "add", dst: "rsi", imm: -(TCP_CHUNK + 64)},
      {op: "mov", dst: "rax", imm: 0},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "g", label: "rt_tr_build"},
      {op: "j", cond: "l", label: "rt_tr_none"},
      {op: "load", dst: "rcx", base: "rbp", disp: -8},
      {op: "load", dst: "rdi", base: "rcx", disp: 24},
      {op: "sar1", dst: "rdi"},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "load", dst: "rcx", base: "rbp", disp: -8},
      {op: "mov", dst: "rax", imm: -1},
      {op: "store", src: "rax", base: "rcx", disp: 24},
      {op: "jmp", label: "rt_tr_out"},
      {op: "label", name: "rt_tr_none"},
      {op: "mov", dst: "rcx", imm: EMPTY},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "jmp", label: "rt_tr_out"},
      {op: "label", name: "rt_tr_build"},
      {op: "store", src: "rax", base: "rbp", disp: -32},
      {op: "label", name: "rt_tr_byte"},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_tr_out"},
      {op: "sub", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "mov", dst: "rdx", src: "rbp"},
      {op: "add", dst: "rdx", imm: -(TCP_CHUNK + 64)},
      {op: "add", dst: "rdx", src: "rcx"},
      {op: "load_byte", dst: "rcx", base: "rdx"},
      {op: "mov", dst: "rdx", src: "rcx"},
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -40}
    ],
    cell(-40, -24, -24),
    [{op: "jmp", label: "rt_tr_byte"}, {op: "label", name: "rt_tr_out"}],
    leave_with(-8, -24)
  ]
)

@doc """
RT_TCP_WRITE: tcp_write natively: the bytes in rsi (a string, or a list of numbers, at most TCP_CHUNK of them gathered in the frame; consumed) sent on the handle in rdi (consumed) without blocking and without SIGPIPE (send with MSG_NOSIGNAL): how many went out, tagged, 0 when the socket is full, closed or the peer is gone.

    RT_TCP_WRITE[0] #=> {op: "label", name: "rt_tcp_write"}
"""
RT_TCP_WRITE = [
  {op: "label", name: "rt_tcp_write"},
  {op: "push_rbp"},
  {op: "mov", dst: "rbp", src: "rsp"},
  {op: "sub", dst: "rsp", imm: TCP_CHUNK + 64},
  {op: "store", src: "rdi", base: "rbp", disp: -8},
  {op: "store", src: "rsi", base: "rbp", disp: -16},
  {op: "mov", dst: "rcx", imm: 1},
  {op: "store", src: "rcx", base: "rbp", disp: -24},
  {op: "load", dst: "rcx", base: "rdi", disp: 24},
  {op: "sar1", dst: "rcx"},
  {op: "cmp", dst: "rcx", imm: 0},
  {op: "j", cond: "l", label: "rt_tw_out"},
  {op: "store", src: "rcx", base: "rbp", disp: -32},
  {op: "cmp", dst: "rsi", imm: 0},
  {op: "j", cond: "e", label: "rt_tw_out"},
  {op: "cmp", dst: "rsi", imm: EMPTY},
  {op: "j", cond: "e", label: "rt_tw_out"},
  {op: "load", dst: "rax", base: "rsi", disp: 0},
  {op: "cmp", dst: "rax", imm: 1},
  {op: "j", cond: "ne", label: "rt_tw_list"},
  {op: "load", dst: "rdx", base: "rsi", disp: 24},
  {op: "add", dst: "rsi", imm: 32},
  {op: "jmp", label: "rt_tw_send"},
  {op: "label", name: "rt_tw_list"},
  {op: "mov", dst: "r8", src: "rsi"},
  {op: "mov", dst: "r10", src: "rbp"},
  {op: "add", dst: "r10", imm: -(TCP_CHUNK + 64)},
  {op: "mov", dst: "r9", imm: 0},
  {op: "label", name: "rt_tw_gather"},
  {op: "cmp", dst: "r8", imm: 0},
  {op: "j", cond: "e", label: "rt_tw_gathered"},
  {op: "cmp", dst: "r9", imm: TCP_CHUNK},
  {op: "j", cond: "ge", label: "rt_tw_gathered"},
  {op: "load", dst: "rcx", base: "r8", disp: 24},
  {op: "sar1", dst: "rcx"},
  {op: "mov", dst: "rdx", src: "r10"},
  {op: "add", dst: "rdx", src: "r9"},
  {op: "store_byte", src: "rcx", base: "rdx"},
  {op: "add", dst: "r9", imm: 1},
  {op: "load", dst: "r8", base: "r8", disp: 32},
  {op: "jmp", label: "rt_tw_gather"},
  {op: "label", name: "rt_tw_gathered"},
  {op: "mov", dst: "rdx", src: "r9"},
  {op: "mov", dst: "rsi", src: "r10"},
  {op: "label", name: "rt_tw_send"},
  {op: "load", dst: "rdi", base: "rbp", disp: -32},
  {op: "mov", dst: "r10", imm: 16384},
  {op: "mov", dst: "r8", imm: 0},
  {op: "mov", dst: "r9", imm: 0},
  {op: "mov", dst: "rax", imm: 44},
  {op: "syscall"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ge", label: "rt_tw_counted"},
  {op: "mov", dst: "rax", imm: 0},
  {op: "label", name: "rt_tw_counted"},
  {op: "mov", dst: "rcx", src: "rax"},
  {op: "add", dst: "rax", src: "rcx"},
  {op: "add", dst: "rax", imm: 1},
  {op: "store", src: "rax", base: "rbp", disp: -24},
  {op: "label", name: "rt_tw_out"},
  {op: "load", dst: "rdi", base: "rbp", disp: -16},
  {op: "call_label", label: "rt_drop"},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "call_label", label: "rt_drop"},
  {op: "load", dst: "rax", base: "rbp", disp: -24},
  {op: "mov", dst: "rsp", src: "rbp"},
  {op: "pop_rbp"},
  {op: "ret"}
]

@doc """
RT_TCP_CLOSE: tcp_close natively: the handle in rdi (consumed) closed and marked -1, so closing twice is done; nil.

    RT_TCP_CLOSE[0] #=> {op: "label", name: "rt_tcp_close"}
"""
RT_TCP_CLOSE = append(
  *[
    [
      {op: "label", name: "rt_tcp_close"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 16},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "load", dst: "rcx", base: "rdi", disp: 24},
      {op: "sar1", dst: "rcx"},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "l", label: "rt_tx_out"},
      {op: "mov", dst: "rdi", src: "rcx"},
      {op: "mov", dst: "rax", imm: 3},
      {op: "syscall"},
      {op: "load", dst: "rcx", base: "rbp", disp: -8},
      {op: "mov", dst: "rax", imm: -1},
      {op: "store", src: "rax", base: "rcx", disp: 24},
      {op: "label", name: "rt_tx_out"}
    ],
    leave_with(-8, -16)
  ]
)

@doc """
socket_programs: programs over the TCP words natively, with the exit status each must give: a listener's port, a connection to it accepted, written to and read from (2 bytes plus the first, 104), a peer's close read as nil, an address with no port and a refused connect raised, nothing waiting to accept, and a list of numbers written.

    length(socket_programs) #=> 7
"""
def socket_programs()
  pair = "(let ((l (tcp_listen \"127.0.0.1:0\"))) (let ((c (tcp_connect (concat \"127.0.0.1:\" (to_s (tcp_port l))) 1000))) (let ((a (tcp_accept l))) "
  [
    ["(let ((l (tcp_listen \"127.0.0.1:0\"))) (if (< 0 (tcp_port l)) 0 1))", 0],
    [
      "#{pair}(let ((n (tcp_write c \"hi\"))) (let ((r (tcp_read a 10))) (begin (tcp_close c) (tcp_close a) (tcp_close l) (+ n (first r))))))))",
      106
    ],
    [
      "#{pair}(begin (tcp_close c) (if (equal? (tcp_read a 10) nil) 0 1)))))",
      0
    ],
    ["(try (tcp_listen \"nohost\") (catch (e) 7))", 7],
    ["(try (tcp_connect \"127.0.0.1:1\" 500) (catch (e) 9))", 9],
    [
      "(let ((l (tcp_listen \"127.0.0.1:0\"))) (if (equal? (tcp_accept l) nil) 0 1))",
      0
    ],
    [
      "#{pair}(begin (tcp_write c (list 104 105)) (length (tcp_read a 10))))))",
      2
    ]
  ]
end

test "the TCP words listen, connect, read and write natively", {
  kind: :integration,
  allow: %i[filesystem network process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-sock"), "sock.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      socket_programs
    )
  end
end

test "each TCP word calls its routine, and the routines assemble with their callees"
  assert last(routine_op([], "tcp_port", [1])) ==
    {op: "call_label", label: "rt_tcp_port"}
  assert rc_op([], "tcp_close", [1]) == routine_op([], "tcp_close", [1])
  assert length(routine_op([], "tcp_read", [1, 2])) == 3
  stand_ins = flat_map(
    %w[rt_alloc rt_drop rt_hosts_lookup rt_dns_lookup],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  routines = append(
    *[
      RT_RESOLVE,
      RT_SOCKADDR,
      RT_TCP_LISTEN,
      RT_TCP_PORT,
      RT_TCP_ACCEPT,
      RT_TCP_OPEN,
      RT_TCP_READ,
      RT_TCP_WRITE,
      RT_TCP_CLOSE,
      stand_ins
    ]
  )
  assert length(assemble(routines)) > 0
  assert new_handle(-40)[2] == {op: "mov", dst: "rcx", imm: HANDLE_KIND}
  assert error_from("rax")[0] == {op: "push", src: "rax"}
  assert close_and_raise("t", -40, -56, -48)[0] == {op: "label", name: "t_bad"}
  assert last(leave_with(-8, -16)) == {op: "ret"}
  assert last(socket_open("t", -40))[:disp] == -40
  assert TCP_CHUNK == 4096
  assert map((w) -> w[0], TCP_OPS) ==
    %w[tcp_listen tcp_port tcp_accept tcp_connect tcp_read tcp_write tcp_close]
  assert length(socket_programs) == 7
end

@doc """
net_events: the instructions that set rdx to the poll events the interest keyword in rcx asks for, against the keywords the call passed (rbp-112 :read, -120 :write, -128 :both): POLLIN (1) for :read, POLLOUT (4) for :write, both (5) for :both, none for any other.

    length(net_events) #=> 16
"""
def net_events()
  [
    {op: "mov", dst: "rdx", imm: 0},
    {op: "load", dst: "rax", base: "rbp", disp: -112},
    {op: "cmp", dst: "rcx", src: "rax"},
    {op: "j", cond: "ne", label: "rt_nw_not_read"},
    {op: "mov", dst: "rdx", imm: 1},
    {op: "label", name: "rt_nw_not_read"},
    {op: "load", dst: "rax", base: "rbp", disp: -120},
    {op: "cmp", dst: "rcx", src: "rax"},
    {op: "j", cond: "ne", label: "rt_nw_not_write"},
    {op: "mov", dst: "rdx", imm: 4},
    {op: "label", name: "rt_nw_not_write"},
    {op: "load", dst: "rax", base: "rbp", disp: -128},
    {op: "cmp", dst: "rcx", src: "rax"},
    {op: "j", cond: "ne", label: "rt_nw_not_both"},
    {op: "mov", dst: "rdx", imm: 5},
    {op: "label", name: "rt_nw_not_both"}
  ]
end

@doc """
net_pair: the instructions that cons [handle at rbp-80, the keyword at rbp+kw] onto the answer at rbp-40, the handle taking one more reference.

    last(net_pair(-112))[:disp] #=> -40
"""
def net_pair(kw)
  append(
    *[
      [
        {op: "load", dst: "rcx", base: "rbp", disp: -80},
        {op: "load", dst: "rdx", base: "rcx", disp: 8},
        {op: "add", dst: "rdx", imm: 1},
        {op: "store", src: "rdx", base: "rcx", disp: 8},
        {op: "load", dst: "rcx", base: "rbp", disp: kw},
        {op: "store", src: "rcx", base: "rbp", disp: -88}
      ],
      cell(-88, 0, -96),
      cell(-80, -96, -96),
      cell(-96, -40, -40)
    ]
  )
end

@doc """
RT_NET_WAIT: net_wait natively (R4 of docs/PURE-BLUE.md), over poll(2) and level-triggered as the reference is: the interests in rdi ([[handle, :read | :write | :both], …], consumed) and the tagged milliseconds in rsi (nil waits as long as it takes, 0 only checks), with the keywords :read, :write, :both and :closed in rdx, rcx, r8 and r9 (the call site passes them, as the data section is the program's). The answer is [[handle, :read | :write | :closed], …] in the interests' order, a handle closed when poll says hung up or failed with nothing to read, or when it is already closed (its descriptor -1, which also makes the wait only check); nil, the empty list natively, when the time passed. A poll cut short by a signal is asked again. The pollfds and the handles live in one scratch block for the call.

    RT_NET_WAIT[0] #=> {op: "label", name: "rt_net_wait"}
"""
RT_NET_WAIT = append(
  *[
    [
      {op: "label", name: "rt_net_wait"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 144}
    ],
    swap_word("rdi", EMPTY, 0, "rax"),
    [
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rdx", base: "rbp", disp: -112},
      {op: "store", src: "rcx", base: "rbp", disp: -120},
      {op: "store", src: "r8", base: "rbp", disp: -128},
      {op: "store", src: "r9", base: "rbp", disp: -136},
      {op: "mov", dst: "rcx", imm: -1},
      {op: "cmp", dst: "rsi", imm: 0},
      {op: "j", cond: "e", label: "rt_nw_timed"},
      {op: "mov", dst: "rcx", src: "rsi"},
      {op: "sar1", dst: "rcx"},
      {op: "label", name: "rt_nw_timed"},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -40},
      {op: "mov", dst: "r8", src: "rdi"},
      {op: "mov", dst: "r9", imm: 0},
      {op: "label", name: "rt_nw_count"},
      {op: "cmp", dst: "r8", imm: 0},
      {op: "j", cond: "e", label: "rt_nw_counted"},
      {op: "add", dst: "r9", imm: 1},
      {op: "load", dst: "r8", base: "r8", disp: 32},
      {op: "jmp", label: "rt_nw_count"},
      {op: "label", name: "rt_nw_counted"},
      {op: "store", src: "r9", base: "rbp", disp: -32},
      {op: "mov", dst: "rdi", src: "r9"},
      {op: "add", dst: "rdi", src: "r9"},
      {op: "add", dst: "rdi", imm: 4},
      {op: "call_label", label: "rt_alloc"},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rax", disp: 0},
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "load", dst: "r8", base: "rbp", disp: -8},
      {op: "mov", dst: "r9", imm: 0},
      {op: "label", name: "rt_nw_fill"},
      {op: "cmp", dst: "r8", imm: 0},
      {op: "j", cond: "e", label: "rt_nw_filled"},
      {op: "store", src: "r8", base: "rbp", disp: -48},
      {op: "store", src: "r9", base: "rbp", disp: -56},
      {op: "load", dst: "r10", base: "r8", disp: 24},
      {op: "load", dst: "r11", base: "r10", disp: 24},
      {op: "store", src: "r11", base: "rbp", disp: -64},
      {op: "load", dst: "rcx", base: "r10", disp: 32},
      {op: "load", dst: "rcx", base: "rcx", disp: 24}
    ],
    net_events,
    [
      {op: "load", dst: "r11", base: "rbp", disp: -64},
      {op: "load", dst: "rax", base: "r11", disp: 24},
      {op: "sar1", dst: "rax"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ge", label: "rt_nw_open"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "movabs", dst: "rax", imm: 4_294_967_295},
      {op: "label", name: "rt_nw_open"},
      {op: "movabs", dst: "rcx", imm: 4_294_967_296},
      {op: "imul", dst: "rdx", src: "rcx"},
      {op: "add", dst: "rax", src: "rdx"},
      {op: "load", dst: "r9", base: "rbp", disp: -56},
      {op: "load", dst: "r10", base: "rbp", disp: -24},
      {op: "mov", dst: "rcx", src: "r9"}
    ],
    times8("rcx"),
    [
      {op: "add", dst: "rcx", src: "r10"},
      {op: "store", src: "rax", base: "rcx", disp: 24},
      {op: "load", dst: "rdx", base: "rbp", disp: -32}
    ],
    times8("rdx"),
    [
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "store", src: "r11", base: "rcx", disp: 24},
      {op: "add", dst: "r9", imm: 1},
      {op: "load", dst: "r8", base: "rbp", disp: -48},
      {op: "load", dst: "r8", base: "r8", disp: 32},
      {op: "jmp", label: "rt_nw_fill"},
      {op: "label", name: "rt_nw_filled"},
      {op: "label", name: "rt_nw_poll"},
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "add", dst: "rdi", imm: 24},
      {op: "load", dst: "rsi", base: "rbp", disp: -32},
      {op: "load", dst: "rdx", base: "rbp", disp: -16},
      {op: "mov", dst: "rax", imm: 7},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: -4},
      {op: "j", cond: "e", label: "rt_nw_poll"},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "store", src: "rcx", base: "rbp", disp: -56},
      {op: "label", name: "rt_nw_answer"},
      {op: "load", dst: "r9", base: "rbp", disp: -56},
      {op: "cmp", dst: "r9", imm: 0},
      {op: "j", cond: "e", label: "rt_nw_out"},
      {op: "sub", dst: "r9", imm: 1},
      {op: "store", src: "r9", base: "rbp", disp: -56},
      {op: "load", dst: "r10", base: "rbp", disp: -24},
      {op: "mov", dst: "rcx", src: "r9"}
    ],
    times8("rcx"),
    [
      {op: "add", dst: "rcx", src: "r10"},
      {op: "load", dst: "rax", base: "rcx", disp: 24},
      {op: "store", src: "rax", base: "rbp", disp: -72},
      {op: "load", dst: "rdx", base: "rbp", disp: -32}
    ],
    times8("rdx"),
    [
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "load", dst: "rcx", base: "rcx", disp: 24},
      {op: "store", src: "rcx", base: "rbp", disp: -80},
      {op: "load", dst: "rax", base: "rbp", disp: -72},
      {op: "mov", dst: "rdx", src: "rax"},
      {op: "and", dst: "rdx", imm: -2_147_483_648},
      {op: "load", dst: "rcx", base: "rbp", disp: -80},
      {op: "load", dst: "rcx", base: "rcx", disp: 24},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "l", label: "rt_nw_closed"}
    ],
    map((_k) -> {op: "shr1", dst: "rax"}, range(0, 48)),
    [
      {op: "store", src: "rax", base: "rbp", disp: -104},
      {op: "mov", dst: "rcx", src: "rax"},
      {op: "and", dst: "rcx", imm: 1},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "ne", label: "rt_nw_open_events"},
      {op: "mov", dst: "rcx", src: "rax"},
      {op: "and", dst: "rcx", imm: 56},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "ne", label: "rt_nw_closed"},
      {op: "label", name: "rt_nw_open_events"},
      {op: "load", dst: "rax", base: "rbp", disp: -104},
      {op: "and", dst: "rax", imm: 4},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_nw_no_write"}
    ],
    net_pair(-120),
    [
      {op: "label", name: "rt_nw_no_write"},
      {op: "load", dst: "rax", base: "rbp", disp: -104},
      {op: "and", dst: "rax", imm: 1},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_nw_answer"}
    ],
    net_pair(-112),
    [{op: "jmp", label: "rt_nw_answer"}, {op: "label", name: "rt_nw_closed"}],
    net_pair(-136),
    [{op: "jmp", label: "rt_nw_answer"}, {op: "label", name: "rt_nw_out"}],
    empty_when_none(-40),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -24},
      {op: "call_label", label: "rt_drop"}
    ],
    leave_with(-8, -40)
  ]
)

@doc """
wait_programs: programs over net_wait natively, with the exit status each must give: a listener with a connection waiting reads as :read, an idle listener times out to nil, a fresh connection is writable, a peer's close reads as :closed after tcp_read sees it, an already closed handle is :closed at once, and :both answers :write for an idle connection.

    length(wait_programs) #=> 6
"""
def wait_programs()
  pair = "(let ((l (tcp_listen \"127.0.0.1:0\"))) (let ((c (tcp_connect (concat \"127.0.0.1:\" (to_s (tcp_port l))) 1000))) "
  [
    [
      "#{pair}(if (equal? (first (rest (first (net_wait (list (list l :read)) 1000)))) :read) 0 1)))",
      0
    ],
    [
      "(let ((l (tcp_listen \"127.0.0.1:0\"))) (if (equal? (net_wait (list (list l :read)) 50) (list)) 0 1))",
      0
    ],
    [
      "#{pair}(if (equal? (first (rest (first (net_wait (list (list c :write)) 1000)))) :write) 0 1)))",
      0
    ],
    [
      "#{pair}(let ((a (tcp_accept l))) (begin (tcp_close c) (tcp_read a 10) (if (equal? (first (rest (first (net_wait (list (list a :read)) 1000)))) :closed) 0 1)))))",
      0
    ],
    [
      "#{pair}(begin (tcp_close c) (length (net_wait (list (list c :read)))))))",
      1
    ],
    [
      "#{pair}(let ((a (tcp_accept l))) (if (equal? (first (rest (first (net_wait (list (list a :both)) 1000)))) :write) 0 1))))",
      0
    ]
  ]
end

test "net_wait answers readiness, time-outs and closes natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem network process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-wait"), "wait.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      wait_programs
    )
  end
end

test "net_wait polls a scratch block of pollfds and conses its answer from the last"
  stand_ins = flat_map(
    append(%w[rt_alloc rt_drop], map(kw_label, NET_WAIT_KEYWORDS)),
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(assemble(append(RT_NET_WAIT, stand_ins))) > 0
  assert length(net_events) == 16
  assert last(net_pair(-112))[:disp] == -40
  assert length(wait_programs) == 6
  assert last(rc_op([], "net_wait", [1, 2])) ==
    {op: "call_label", label: "rt_net_wait"}
  assert length(net_wait_op([], [1])) == 7
end

@doc """
net_wait_op: the instructions of net_wait: the interests in rdi, the timeout in rsi (nil when it is not given), the four keywords it reads and answers in rdx, rcx, r8 and r9, then a call to rt_net_wait.

    last(net_wait_op([], [1])) #=> {op: "call_label", label: "rt_net_wait"}
"""
def net_wait_op(slots, args)
  append(
    *[
      tagged_atom(slots, args[0], "rdi"),
      if length(args) > 1
        tagged_atom(slots, args[1], "rsi")
      else
        [{op: "mov", dst: "rsi", imm: 0}]
      end,
      map(
        (p) -> {op: "lea_label", dst: p[1], label: kw_label(p[0])},
        [[:read, "rdx"], [:write, "rcx"], [:both, "r8"], [:closed, "r9"]]
      ),
      [{op: "call_label", label: "rt_net_wait"}]
    ]
  )
end

@doc """
put_text: the instructions that write the bytes of a text to standard output one rt_put_byte at a time.

    length(put_text("ab")) #=> 4
"""
def put_text(s)
  flat_map(
    text_bytes(s),
    fn(c)
      [
        {op: "mov", dst: "rdi", imm: 2 * c + 1},
        {op: "call_label", label: "rt_put_byte"}
      ]
    end
  )
end

@doc """
SHOW_ESCAPES: each byte a shown string writes escaped, and the letter after its backslash.

    SHOW_ESCAPES[2] #=> [10, "n"]
"""
SHOW_ESCAPES = [
  [34, "\""],
  [92, "\\"],
  [10, "n"],
  [9, "t"],
  [13, "r"],
  [0, "u{0}"]
]

@doc """
show_escape: the instructions that, when the byte in rax is one of SHOW_ESCAPES, write it as a backslash and its letter and jump to done.

    length(show_escape("t")) #=> 54
"""
def show_escape(done)
  flat_map(
    SHOW_ESCAPES,
    fn(e)
      skip = "rt_sh_esc_#{to_s(e[0])}"
      append(
        *[
          [
            {op: "cmp", dst: "rax", imm: e[0]},
            {op: "j", cond: "ne", label: skip}
          ],
          put_text("\\#{e[1]}"),
          [{op: "jmp", label: done}, {op: "label", name: skip}]
        ]
      )
    end
  )
end

@doc """
SHOW_MAP: rt_show's map case, from rt_sh_map: { then each entry, a keyword key as its name and a colon, any other key shown and =>, then its value shown, between commas, then }.

    SHOW_MAP[0] #=> {op: "label", name: "rt_sh_map"}
"""
SHOW_MAP = append(
  *[
    [
      {op: "label", name: "rt_sh_map"},
      {op: "load", dst: "rcx", base: "rdi", disp: 24},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -24}
    ],
    put_text("{"),
    [
      {op: "label", name: "rt_sh_entry"},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_sh_map_end"},
      {op: "cmp", dst: "rcx", imm: EMPTY},
      {op: "j", cond: "e", label: "rt_sh_map_end"},
      {op: "load", dst: "rax", base: "rbp", disp: -24},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_sh_entry_first"}
    ],
    put_text(", "),
    [
      {op: "label", name: "rt_sh_entry_first"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "load", dst: "rcx", base: "rcx", disp: 24},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "load", dst: "rdi", base: "rcx", disp: 24},
      {op: "mov", dst: "rax", src: "rdi"},
      {op: "and", dst: "rax", imm: 1},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_sh_key_other"},
      {op: "cmp", dst: "rdi", imm: 4096},
      {op: "j", cond: "l", label: "rt_sh_key_other"},
      {op: "load", dst: "rax", base: "rdi", disp: 0},
      {op: "cmp", dst: "rax", imm: 2},
      {op: "j", cond: "ne", label: "rt_sh_key_other"},
      {op: "mov", dst: "rsi", src: "rdi"},
      {op: "load", dst: "rdx", base: "rsi", disp: 24},
      {op: "add", dst: "rsi", imm: 32},
      {op: "load", dst: "rdi", base: "r14", disp: SHOW_FD_AT},
      {op: "mov", dst: "rax", imm: 1},
      {op: "syscall"}
    ],
    put_text(": "),
    [
      {op: "jmp", label: "rt_sh_value"},
      {op: "label", name: "rt_sh_key_other"},
      {op: "call_label", label: "rt_show"}
    ],
    put_text(" => "),
    [
      {op: "label", name: "rt_sh_value"},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "load", dst: "rcx", base: "rcx", disp: 32},
      {op: "load", dst: "rdi", base: "rcx", disp: 24},
      {op: "call_label", label: "rt_show"},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "load", dst: "rcx", base: "rcx", disp: 32},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "jmp", label: "rt_sh_entry"},
      {op: "label", name: "rt_sh_map_end"}
    ],
    put_text("}")
  ]
)

@doc """
RT_SHOW: a value written to standard output as blue writes its literal (to_s inside a list), the value in rdi borrowed: a number in decimal, nil, true, a string quoted with SHOW_ESCAPES, a keyword as :name, a list as [a, b] with each element shown in turn, an error as <error> and a function as <fn>. Natively false and the empty list are nil, so each shows as nil.

    RT_SHOW[0] #=> {op: "label", name: "rt_show"}
"""
RT_SHOW = append(
  *[
    [
      {op: "label", name: "rt_show"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 32},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rax", src: "rdi"},
      {op: "and", dst: "rax", imm: 1},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_sh_not_int"},
      {op: "call_label", label: "rt_put_int"},
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_not_int"},
      {op: "cmp", dst: "rdi", imm: 0},
      {op: "j", cond: "ne", label: "rt_sh_not_nil"}
    ],
    put_text("nil"),
    [
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_not_nil"},
      {op: "cmp", dst: "rdi", imm: 2},
      {op: "j", cond: "ne", label: "rt_sh_not_true"}
    ],
    put_text("true"),
    [
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_not_true"},
      {op: "cmp", dst: "rdi", imm: FALSE},
      {op: "j", cond: "ne", label: "rt_sh_not_false"}
    ],
    put_text("false"),
    [
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_not_false"},
      {op: "cmp", dst: "rdi", imm: EMPTY},
      {op: "j", cond: "ne", label: "rt_sh_block"}
    ],
    put_text("[]"),
    [
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_block"},
      {op: "load", dst: "rax", base: "rdi", disp: 0},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_sh_list"},
      {op: "cmp", dst: "rax", imm: 1},
      {op: "j", cond: "e", label: "rt_sh_string"},
      {op: "cmp", dst: "rax", imm: 2},
      {op: "j", cond: "e", label: "rt_sh_keyword"},
      {op: "cmp", dst: "rax", imm: 4},
      {op: "j", cond: "e", label: "rt_sh_error"},
      {op: "cmp", dst: "rax", imm: MAP_KIND},
      {op: "j", cond: "e", label: "rt_sh_map"}
    ],
    put_text("<fn>"),
    [{op: "jmp", label: "rt_sh_out"}, {op: "label", name: "rt_sh_error"}],
    put_text("<error>"),
    [{op: "jmp", label: "rt_sh_out"}],
    SHOW_MAP,
    [{op: "jmp", label: "rt_sh_out"}, {op: "label", name: "rt_sh_keyword"}],
    put_text(":"),
    [
      {op: "load", dst: "rsi", base: "rbp", disp: -8},
      {op: "load", dst: "rdx", base: "rsi", disp: 24},
      {op: "add", dst: "rsi", imm: 32},
      {op: "load", dst: "rdi", base: "r14", disp: SHOW_FD_AT},
      {op: "mov", dst: "rax", imm: 1},
      {op: "syscall"},
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_list"},
      {op: "store", src: "rdi", base: "rbp", disp: -16},
      {op: "mov", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -24}
    ],
    put_text("["),
    [
      {op: "label", name: "rt_sh_elem"},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_sh_list_end"},
      {op: "load", dst: "rax", base: "rbp", disp: -24},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_sh_first"}
    ],
    put_text(", "),
    [
      {op: "label", name: "rt_sh_first"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "mov", dst: "rax", src: "rcx"},
      {op: "and", dst: "rax", imm: 1},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_sh_tail"},
      {op: "cmp", dst: "rcx", imm: 2},
      {op: "j", cond: "e", label: "rt_sh_tail"},
      {op: "load", dst: "rax", base: "rcx", disp: 0},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_sh_tail"},
      {op: "load", dst: "rdi", base: "rcx", disp: 24},
      {op: "call_label", label: "rt_show"},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "load", dst: "rcx", base: "rcx", disp: 32},
      {op: "store", src: "rcx", base: "rbp", disp: -16},
      {op: "jmp", label: "rt_sh_elem"},
      {op: "label", name: "rt_sh_tail"},
      {op: "mov", dst: "rdi", src: "rcx"},
      {op: "call_label", label: "rt_show"},
      {op: "label", name: "rt_sh_list_end"}
    ],
    put_text("]"),
    [
      {op: "jmp", label: "rt_sh_out"},
      {op: "label", name: "rt_sh_string"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -16}
    ],
    put_text("\""),
    [
      {op: "label", name: "rt_sh_byte"},
      {op: "load", dst: "rsi", base: "rbp", disp: -8},
      {op: "load", dst: "rcx", base: "rbp", disp: -16},
      {op: "load", dst: "rdx", base: "rsi", disp: 24},
      {op: "cmp", dst: "rcx", src: "rdx"},
      {op: "j", cond: "e", label: "rt_sh_string_end"},
      {op: "add", dst: "rsi", imm: 32},
      {op: "add", dst: "rsi", src: "rcx"},
      {op: "load_byte", dst: "rax", base: "rsi"},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -16}
    ],
    show_escape("rt_sh_byte"),
    [
      {op: "mov", dst: "rdi", src: "rax"},
      {op: "add", dst: "rdi", src: "rax"},
      {op: "add", dst: "rdi", imm: 1},
      {op: "call_label", label: "rt_put_byte"},
      {op: "jmp", label: "rt_sh_byte"},
      {op: "label", name: "rt_sh_string_end"}
    ],
    put_text("\""),
    [
      {op: "label", name: "rt_sh_out"},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
show_programs: programs compiled in :show mode, with what each must write: numbers, nil, true, a string with escapes, a keyword, nested lists, a concatenation, and a NUL.

    length(show_programs) #=> 8
"""
def show_programs()
  [
    %w[-42 -42],
    %w[nil nil],
    %w[true true],
    ["\"a\\\"b\\\\c\\nd\"", "\"a\\\"b\\\\c\\nd\""],
    %w[:kw :kw],
    ["(list 1 (list 2 3) \"x\" :k)", "[1, [2, 3], \"x\", :k]"],
    ["(concat \"a\" \"b\")", "\"ab\""],
    ["(concat \"a\" (concat \"\\u{0}\" \"b\"))", "\"a\\u{0}b\""]
  ]
end

test "a :show program writes its value as blue does natively", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-show"), "show.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        r = exec_capture(path)
        assert status_of(r) == 0
        assert stdout_of(r) == p[1]
      end,
      show_programs
    )
  end
end

test "show escapes a string's quotes, backslashes and breaks, and ends a :show program in exit 0"
  assert length(put_text("ab")) == 4
  assert length(show_escape("t")) == 54
  assert SHOW_ESCAPES[2] == [10, "n"]
  stand_ins = flat_map(
    %w[rt_put_int rt_put_byte],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(assemble(append(RT_SHOW, stand_ins))) > 0
  assert member?(
    {op: "call_label", label: "rt_show"},
    rc_gen([], read_forms("(ret 3)")[0], :show, 0)[0]
  )
  assert length(show_programs) == 8
end

@doc """
ZERO_ARITY_WORDS: the native words that take no argument, which blue's lowering writes as a bare name when the source calls them without parentheses.

    ZERO_ARITY_WORDS[0] #=> "now"
"""
ZERO_ARITY_WORDS = %w[now now_ms now_ns now_rfc3339 self_exe read_line cwd argv]

@doc """
binders: every name a core form binds anywhere to a value: let's names, lambda's and a defined function's parameters, and a defined value's name (a defined function's own name is a function, which a bare call still calls).

    binders(read_forms("(let ((now 1)) now)")[0]) #=> ["now"]
"""
def binders(form)
  if not list?(form) or length(form) == 0
    []
  else
    head = if symbol?(form[0])
      to_s(form[0])
    else
      ""
    end
    own = if head == "let" and list?(form[1])
      map((b) -> to_s(b[0]), filter((b) -> list?(b), form[1]))
    elsif head == "lambda" and list?(form[1])
      map((p) -> to_s(p), form[1])
    elsif head == "define" and list?(form[1])
      map((p) -> to_s(p), rest(form[1]))
    elsif head == "define"
      [to_s(form[1])]
    else
      []
    end
    append(own, flat_map(form, binders))
  end
end

@doc """
bare_calls: a core form with each bare name of a ZERO_ARITY_WORDS word the program never binds made a call of that word, so `now` compiles as `(now)`, and each path_join of more than two parts nested into joins of two.

    bare_calls(read_forms("(integer? now)")[0]) == read_forms("(integer? (now))")[0] #=> true
"""
def bare_calls(form)
  packed = rest_calls(form, rest_arities(form))
  call_bare(packed, binders(packed))
end

@doc """
call_bare: bare_calls over one form, given the names the program binds.

    call_bare(read_forms("now")[0], ["now"]) == read_forms("now")[0] #=> true
"""
def call_bare(form, bound)
  if symbol?(form)
    if member?(to_s(form), ZERO_ARITY_WORDS) and not member?(to_s(form), bound)
      [form]
    else
      form
    end
  elsif list?(form) and length(form) > 0
    if symbol?(form[0]) and
        to_s(form[0]) == "blue-field" and
        keyword?(form[2]) and
        member?(to_s(form[2]), map((p) -> p[0], KIND_PREDICATES))
      [read_forms(to_s(form[2]))[0], call_bare(form[1], bound)]
    elsif symbol?(form[0]) and
        member?(to_s(form[0]), %w[or and]) and
        length(form) == 3
      call_bare(logical(to_s(form[0]), form[1], form[2]), bound)
    elsif symbol?(form[0]) and
        to_s(form[0]) == "ls" and
        length(form) == 2 and
        not member?("ls", bound)
      [
        read_forms("sort_strings")[0],
        [read_forms("ls_raw")[0], call_bare(form[1], bound)]
      ]
    elsif symbol?(form[0]) and to_s(form[0]) == "drop" and length(form) == 3
      cons(
        read_forms("list_drop")[0],
        map((f) -> call_bare(f, bound), rest(form))
      )
    elsif symbol?(form[0]) and to_s(form[0]) == "concat" and length(form) == 3
      cons(
        form[0],
        map(
          fn(a)
            c = call_bare(a, bound)
            if string?(a) or head_is?(a, "to_s")
              c
            else
              [read_forms("to_s")[0], c]
            end
          end,
          rest(form)
        )
      )
    elsif head_is?(form, "floor") and
        length(form) == 2 and
        head_is?(form[1], "/")
      cons(
        read_forms("int_div")[0],
        map((f) -> call_bare(f, bound), rest(form[1]))
      )
    elsif head_is?(form, "read_bytes") and length(form) == 4
      [
        read_forms("bytes_slice")[0],
        [form[0], call_bare(form[1], bound)],
        call_bare(form[2], bound),
        call_bare(form[3], bound)
      ]
    elsif head_is?(form, "exec_within") and length(form) > 2
      w = read_forms("__within")[0]
      [
        read_forms("let")[0],
        [
          [
            w,
            cons(
              read_forms("exec_within_raw")[0],
              map((f) -> call_bare(f, bound), rest(form))
            )
          ]
        ],
        nth(
          0,
          read_forms("(append __within (list (list :timed_out (exec_timed_out))))")
        )
      ]
    elsif head_is?(form, "sh_exec") and length(form) == 2
      [read_forms("exec_capture")[0], "sh", "-c", call_bare(form[1], bound)]
    elsif symbol?(form[0]) and to_s(form[0]) == "path_join" and length(form) > 3
      call_bare(
        append([form[0], [form[0], form[1], form[2]]], rest(rest(rest(form)))),
        bound
      )
    else
      cons(
        if symbol?(form[0])
          form[0]
        else
          call_bare(form[0], bound)
        end,
        map((f) -> call_bare(f, bound), rest(form))
      )
    end
  else
    form
  end
end

test "a bare zero-argument word becomes its call unless the program binds it"
  assert bare_calls(read_forms("(integer? now)")[0]) ==
    read_forms("(integer? (now))")[0]
  assert bare_calls(read_forms("(let ((now 1)) now)")[0]) ==
    read_forms("(let ((now 1)) now)")[0]
  assert binders(read_forms("(define (f a) (lambda (b) a))")[0]) == %w[a b]
  assert binders(read_forms("(define x 1)")[0]) == ["x"]
  assert bare_calls(read_forms("((f) now)")[0]) == read_forms("((f) (now))")[0]
  assert ZERO_ARITY_WORDS[5] == "read_line"
  assert call_bare(read_forms("now")[0], []) == read_forms("(now)")[0]
  assert length(compile_whole(read_forms("(+ now 1)")[0], :exit)) > 0
end

@doc """
RT_KIND_OF: the kind of the value in rdi (only read) in rax: 0 nil, 8 false, 1 a number, 2 true, 3 a list cell, 4 a string, 5 a keyword, 6 an error, 7 anything else.

    RT_KIND_OF[0] #=> {op: "label", name: "rt_kind_of"}
"""
RT_KIND_OF = [
  {op: "label", name: "rt_kind_of"},
  {op: "mov", dst: "rax", imm: 0},
  {op: "cmp", dst: "rdi", imm: 0},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 8},
  {op: "cmp", dst: "rdi", imm: FALSE},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 9},
  {op: "cmp", dst: "rdi", imm: EMPTY},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", src: "rdi"},
  {op: "and", dst: "rax", imm: 1},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ne", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 2},
  {op: "cmp", dst: "rdi", imm: 2},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "load", dst: "rcx", base: "rdi", disp: 0},
  {op: "mov", dst: "rax", imm: 3},
  {op: "cmp", dst: "rcx", imm: 0},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 4},
  {op: "cmp", dst: "rcx", imm: 1},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 5},
  {op: "cmp", dst: "rcx", imm: 2},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 6},
  {op: "cmp", dst: "rcx", imm: 4},
  {op: "j", cond: "e", label: "rt_ko_out"},
  {op: "mov", dst: "rax", imm: 7},
  {op: "label", name: "rt_ko_out"},
  {op: "ret"}
]

@doc """
KIND_PREDICATES: each type predicate native code answers and the kinds of rt_kind_of it accepts. Natively the empty list is nil, so list? holds for nil.

    KIND_PREDICATES[0] #=> ["integer?", [1]]
"""
KIND_PREDICATES = [
  ["integer?", [1]],
  ["string?", [4]],
  ["keyword?", [5]],
  ["list?", [3, 9]],
  ["boolean?", [2, 8]],
  ["nil?", [0]]
]

@doc """
kind_predicate: the instructions of a type predicate: the kind of its argument from rt_kind_of, the argument dropped, true (2) when the kind is one the predicate accepts.

    last(kind_predicate([], "integer?", [1]))[:src] #=> "rcx"
"""
def kind_predicate(slots, op, args)
  kinds = filter((p) -> p[0] == op, KIND_PREDICATES)[0][1]
  append(
    *[
      tagged_atom(slots, args[0], "rdi"),
      [
        {op: "push", src: "rdi"},
        {op: "call_label", label: "rt_kind_of"},
        {op: "pop", dst: "rdi"},
        {op: "push", src: "rax"},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rdx"},
        {op: "mov", dst: "rcx", imm: 0}
      ],
      flat_map(
        kinds,
        fn(k)
          [
            {op: "mov", dst: "rax", src: "rdx"},
            {op: "cmp", dst: "rax", imm: k},
            {op: "set", cond: "e"},
            {op: "movzx"},
            {op: "add", dst: "rcx", src: "rax"}
          ]
        end
      ),
      [
        {op: "mov", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", src: "rcx"}
      ],
      AS_BOOLEAN
    ]
  )
end

@doc """
kind_programs: programs over the type predicates, or, and and the prelude's every? natively, each must exit 0.

    length(kind_programs) #=> 5
"""
def kind_programs()
  [
    "(if (integer? 5) (if (integer? \"a\") 1 0) 2)",
    "(if (string? (concat \"a\" \"b\")) (if (keyword? :k) (if (list? (list 1)) 0 3) 4) 5)",
    "(if (boolean? true) (if (nil? nil) (if (list? 3) 6 0) 7) 8)",
    "(if (or nil true) (if (and 1 nil) 1 (if (and 1 2) 0 3)) 2)",
    "(if (every? (lambda (b) (< b 3)) (list 1 2)) (if (every? (lambda (b) (< b 2)) (list 1 2)) 1 0) 2)"
  ]
end

test "the type predicates answer natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-kind"), "kind.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p)[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == 0
        write_bytes(path, compile_program(read_forms(p)[0], :leaks))
        assert status_of(exec_capture(path)) == 0
      end,
      kind_programs
    )
  end
end

test "a type predicate asks rt_kind_of and sums its accepted kinds into a boolean"
  assert length(assemble(append(RT_KIND_OF, []))) > 0
  assert KIND_PREDICATES[3][0] == "list?"
  assert member?(
    {op: "call_label", label: "rt_kind_of"},
    rc_op([], "string?", ["a"])
  )
  assert last(kind_predicate([], "integer?", [1]))[:src] == "rcx"
  assert length(kind_programs) == 5
end

@doc """
HOST_OPS: each native host word that one runtime routine answers, its arguments in rdi then rsi.

    HOST_OPS[0] #=> ["getenv", "rt_getenv"]
"""
HOST_OPS = [
  %w[getenv rt_getenv],
  %w[env_required rt_env_required],
  %w[path_join rt_path_join],
  %w[path_basename rt_path_basename],
  %w[path_dirname rt_path_dirname],
  %w[path_extension rt_path_extension],
  %w[mkdir rt_mkdir],
  %w[mkdir_p rt_mkdir_p],
  %w[rm rt_rm],
  %w[rm_rf rt_rm_rf],
  %w[rename_file rt_rename_file],
  %w[path_exists rt_path_exists],
  %w[is_dir? rt_is_dir],
  %w[is_file? rt_is_file],
  %w[file_size rt_file_size],
  %w[file_mtime_ms rt_file_mtime_ms],
  %w[write_file rt_write_file],
  %w[append_file rt_append_file],
  %w[read_bytes rt_read_bytes],
  %w[cwd rt_cwd],
  %w[argv rt_argv],
  %w[argv_get rt_argv_get],
  %w[random_bytes rt_random_bytes],
  %w[ls_raw rt_ls_raw],
  %w[string_lt rt_string_lt],
  %w[int_div rt_floor_div]
]

@doc """
ROUTINE_OPS: every word routine_op compiles, the TCP words and the host words.

    length(ROUTINE_OPS) #=> 33
"""
ROUTINE_OPS = append(TCP_OPS, HOST_OPS)

@doc """
RT_ENV_LOOKUP: the address of the value of the environment entry named by the string in rdi (only read), in the environment the program started with (r14 + ENVP_AT), or 0 when no entry is NAME=.

    RT_ENV_LOOKUP[0] #=> {op: "label", name: "rt_env_lookup"}
"""
RT_ENV_LOOKUP = [
  {op: "label", name: "rt_env_lookup"},
  {op: "load", dst: "r9", base: "rdi", disp: 24},
  {op: "mov", dst: "r8", src: "rdi"},
  {op: "add", dst: "r8", imm: 32},
  {op: "load", dst: "rsi", base: "r14", disp: ENVP_AT},
  {op: "label", name: "rt_el_entry"},
  {op: "load", dst: "rcx", base: "rsi", disp: 0},
  {op: "mov", dst: "rax", imm: 0},
  {op: "cmp", dst: "rcx", imm: 0},
  {op: "j", cond: "e", label: "rt_el_out"},
  {op: "mov", dst: "r11", imm: 0},
  {op: "label", name: "rt_el_byte"},
  {op: "cmp", dst: "r11", src: "r9"},
  {op: "j", cond: "e", label: "rt_el_named"},
  {op: "mov", dst: "rax", src: "rcx"},
  {op: "add", dst: "rax", src: "r11"},
  {op: "load_byte", dst: "rax", base: "rax"},
  {op: "mov", dst: "r10", src: "r8"},
  {op: "add", dst: "r10", src: "r11"},
  {op: "load_byte", dst: "r10", base: "r10"},
  {op: "cmp", dst: "rax", src: "r10"},
  {op: "j", cond: "ne", label: "rt_el_next"},
  {op: "add", dst: "r11", imm: 1},
  {op: "jmp", label: "rt_el_byte"},
  {op: "label", name: "rt_el_named"},
  {op: "mov", dst: "rax", src: "rcx"},
  {op: "add", dst: "rax", src: "r9"},
  {op: "load_byte", dst: "rdx", base: "rax"},
  {op: "add", dst: "rax", imm: 1},
  {op: "cmp", dst: "rdx", imm: 61},
  {op: "j", cond: "e", label: "rt_el_out"},
  {op: "label", name: "rt_el_next"},
  {op: "add", dst: "rsi", imm: 8},
  {op: "jmp", label: "rt_el_entry"},
  {op: "label", name: "rt_el_out"},
  {op: "ret"}
]

@doc """
env_value: the instructions that, with the address of a NUL-ended value at rbp-24, measure it and make it a string at rbp-40.

    last(env_value("t"))[:disp] #=> -40
"""
def env_value(tag)
  append(
    *[
      [
        {op: "load", dst: "rax", base: "rbp", disp: -24},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "label", name: "#{tag}_len"},
        {op: "mov", dst: "rdx", src: "rax"},
        {op: "add", dst: "rdx", src: "rcx"},
        {op: "load_byte", dst: "rdx", base: "rdx"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_measured"},
        {op: "add", dst: "rcx", imm: 1},
        {op: "jmp", label: "#{tag}_len"},
        {op: "label", name: "#{tag}_measured"},
        {op: "store", src: "rcx", base: "rbp", disp: -32}
      ],
      string_from_buffer(-24, -32, -40, "#{tag}_copy"),
      [{op: "store", src: "rax", base: "rbp", disp: -40}]
    ]
  )
end

@doc """
RT_GETENV: getenv natively: the value of the environment entry named by the string in rdi as a new string, or the default in rsi when there is none; both consumed.

    RT_GETENV[0] #=> {op: "label", name: "rt_getenv"}
"""
RT_GETENV = append(
  *[
    [
      {op: "label", name: "rt_getenv"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -16},
      {op: "store", src: "rsi", base: "rbp", disp: -40},
      {op: "call_label", label: "rt_env_lookup"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_ge_out"},
      {op: "store", src: "rax", base: "rbp", disp: -24}
    ],
    env_value("rt_ge"),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -16},
      {op: "call_label", label: "rt_drop"},
      {op: "label", name: "rt_ge_out"}
    ],
    leave_with(-8, -40)
  ]
)

@doc """
RT_ENV_REQUIRED: env_required natively: the value of the environment entry named by the string in rdi (consumed) as a new string, or an error (ENOENT, -2) when there is none.

    RT_ENV_REQUIRED[0] #=> {op: "label", name: "rt_env_required"}
"""
RT_ENV_REQUIRED = append(
  *[
    [
      {op: "label", name: "rt_env_required"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "call_label", label: "rt_env_lookup"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "ne", label: "rt_er_found"},
      {op: "mov", dst: "rax", imm: -2}
    ],
    error_from("rax"),
    [
      {op: "store", src: "rax", base: "rbp", disp: -40},
      {op: "jmp", label: "rt_er_out"},
      {op: "label", name: "rt_er_found"},
      {op: "store", src: "rax", base: "rbp", disp: -24}
    ],
    env_value("rt_er"),
    [{op: "label", name: "rt_er_out"}],
    leave_with(-8, -40)
  ]
)

@doc """
lookup_programs: programs over getenv and env_required natively, in :show mode, with what each must write: PATH found, an unset name's default, a required unset name raised, and PATH required.

    length(lookup_programs) #=> 4
"""
def lookup_programs()
  [
    ["(string? (getenv \"PATH\" nil))", "true"],
    ["(getenv \"BLUE_SPEC_SURELY_UNSET\" \"d\")", "\"d\""],
    ["(try (env_required \"BLUE_SPEC_SURELY_UNSET\") (catch (e) 7))", "7"],
    ["(string? (env_required \"PATH\"))", "true"]
  ]
end

test "getenv and env_required read the environment natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-env"), "env.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      lookup_programs
    )
  end
end

test "the environment words look an entry up by name and copy its value"
  stand_ins = flat_map(
    %w[rt_alloc rt_drop],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  routines = append(*[RT_ENV_LOOKUP, RT_GETENV, RT_ENV_REQUIRED, stand_ins])
  assert length(assemble(routines)) > 0
  assert last(env_value("t"))[:disp] == -40
  assert HOST_OPS[1] == %w[env_required rt_env_required]
  assert length(ROUTINE_OPS) == 33
  assert last(rc_op([], "getenv", %w[A b])) ==
    {op: "call_label", label: "rt_getenv"}
  assert length(lookup_programs) == 4
end

@doc """
path_bounds: the instructions that read the path string at rbp-8: its bytes' address at rbp-48, the end of its last component (trailing slashes passed over) at rbp-16, and that component's start at rbp-24.

    last(path_bounds("t"))[:disp] #=> -24
"""
def path_bounds(tag)
  [
    {op: "load", dst: "rcx", base: "rbp", disp: -8},
    {op: "load", dst: "rdx", base: "rcx", disp: 24},
    {op: "add", dst: "rcx", imm: 32},
    {op: "store", src: "rcx", base: "rbp", disp: -48},
    {op: "label", name: "#{tag}_trail"},
    {op: "cmp", dst: "rdx", imm: 0},
    {op: "j", cond: "e", label: "#{tag}_ended"},
    {op: "mov", dst: "rax", src: "rcx"},
    {op: "add", dst: "rax", src: "rdx"},
    {op: "sub", dst: "rax", imm: 1},
    {op: "load_byte", dst: "rax", base: "rax"},
    {op: "cmp", dst: "rax", imm: 47},
    {op: "j", cond: "ne", label: "#{tag}_ended"},
    {op: "sub", dst: "rdx", imm: 1},
    {op: "jmp", label: "#{tag}_trail"},
    {op: "label", name: "#{tag}_ended"},
    {op: "store", src: "rdx", base: "rbp", disp: -16},
    {op: "label", name: "#{tag}_start"},
    {op: "cmp", dst: "rdx", imm: 0},
    {op: "j", cond: "e", label: "#{tag}_started"},
    {op: "mov", dst: "rax", src: "rcx"},
    {op: "add", dst: "rax", src: "rdx"},
    {op: "sub", dst: "rax", imm: 1},
    {op: "load_byte", dst: "rax", base: "rax"},
    {op: "cmp", dst: "rax", imm: 47},
    {op: "j", cond: "e", label: "#{tag}_started"},
    {op: "sub", dst: "rdx", imm: 1},
    {op: "jmp", label: "#{tag}_start"},
    {op: "label", name: "#{tag}_started"},
    {op: "store", src: "rdx", base: "rbp", disp: -24}
  ]
end

@doc """
path_part: the instructions that make the bytes from the index at rbp+from to the index at rbp+to of the path at rbp-8 a new string at rbp-40, then drop the path.

    last(path_part("t", -24, -16))[:op] #=> "call_label"
"""
def path_part(tag, from, to)
  append(
    *[
      [
        {op: "load", dst: "rcx", base: "rbp", disp: from},
        {op: "load", dst: "rdx", base: "rbp", disp: to},
        {op: "sub", dst: "rdx", src: "rcx"},
        {op: "store", src: "rdx", base: "rbp", disp: -32},
        {op: "load", dst: "rax", base: "rbp", disp: -48},
        {op: "add", dst: "rax", src: "rcx"},
        {op: "store", src: "rax", base: "rbp", disp: -56}
      ],
      string_from_buffer(-56, -32, -40, "#{tag}_copy"),
      [
        {op: "load", dst: "rdi", base: "rbp", disp: -8},
        {op: "call_label", label: "rt_drop"}
      ]
    ]
  )
end

@doc """
path_routine: a routine over one path string in rdi (consumed): its frame, path_bounds, the body, and the string at rbp-40 answered.

    path_routine("rt_x", [])[0] #=> {op: "label", name: "rt_x"}
"""
def path_routine(name, body)
  append(
    *[
      [
        {op: "label", name:},
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sub", dst: "rsp", imm: 64},
        {op: "store", src: "rdi", base: "rbp", disp: -8}
      ],
      path_bounds(name),
      body,
      [
        {op: "load", dst: "rax", base: "rbp", disp: -40},
        {op: "mov", dst: "rsp", src: "rbp"},
        {op: "pop_rbp"},
        {op: "ret"}
      ]
    ]
  )
end

@doc """
RT_PATH_BASENAME: path_basename natively: the last component of the path, trailing slashes passed over.

    RT_PATH_BASENAME[0] #=> {op: "label", name: "rt_path_basename"}
"""
RT_PATH_BASENAME = path_routine(
  "rt_path_basename",
  path_part("rt_pb", -24, -16)
)

@doc """
RT_PATH_DIRNAME: path_dirname natively: everything before the last component, its own trailing slashes passed over; "/" for a component at the root, "" for a lone one.

    RT_PATH_DIRNAME[0] #=> {op: "label", name: "rt_path_dirname"}
"""
RT_PATH_DIRNAME = path_routine(
  "rt_path_dirname",
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -64},
        {op: "load", dst: "rdx", base: "rbp", disp: -24},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "rt_pd_cut"},
        {op: "load", dst: "rcx", base: "rbp", disp: -48},
        {op: "label", name: "rt_pd_trail"},
        {op: "cmp", dst: "rdx", imm: 1},
        {op: "j", cond: "e", label: "rt_pd_cut"},
        {op: "mov", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", src: "rdx"},
        {op: "sub", dst: "rax", imm: 2},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "cmp", dst: "rax", imm: 47},
        {op: "j", cond: "ne", label: "rt_pd_slash"},
        {op: "sub", dst: "rdx", imm: 1},
        {op: "jmp", label: "rt_pd_trail"},
        {op: "label", name: "rt_pd_slash"},
        {op: "sub", dst: "rdx", imm: 1},
        {op: "label", name: "rt_pd_cut"},
        {op: "store", src: "rdx", base: "rbp", disp: -16}
      ],
      path_part("rt_pd", -64, -16)
    ]
  )
)

@doc """
RT_PATH_EXTENSION: path_extension natively: what follows the last dot of the last component, "" when it has none or its only dot leads it.

    RT_PATH_EXTENSION[0] #=> {op: "label", name: "rt_path_extension"}
"""
RT_PATH_EXTENSION = path_routine(
  "rt_path_extension",
  append(
    *[
      [
        {op: "load", dst: "rcx", base: "rbp", disp: -48},
        {op: "load", dst: "rdx", base: "rbp", disp: -16},
        {op: "label", name: "rt_px_dot"},
        {op: "load", dst: "rax", base: "rbp", disp: -24},
        {op: "add", dst: "rax", imm: 1},
        {op: "cmp", dst: "rdx", src: "rax"},
        {op: "j", cond: "l", label: "rt_px_none"},
        {op: "mov", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", src: "rdx"},
        {op: "sub", dst: "rax", imm: 1},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "cmp", dst: "rax", imm: 46},
        {op: "j", cond: "e", label: "rt_px_found"},
        {op: "sub", dst: "rdx", imm: 1},
        {op: "jmp", label: "rt_px_dot"},
        {op: "label", name: "rt_px_found"},
        {op: "load", dst: "rax", base: "rbp", disp: -24},
        {op: "add", dst: "rax", imm: 1},
        {op: "cmp", dst: "rdx", src: "rax"},
        {op: "j", cond: "g", label: "rt_px_at"},
        {op: "label", name: "rt_px_none"},
        {op: "load", dst: "rdx", base: "rbp", disp: -16},
        {op: "label", name: "rt_px_at"},
        {op: "store", src: "rdx", base: "rbp", disp: -24}
      ],
      path_part("rt_px", -24, -16)
    ]
  )
)

@doc """
RT_PATH_JOIN: path_join of two parts natively (bare_calls nests more): the second when it is absolute or the first is empty, else the two with one slash between, as blue joins them; both consumed.

    RT_PATH_JOIN[0] #=> {op: "label", name: "rt_path_join"}
"""
RT_PATH_JOIN = [
  {op: "label", name: "rt_path_join"},
  {op: "push_rbp"},
  {op: "mov", dst: "rbp", src: "rsp"},
  {op: "sub", dst: "rsp", imm: 32},
  {op: "store", src: "rdi", base: "rbp", disp: -8},
  {op: "store", src: "rsi", base: "rbp", disp: -16},
  {op: "load", dst: "rcx", base: "rsi", disp: 24},
  {op: "cmp", dst: "rcx", imm: 0},
  {op: "j", cond: "e", label: "rt_pj_relative"},
  {op: "mov", dst: "rax", src: "rsi"},
  {op: "add", dst: "rax", imm: 32},
  {op: "load_byte", dst: "rax", base: "rax"},
  {op: "cmp", dst: "rax", imm: 47},
  {op: "j", cond: "e", label: "rt_pj_second"},
  {op: "label", name: "rt_pj_relative"},
  {op: "load", dst: "rcx", base: "rdi", disp: 24},
  {op: "cmp", dst: "rcx", imm: 0},
  {op: "j", cond: "e", label: "rt_pj_second"},
  {op: "mov", dst: "rax", src: "rdi"},
  {op: "add", dst: "rax", imm: 31},
  {op: "add", dst: "rax", src: "rcx"},
  {op: "load_byte", dst: "rax", base: "rax"},
  {op: "cmp", dst: "rax", imm: 47},
  {op: "j", cond: "e", label: "rt_pj_concat"},
  {op: "mov", dst: "rdi", imm: 5},
  {op: "call_label", label: "rt_alloc"},
  {op: "mov", dst: "rcx", imm: 1},
  {op: "store", src: "rcx", base: "rax", disp: 0},
  {op: "store", src: "rcx", base: "rax", disp: 24},
  {op: "mov", dst: "rcx", imm: 47},
  {op: "store", src: "rcx", base: "rax", disp: 32},
  {op: "mov", dst: "rsi", src: "rax"},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "call_label", label: "rt_concat"},
  {op: "store", src: "rax", base: "rbp", disp: -8},
  {op: "label", name: "rt_pj_concat"},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "load", dst: "rsi", base: "rbp", disp: -16},
  {op: "call_label", label: "rt_concat"},
  {op: "jmp", label: "rt_pj_out"},
  {op: "label", name: "rt_pj_second"},
  {op: "call_label", label: "rt_drop"},
  {op: "load", dst: "rax", base: "rbp", disp: -16},
  {op: "label", name: "rt_pj_out"},
  {op: "mov", dst: "rsp", src: "rbp"},
  {op: "pop_rbp"},
  {op: "ret"}
]

@doc """
path_programs: programs over the path words natively, in :show mode, with what each must write, as blue answers them.

    length(path_programs) #=> 12
"""
def path_programs()
  [
    ["(path_join \"a\" \"b\" \"c.b\")", "\"a/b/c.b\""],
    ["(path_join \"a\" \"/b\")", "\"/b\""],
    ["(path_join \"a/\" \"b\")", "\"a/b\""],
    ["(path_join \"\" \"b\")", "\"b\""],
    ["(path_join \"a\" \"\")", "\"a/\""],
    ["(path_basename \"/x/y.b\")", "\"y.b\""],
    ["(path_basename \"/x/\")", "\"x\""],
    ["(path_dirname \"/x/y.b\")", "\"/x\""],
    ["(path_dirname \"y\")", "\"\""],
    ["(path_dirname \"/y\")", "\"/\""],
    ["(path_extension \"a.tar.gz\")", "\"gz\""],
    ["(path_extension \".bashrc\")", "\"\""]
  ]
end

test "the path words answer as blue does, natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-path"), "path.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      path_programs
    )
  end
end

test "the path words share one reading of the last component, and path_join nests"
  stand_ins = flat_map(
    %w[rt_alloc rt_drop rt_concat],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  routines = append(
    *[
      RT_PATH_JOIN,
      RT_PATH_BASENAME,
      RT_PATH_DIRNAME,
      RT_PATH_EXTENSION,
      stand_ins
    ]
  )
  assert length(assemble(routines)) > 0
  assert last(path_bounds("t"))[:disp] == -24
  assert last(path_part("t", -24, -16))[:op] == "call_label"
  assert path_routine("rt_x", [])[0] == {op: "label", name: "rt_x"}
  assert bare_calls(read_forms("(path_join a b c)")[0]) ==
    read_forms("(path_join (path_join a b) c)")[0]
  assert length(path_programs) == 12
end

@doc """
path_call: a routine over one path string in rdi (consumed): the path made a NUL-ended copy on the stack, the system call nr with that copy in rdi and extra (pairs of register and immediate) in the rest, its return at rbp-16; then answer, which leaves the routine's answer at rbp-24 from the return in rax. Its frame keeps 144 bytes at rbp-176 for a stat.

    path_call("rt_x", 87, [], [])[0] #=> {op: "label", name: "rt_x"}
"""
def path_call(name, nr, extra, answer)
  append(
    *[
      [
        {op: "label", name:},
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sub", dst: "rsp", imm: 192},
        {op: "store", src: "rdi", base: "rbp", disp: -8}
      ],
      path_on_stack("#{name}_path"),
      [{op: "mov", dst: "rdi", src: "rsp"}],
      map((e) -> e, extra),
      [
        {op: "mov", dst: "rax", imm: nr},
        {op: "syscall"},
        {op: "add", dst: "rsp", src: "r9"},
        {op: "store", src: "rax", base: "rbp", disp: -16}
      ],
      answer,
      leave_with(-8, -24)
    ]
  )
end

@doc """
nil_or_error: an answer for path_call: nil when the call returned 0 (or the errno in ok, negated, such as EEXIST for mkdir), else an error carrying the errno.

    last(nil_or_error("t", 0))[:op] #=> "label"
"""
def nil_or_error(tag, ok)
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -24},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_ok"},
        {op: "cmp", dst: "rax", imm: ok},
        {op: "j", cond: "e", label: "#{tag}_ok"}
      ],
      error_from("rax"),
      [
        {op: "store", src: "rax", base: "rbp", disp: -24},
        {op: "label", name: "#{tag}_ok"}
      ]
    ]
  )
end

@doc """
STAT_AT: where path_call's frame keeps the stat a stat-reading word fills.

    STAT_AT #=> -176
"""
STAT_AT = -176

@doc """
stat_extra: the second argument of stat(2), the buffer at STAT_AT.

    stat_extra[0][:dst] #=> "rsi"
"""
def stat_extra()
  [{op: "mov", dst: "rsi", src: "rbp"}, {op: "add", dst: "rsi", imm: STAT_AT}]
end

@doc """
mode_is: an answer for a stat: true when the call succeeded and the file type bits of st_mode equal kind (0o040000 a directory, 0o100000 a regular file, 0 for anything at all).

    length(mode_is("t", 0)) #=> 11
"""
def mode_is(tag, kind)
  mask = if kind == 0
    0
  else
    61440
  end
  [
    {op: "mov", dst: "rcx", imm: FALSE},
    {op: "store", src: "rcx", base: "rbp", disp: -24},
    {op: "cmp", dst: "rax", imm: 0},
    {op: "j", cond: "ne", label: "#{tag}_no"},
    {op: "load", dst: "rax", base: "rbp", disp: STAT_AT + 24},
    {op: "and", dst: "rax", imm: mask},
    {op: "cmp", dst: "rax", imm: kind},
    {op: "j", cond: "ne", label: "#{tag}_no"},
    {op: "mov", dst: "rcx", imm: 2},
    {op: "store", src: "rcx", base: "rbp", disp: -24},
    {op: "label", name: "#{tag}_no"}
  ]
end

@doc """
stat_number: an answer for a stat: the tagged number the instructions in read leave in rax from the stat, or an error carrying the errno when the stat failed.

    last(stat_number("t", []))[:name] #=> "t_done"
"""
def stat_number(tag, read)
  append(
    *[
      [
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "#{tag}_read"}
      ],
      error_from("rax"),
      [
        {op: "store", src: "rax", base: "rbp", disp: -24},
        {op: "jmp", label: "#{tag}_done"},
        {op: "label", name: "#{tag}_read"}
      ],
      read,
      [
        {op: "mov", dst: "rcx", src: "rax"},
        {op: "add", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", imm: 1},
        {op: "store", src: "rax", base: "rbp", disp: -24},
        {op: "label", name: "#{tag}_done"}
      ]
    ]
  )
end

@doc """
MTIME_MS: the instructions that read st_mtime from the stat as Unix milliseconds in rax.

    length(MTIME_MS) #=> 10
"""
MTIME_MS = [
  {op: "load", dst: "rax", base: "rbp", disp: STAT_AT + 96},
  {op: "cqo"},
  {op: "mov", dst: "rcx", imm: 1_000_000},
  {op: "idiv", src: "rcx"},
  {op: "mov", dst: "r8", src: "rax"},
  {op: "load", dst: "rax", base: "rbp", disp: STAT_AT + 88},
  {op: "mov", dst: "rcx", imm: 1000},
  {op: "imul", dst: "rax", src: "rcx"},
  {op: "add", dst: "rax", src: "r8"},
  {op: "mov", dst: "rcx", src: "rax"}
]

@doc """
open_write: a routine writing the string in rsi (consumed) to the path in rdi (consumed), opened with flags (created 0o644): nil, or an error carrying the errno when it does not open.

    open_write("rt_x", 577)[0] #=> {op: "label", name: "rt_x"}
"""
def open_write(name, flags)
  append(
    *[
      [
        {op: "label", name:},
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sub", dst: "rsp", imm: 48},
        {op: "store", src: "rdi", base: "rbp", disp: -8},
        {op: "store", src: "rsi", base: "rbp", disp: -32},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -24}
      ],
      path_on_stack("#{name}_path"),
      [
        {op: "mov", dst: "rdi", src: "rsp"},
        {op: "mov", dst: "rsi", imm: flags},
        {op: "mov", dst: "rdx", imm: 420},
        {op: "mov", dst: "rax", imm: 2},
        {op: "syscall"},
        {op: "add", dst: "rsp", src: "r9"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "ge", label: "#{name}_opened"}
      ],
      error_from("rax"),
      [
        {op: "store", src: "rax", base: "rbp", disp: -24},
        {op: "jmp", label: "#{name}_out"},
        {op: "label", name: "#{name}_opened"},
        {op: "store", src: "rax", base: "rbp", disp: -16},
        {op: "mov", dst: "r8", imm: 0},
        {op: "label", name: "#{name}_more"},
        {op: "load", dst: "rsi", base: "rbp", disp: -32},
        {op: "load", dst: "rdx", base: "rsi", disp: 24},
        {op: "sub", dst: "rdx", src: "r8"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "le", label: "#{name}_close"},
        {op: "add", dst: "rsi", imm: 32},
        {op: "add", dst: "rsi", src: "r8"},
        {op: "load", dst: "rdi", base: "rbp", disp: -16},
        {op: "store", src: "r8", base: "rbp", disp: -40},
        {op: "mov", dst: "rax", imm: 1},
        {op: "syscall"},
        {op: "load", dst: "r8", base: "rbp", disp: -40},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "le", label: "#{name}_close"},
        {op: "add", dst: "r8", src: "rax"},
        {op: "jmp", label: "#{name}_more"},
        {op: "label", name: "#{name}_close"},
        {op: "load", dst: "rdi", base: "rbp", disp: -16},
        {op: "mov", dst: "rax", imm: 3},
        {op: "syscall"},
        {op: "label", name: "#{name}_out"},
        {op: "load", dst: "rdi", base: "rbp", disp: -32},
        {op: "call_label", label: "rt_drop"}
      ],
      leave_with(-8, -24)
    ]
  )
end

@doc """
RT_MKDIR_P: mkdir_p natively: the path in rdi (consumed) copied to the stack with a NUL ending, each prefix ending at a slash made a directory in turn and then the whole, an existing one passed by; nil, or an error carrying the errno of the first that fails otherwise.

    RT_MKDIR_P[0] #=> {op: "label", name: "rt_mkdir_p"}
"""
RT_MKDIR_P = append(
  *[
    [
      {op: "label", name: "rt_mkdir_p"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rdi", disp: 24},
      {op: "store", src: "rcx", base: "rbp", disp: -32}
    ],
    path_on_stack("rt_mp_path"),
    [
      {op: "store", src: "r9", base: "rbp", disp: -40},
      {op: "mov", dst: "r8", imm: 1},
      {op: "label", name: "rt_mp_scan"},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "cmp", dst: "r8", src: "rcx"},
      {op: "j", cond: "ge", label: "rt_mp_last"},
      {op: "mov", dst: "rax", src: "rsp"},
      {op: "add", dst: "rax", src: "r8"},
      {op: "load_byte", dst: "rcx", base: "rax"},
      {op: "cmp", dst: "rcx", imm: 47},
      {op: "j", cond: "ne", label: "rt_mp_next"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store_byte", src: "rcx", base: "rax"},
      {op: "store", src: "r8", base: "rbp", disp: -48},
      {op: "mov", dst: "rdi", src: "rsp"},
      {op: "mov", dst: "rsi", imm: 511},
      {op: "mov", dst: "rax", imm: 83},
      {op: "syscall"},
      {op: "load", dst: "r8", base: "rbp", disp: -48},
      {op: "mov", dst: "rcx", src: "rsp"},
      {op: "add", dst: "rcx", src: "r8"},
      {op: "mov", dst: "rdx", imm: 47},
      {op: "store_byte", src: "rdx", base: "rcx"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_mp_next"},
      {op: "cmp", dst: "rax", imm: -17},
      {op: "j", cond: "ne", label: "rt_mp_bad"},
      {op: "label", name: "rt_mp_next"},
      {op: "add", dst: "r8", imm: 1},
      {op: "jmp", label: "rt_mp_scan"},
      {op: "label", name: "rt_mp_last"},
      {op: "mov", dst: "rdi", src: "rsp"},
      {op: "mov", dst: "rsi", imm: 511},
      {op: "mov", dst: "rax", imm: 83},
      {op: "syscall"},
      {op: "cmp", dst: "rax", imm: 0},
      {op: "j", cond: "e", label: "rt_mp_done"},
      {op: "cmp", dst: "rax", imm: -17},
      {op: "j", cond: "e", label: "rt_mp_done"},
      {op: "label", name: "rt_mp_bad"}
    ],
    error_from("rax"),
    [
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "label", name: "rt_mp_done"},
      {op: "load", dst: "r9", base: "rbp", disp: -40},
      {op: "add", dst: "rsp", src: "r9"}
    ],
    leave_with(-8, -24)
  ]
)

@doc """
RT_RENAME_FILE: rename_file natively: the path in rdi renamed to the path in rsi (both consumed) by rename(2), atomic on one filesystem; nil, or an error carrying the errno.

    RT_RENAME_FILE[0] #=> {op: "label", name: "rt_rename_file"}
"""
RT_RENAME_FILE = append(
  *[
    [
      {op: "label", name: "rt_rename_file"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8},
      {op: "store", src: "rsi", base: "rbp", disp: -32}
    ],
    path_on_stack("rt_rn_from"),
    [
      {op: "store", src: "rsp", base: "rbp", disp: -40},
      {op: "store", src: "r9", base: "rbp", disp: -48},
      {op: "load", dst: "rdi", base: "rbp", disp: -32}
    ],
    path_on_stack("rt_rn_to"),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -40},
      {op: "mov", dst: "rsi", src: "rsp"},
      {op: "mov", dst: "rax", imm: 82},
      {op: "syscall"},
      {op: "add", dst: "rsp", src: "r9"},
      {op: "load", dst: "r9", base: "rbp", disp: -48},
      {op: "add", dst: "rsp", src: "r9"},
      {op: "store", src: "rax", base: "rbp", disp: -16}
    ],
    nil_or_error("rt_rn", 0),
    [
      {op: "load", dst: "rdi", base: "rbp", disp: -32},
      {op: "call_label", label: "rt_drop"}
    ],
    leave_with(-8, -24)
  ]
)

@doc """
RT_RM_TREE: the entry named by the NUL-ended name at rsi in the directory open as rdi removed, and, when it is a directory, everything in it first: unlinkat, else openat, getdents64 over its entries (passing . and ..) each removed in turn, close, and unlinkat as a directory. rax is 0, or the negated errno of the step that failed; an absent entry is 0.

    RT_RM_TREE[0] #=> {op: "label", name: "rt_rm_tree"}
"""
RT_RM_TREE = [
  {op: "label", name: "rt_rm_tree"},
  {op: "push_rbp"},
  {op: "mov", dst: "rbp", src: "rsp"},
  {op: "sub", dst: "rsp", imm: 4160},
  {op: "store", src: "rdi", base: "rbp", disp: -8},
  {op: "store", src: "rsi", base: "rbp", disp: -16},
  {op: "mov", dst: "rdx", imm: 0},
  {op: "mov", dst: "rax", imm: 263},
  {op: "syscall"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "e", label: "rt_rt_out"},
  {op: "cmp", dst: "rax", imm: -2},
  {op: "j", cond: "e", label: "rt_rt_gone"},
  {op: "cmp", dst: "rax", imm: -21},
  {op: "j", cond: "e", label: "rt_rt_dir"},
  {op: "cmp", dst: "rax", imm: -1},
  {op: "j", cond: "ne", label: "rt_rt_out"},
  {op: "label", name: "rt_rt_dir"},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "load", dst: "rsi", base: "rbp", disp: -16},
  {op: "mov", dst: "rdx", imm: 589_824},
  {op: "mov", dst: "rax", imm: 257},
  {op: "syscall"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "l", label: "rt_rt_out"},
  {op: "store", src: "rax", base: "rbp", disp: -24},
  {op: "label", name: "rt_rt_read"},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rsi", src: "rbp"},
  {op: "add", dst: "rsi", imm: -4160},
  {op: "mov", dst: "rdx", imm: 4096},
  {op: "mov", dst: "rax", imm: 217},
  {op: "syscall"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "le", label: "rt_rt_closed"},
  {op: "store", src: "rax", base: "rbp", disp: -32},
  {op: "mov", dst: "rcx", imm: 0},
  {op: "label", name: "rt_rt_entry"},
  {op: "load", dst: "rax", base: "rbp", disp: -32},
  {op: "cmp", dst: "rcx", src: "rax"},
  {op: "j", cond: "ge", label: "rt_rt_read"},
  {op: "store", src: "rcx", base: "rbp", disp: -40},
  {op: "mov", dst: "rsi", src: "rbp"},
  {op: "add", dst: "rsi", imm: -4160},
  {op: "add", dst: "rsi", src: "rcx"},
  {op: "mov", dst: "rax", src: "rsi"},
  {op: "add", dst: "rax", imm: 16},
  {op: "load_byte", dst: "rdx", base: "rax"},
  {op: "add", dst: "rsi", imm: 19},
  {op: "load_byte", dst: "rax", base: "rsi"},
  {op: "cmp", dst: "rax", imm: 46},
  {op: "j", cond: "ne", label: "rt_rt_remove"},
  {op: "mov", dst: "rax", src: "rsi"},
  {op: "add", dst: "rax", imm: 1},
  {op: "load_byte", dst: "rax", base: "rax"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "e", label: "rt_rt_skip"},
  {op: "cmp", dst: "rax", imm: 46},
  {op: "j", cond: "ne", label: "rt_rt_remove"},
  {op: "mov", dst: "rax", src: "rsi"},
  {op: "add", dst: "rax", imm: 2},
  {op: "load_byte", dst: "rax", base: "rax"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "e", label: "rt_rt_skip"},
  {op: "label", name: "rt_rt_remove"},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "call_label", label: "rt_rm_tree"},
  {op: "cmp", dst: "rax", imm: 0},
  {op: "j", cond: "ne", label: "rt_rt_close_fail"},
  {op: "label", name: "rt_rt_skip"},
  {op: "load", dst: "rcx", base: "rbp", disp: -40},
  {op: "mov", dst: "rax", src: "rbp"},
  {op: "add", dst: "rax", imm: -4160},
  {op: "add", dst: "rax", src: "rcx"},
  {op: "add", dst: "rax", imm: 16},
  {op: "load_byte", dst: "rdx", base: "rax"},
  {op: "add", dst: "rax", imm: 1},
  {op: "load_byte", dst: "rax", base: "rax"},
  {op: "mov", dst: "r8", imm: 256},
  {op: "imul", dst: "rax", src: "r8"},
  {op: "add", dst: "rax", src: "rdx"},
  {op: "add", dst: "rcx", src: "rax"},
  {op: "jmp", label: "rt_rt_entry"},
  {op: "label", name: "rt_rt_close_fail"},
  {op: "store", src: "rax", base: "rbp", disp: -32},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rax", imm: 3},
  {op: "syscall"},
  {op: "load", dst: "rax", base: "rbp", disp: -32},
  {op: "jmp", label: "rt_rt_out"},
  {op: "label", name: "rt_rt_closed"},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rax", imm: 3},
  {op: "syscall"},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "load", dst: "rsi", base: "rbp", disp: -16},
  {op: "mov", dst: "rdx", imm: 512},
  {op: "mov", dst: "rax", imm: 263},
  {op: "syscall"},
  {op: "jmp", label: "rt_rt_out"},
  {op: "label", name: "rt_rt_gone"},
  {op: "mov", dst: "rax", imm: 0},
  {op: "label", name: "rt_rt_out"},
  {op: "mov", dst: "rsp", src: "rbp"},
  {op: "pop_rbp"},
  {op: "ret"}
]

@doc """
RT_READ_BYTES: read_bytes natively (the one-argument form): the file at the path in rdi (consumed) read with rt_read_file, then its bytes as a list of numbers built from the last back; the error when it cannot be read.

    RT_READ_BYTES[0] #=> {op: "label", name: "rt_read_bytes"}
"""
RT_READ_BYTES = append(
  *[
    [
      {op: "label", name: "rt_read_bytes"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "call_label", label: "rt_read_file"},
      {op: "store", src: "rax", base: "rbp", disp: -8},
      {op: "store", src: "rax", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rax", disp: 0},
      {op: "cmp", dst: "rcx", imm: 4},
      {op: "j", cond: "e", label: "rt_rb_raise"},
      {op: "mov", dst: "rcx", imm: 0},
      {op: "store", src: "rcx", base: "rbp", disp: -24},
      {op: "load", dst: "rcx", base: "rax", disp: 24},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "label", name: "rt_rb_byte"},
      {op: "load", dst: "rcx", base: "rbp", disp: -32},
      {op: "cmp", dst: "rcx", imm: 0},
      {op: "j", cond: "e", label: "rt_rb_out"},
      {op: "sub", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -32},
      {op: "load", dst: "rdx", base: "rbp", disp: -8},
      {op: "add", dst: "rdx", imm: 32},
      {op: "add", dst: "rdx", src: "rcx"},
      {op: "load_byte", dst: "rcx", base: "rdx"},
      {op: "mov", dst: "rdx", src: "rcx"},
      {op: "add", dst: "rcx", src: "rdx"},
      {op: "add", dst: "rcx", imm: 1},
      {op: "store", src: "rcx", base: "rbp", disp: -40}
    ],
    cell(-40, -24, -24),
    [{op: "jmp", label: "rt_rb_byte"}, {op: "label", name: "rt_rb_out"}],
    leave_with(-8, -24),
    [
      {op: "label", name: "rt_rb_raise"},
      {op: "load", dst: "rax", base: "rbp", disp: -24},
      {op: "mov", dst: "rsp", src: "rbp"},
      {op: "pop_rbp"},
      {op: "ret"}
    ]
  ]
)

@doc """
RT_RM_RF: rm_rf natively: the path in rdi (consumed) removed with everything under it, through rt_rm_tree from the working directory (AT_FDCWD); nil, also when there is nothing, or an error carrying the errno.

    RT_RM_RF[0] #=> {op: "label", name: "rt_rm_rf"}
"""
RT_RM_RF = append(
  *[
    [
      {op: "label", name: "rt_rm_rf"},
      {op: "push_rbp"},
      {op: "mov", dst: "rbp", src: "rsp"},
      {op: "sub", dst: "rsp", imm: 48},
      {op: "store", src: "rdi", base: "rbp", disp: -8}
    ],
    path_on_stack("rt_rr_path"),
    [
      {op: "store", src: "r9", base: "rbp", disp: -40},
      {op: "mov", dst: "rdi", imm: -100},
      {op: "mov", dst: "rsi", src: "rsp"},
      {op: "call_label", label: "rt_rm_tree"},
      {op: "load", dst: "r9", base: "rbp", disp: -40},
      {op: "add", dst: "rsp", src: "r9"},
      {op: "store", src: "rax", base: "rbp", disp: -16}
    ],
    nil_or_error("rt_rr", 0),
    leave_with(-8, -24)
  ]
)

@doc """
FS_ROUTINES: the filesystem words natively, each one routine: mkdir, mkdir_p, rm, rm_rf (over rt_rm_tree), rename_file, the stat words path_exists, is_dir?, is_file?, file_size and file_mtime_ms, write_file, append_file, and read_bytes.

    FS_ROUTINES[0] #=> {op: "label", name: "rt_mkdir"}
"""
FS_ROUTINES = append(
  *[
    path_call(
      "rt_mkdir",
      83,
      [{op: "mov", dst: "rsi", imm: 511}],
      nil_or_error("rt_md", -17)
    ),
    RT_MKDIR_P,
    path_call("rt_rm", 87, [], nil_or_error("rt_ul", 0)),
    RT_RM_TREE,
    RT_RM_RF,
    RT_RENAME_FILE,
    path_call("rt_path_exists", 4, stat_extra, mode_is("rt_pe", 0)),
    path_call("rt_is_dir", 4, stat_extra, mode_is("rt_id", 16384)),
    path_call("rt_is_file", 4, stat_extra, mode_is("rt_if", 32768)),
    path_call(
      "rt_file_size",
      4,
      stat_extra,
      stat_number(
        "rt_fs",
        [{op: "load", dst: "rax", base: "rbp", disp: STAT_AT + 48}]
      )
    ),
    path_call(
      "rt_file_mtime_ms",
      4,
      stat_extra,
      stat_number("rt_fm", MTIME_MS)
    ),
    open_write("rt_write_file", 577),
    open_write("rt_append_file", 1089),
    RT_READ_BYTES
  ]
)

@doc """
fs_programs: programs over the filesystem words natively, in :show mode, under a directory of the program's own, with what each must write.

    length(fs_programs) #=> 6
"""
def fs_programs()
  d = "(path_join (getenv \"TMPDIR\" \"/tmp\") \"hashiru-fs\")"
  [
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p (path_join d \"x/y\")) (write_file (path_join d \"x/y/a.txt\") \"one\") (append_file (path_join d \"x/y/a.txt\") \" two\") (let ((r (read_file (path_join d \"x/y/a.txt\")))) (begin (rm_rf d) r))))",
      "\"one two\""
    ],
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p d) (write_file (path_join d \"f\") \"abc\") (let ((r (list (path_exists d) (is_dir? d) (is_file? d) (is_file? (path_join d \"f\")) (file_size (path_join d \"f\")) (integer? (file_mtime_ms (path_join d \"f\")))))) (begin (rm_rf d) r))))",
      "[true, true, false, true, 3, true]"
    ],
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p d) (write_file (path_join d \"a\") \"z\") (rename_file (path_join d \"a\") (path_join d \"b\")) (let ((r (list (path_exists (path_join d \"a\")) (path_exists (path_join d \"b\"))))) (begin (rm (path_join d \"b\")) (let ((s (path_exists (path_join d \"b\")))) (begin (rm_rf d) (list r s)))))))",
      "[[false, true], false]"
    ],
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p d) (write_file (path_join d \"b\") \"AB\") (let ((r (read_bytes (path_join d \"b\")))) (begin (rm_rf d) r))))",
      "[65, 66]"
    ],
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir d) (let ((r (try (rm (path_join d \"none\")) (catch (e) 7)))) (begin (rm_rf d) (list r (path_exists d))))))",
      "[7, false]"
    ],
    ["(rm_rf \"/nonexistent/hashiru-none\")", "nil"]
  ]
end

test "the filesystem words work natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-fs-run"), "fs.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      fs_programs
    )
  end
end

test "the filesystem routines assemble, and a field call of a predicate becomes the predicate"
  stand_ins = flat_map(
    %w[rt_alloc rt_drop rt_read_file],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(assemble(append(FS_ROUTINES, stand_ins))) > 0
  assert path_call("rt_x", 87, [], [])[0] == {op: "label", name: "rt_x"}
  assert last(nil_or_error("t", 0))[:op] == "label"
  assert STAT_AT == -176
  assert stat_extra[0][:dst] == "rsi"
  assert length(mode_is("t", 0)) == 11
  assert last(stat_number("t", []))[:name] == "t_done"
  assert length(MTIME_MS) == 10
  assert open_write("rt_x", 577)[0] == {op: "label", name: "rt_x"}
  assert RT_MKDIR_P[0] == {op: "label", name: "rt_mkdir_p"}
  assert RT_RENAME_FILE[0] == {op: "label", name: "rt_rename_file"}
  assert RT_RM_TREE[0] == {op: "label", name: "rt_rm_tree"}
  assert RT_READ_BYTES[0] == {op: "label", name: "rt_read_bytes"}
  assert RT_RM_RF[0] == {op: "label", name: "rt_rm_rf"}
  assert bare_calls(read_forms("(blue-field x :nil?)")[0]) ==
    read_forms("(nil? x)")[0]
  assert length(fs_programs) == 6
end

@doc """
ARGV_AT: where the program keeps the address of the argument vector the kernel passed at entry, as an offset from r14: the word after the environment pointer.

    ARGV_AT #=> 520
"""
ARGV_AT = ENVP_AT + 8

@doc """
save_argv: the instructions that keep the address of argv[0] (rbp + 16 at entry) at r14 + ARGV_AT.

    last(save_argv)[:disp] #=> ARGV_AT
"""
def save_argv()
  [
    {op: "mov", dst: "rcx", src: "rbp"},
    {op: "add", dst: "rcx", imm: 16},
    {op: "store", src: "rcx", base: "r14", disp: ARGV_AT}
  ]
end

@doc """
frame_routine: a routine with a frame of size bytes around body, answering the word at rbp-40.

    frame_routine("rt_x", 48, [])[0] #=> {op: "label", name: "rt_x"}
"""
def frame_routine(name, size, body)
  append(
    *[
      [
        {op: "label", name:},
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sub", dst: "rsp", imm: size}
      ],
      body,
      [
        {op: "load", dst: "rax", base: "rbp", disp: -40},
        {op: "mov", dst: "rsp", src: "rbp"},
        {op: "pop_rbp"},
        {op: "ret"}
      ]
    ]
  )
end

@doc """
RT_ARGV: argv natively: the program's own arguments, argv[1] on, as a list of strings, built from the last back.

    RT_ARGV[0] #=> {op: "label", name: "rt_argv"}
"""
RT_ARGV = frame_routine(
  "rt_argv",
  64,
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -48},
        {op: "load", dst: "rsi", base: "r14", disp: ARGV_AT},
        {op: "mov", dst: "rcx", imm: 1},
        {op: "label", name: "rt_av_count"},
        {op: "mov", dst: "rax", src: "rcx"}
      ],
      times8("rax"),
      [
        {op: "add", dst: "rax", src: "rsi"},
        {op: "load", dst: "rax", base: "rax", disp: 0},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "rt_av_counted"},
        {op: "add", dst: "rcx", imm: 1},
        {op: "jmp", label: "rt_av_count"},
        {op: "label", name: "rt_av_counted"},
        {op: "store", src: "rcx", base: "rbp", disp: -56},
        {op: "label", name: "rt_av_next"},
        {op: "load", dst: "rcx", base: "rbp", disp: -56},
        {op: "sub", dst: "rcx", imm: 1},
        {op: "cmp", dst: "rcx", imm: 1},
        {op: "j", cond: "l", label: "rt_av_done"},
        {op: "store", src: "rcx", base: "rbp", disp: -56},
        {op: "load", dst: "rax", base: "r14", disp: ARGV_AT}
      ],
      times8("rcx"),
      [
        {op: "add", dst: "rax", src: "rcx"},
        {op: "load", dst: "rax", base: "rax", disp: 0},
        {op: "store", src: "rax", base: "rbp", disp: -24}
      ],
      env_value("rt_av"),
      cell(-40, -48, -48),
      [{op: "jmp", label: "rt_av_next"}, {op: "label", name: "rt_av_done"}],
      empty_when_none(-48),
      [
        {op: "load", dst: "rax", base: "rbp", disp: -48},
        {op: "store", src: "rax", base: "rbp", disp: -40}
      ]
    ]
  )
)

@doc """
RT_ARGV_GET: argv_get natively: argument i (the tagged number in rdi, from 0 for argv[1]) as a new string, or the default in rsi (nil when not given) when there is none; the default is consumed when the argument is taken.

    RT_ARGV_GET[0] #=> {op: "label", name: "rt_argv_get"}
"""
RT_ARGV_GET = frame_routine(
  "rt_argv_get",
  48,
  append(
    *[
      [
        {op: "store", src: "rsi", base: "rbp", disp: -40},
        {op: "store", src: "rsi", base: "rbp", disp: -16},
        {op: "sar1", dst: "rdi"},
        {op: "cmp", dst: "rdi", imm: 0},
        {op: "j", cond: "l", label: "rt_ag_out"},
        {op: "load", dst: "rsi", base: "r14", disp: ARGV_AT},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "label", name: "rt_ag_walk"},
        {op: "add", dst: "rsi", imm: 8},
        {op: "load", dst: "rax", base: "rsi", disp: 0},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "rt_ag_out"},
        {op: "cmp", dst: "rcx", src: "rdi"},
        {op: "j", cond: "e", label: "rt_ag_found"},
        {op: "add", dst: "rcx", imm: 1},
        {op: "jmp", label: "rt_ag_walk"},
        {op: "label", name: "rt_ag_found"},
        {op: "store", src: "rax", base: "rbp", disp: -24}
      ],
      env_value("rt_ag"),
      [
        {op: "load", dst: "rdi", base: "rbp", disp: -16},
        {op: "call_label", label: "rt_drop"},
        {op: "label", name: "rt_ag_out"}
      ]
    ]
  )
)

@doc """
RT_CWD: cwd natively: the working directory by getcwd(2) into the frame, as a new string; nil when it cannot be read.

    RT_CWD[0] #=> {op: "label", name: "rt_cwd"}
"""
RT_CWD = frame_routine(
  "rt_cwd",
  4160,
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -40},
        {op: "mov", dst: "rdi", src: "rbp"},
        {op: "add", dst: "rdi", imm: -4160},
        {op: "mov", dst: "rsi", imm: 4096},
        {op: "mov", dst: "rax", imm: 79},
        {op: "syscall"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "l", label: "rt_cw_out"},
        {op: "mov", dst: "rax", src: "rbp"},
        {op: "add", dst: "rax", imm: -4160},
        {op: "store", src: "rax", base: "rbp", disp: -24}
      ],
      env_value("rt_cw"),
      [{op: "label", name: "rt_cw_out"}]
    ]
  )
)

@doc """
RT_RANDOM_BYTES: random_bytes natively: the tagged count in rdi of random bytes from getrandom(2), as a list of numbers, filled 4096 at a time in the frame; an error (EINVAL) when the count is not 0 to 1048576, and the errno when the source cannot be read.

    RT_RANDOM_BYTES[0] #=> {op: "label", name: "rt_random_bytes"}
"""
RT_RANDOM_BYTES = frame_routine(
  "rt_random_bytes",
  4160,
  append(
    *[
      [
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -40},
        {op: "sar1", dst: "rdi"},
        {op: "store", src: "rdi", base: "rbp", disp: -8},
        {op: "mov", dst: "rax", imm: -22},
        {op: "cmp", dst: "rdi", imm: 0},
        {op: "j", cond: "l", label: "rt_rd_bad"},
        {op: "cmp", dst: "rdi", imm: 1_048_576},
        {op: "j", cond: "g", label: "rt_rd_bad"},
        {op: "label", name: "rt_rd_chunk"},
        {op: "load", dst: "rsi", base: "rbp", disp: -8},
        {op: "cmp", dst: "rsi", imm: 0},
        {op: "j", cond: "e", label: "rt_rd_out"},
        {op: "cmp", dst: "rsi", imm: 4096},
        {op: "j", cond: "le", label: "rt_rd_sized"},
        {op: "mov", dst: "rsi", imm: 4096},
        {op: "label", name: "rt_rd_sized"},
        {op: "mov", dst: "rdi", src: "rbp"},
        {op: "add", dst: "rdi", imm: -4160},
        {op: "mov", dst: "rdx", imm: 0},
        {op: "mov", dst: "rax", imm: 318},
        {op: "syscall"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "le", label: "rt_rd_failed"},
        {op: "load", dst: "rcx", base: "rbp", disp: -8},
        {op: "sub", dst: "rcx", src: "rax"},
        {op: "store", src: "rcx", base: "rbp", disp: -8},
        {op: "store", src: "rax", base: "rbp", disp: -16},
        {op: "label", name: "rt_rd_byte"},
        {op: "load", dst: "rcx", base: "rbp", disp: -16},
        {op: "cmp", dst: "rcx", imm: 0},
        {op: "j", cond: "e", label: "rt_rd_chunk"},
        {op: "sub", dst: "rcx", imm: 1},
        {op: "store", src: "rcx", base: "rbp", disp: -16},
        {op: "mov", dst: "rdx", src: "rbp"},
        {op: "add", dst: "rdx", imm: -4160},
        {op: "add", dst: "rdx", src: "rcx"},
        {op: "load_byte", dst: "rcx", base: "rdx"},
        {op: "mov", dst: "rdx", src: "rcx"},
        {op: "add", dst: "rcx", src: "rdx"},
        {op: "add", dst: "rcx", imm: 1},
        {op: "store", src: "rcx", base: "rbp", disp: -24}
      ],
      cell(-24, -40, -40),
      [
        {op: "jmp", label: "rt_rd_byte"},
        {op: "label", name: "rt_rd_failed"},
        {op: "push", src: "rax"},
        {op: "load", dst: "rdi", base: "rbp", disp: -40},
        {op: "call_label", label: "rt_drop"},
        {op: "pop", dst: "rax"},
        {op: "label", name: "rt_rd_bad"}
      ],
      error_from("rax"),
      [
        {op: "store", src: "rax", base: "rbp", disp: -40},
        {op: "label", name: "rt_rd_out"}
      ],
      empty_when_none(-40)
    ]
  )
)

@doc """
PROCESS_ROUTINES: the process words natively, each one routine: argv, argv_get, cwd and random_bytes.

    PROCESS_ROUTINES[0] #=> {op: "label", name: "rt_argv"}
"""
PROCESS_ROUTINES = append(*[RT_ARGV, RT_ARGV_GET, RT_CWD, RT_RANDOM_BYTES])

@doc """
process_programs: programs over the process words natively, in :show mode, with what each must write.

    length(process_programs) #=> 6
"""
def process_programs()
  [
    ["(string? cwd)", "true"],
    ["(list? argv)", "true"],
    ["(argv_get 999 :none)", ":none"],
    ["(length (random_bytes 16))", "16"],
    ["(try (random_bytes -1) (catch (e) 7))", "7"],
    ["(list (exec_ok? \"true\") (exec_ok? \"false\"))", "[true, false]"]
  ]
end

test "the process words answer natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-proc"), "proc.out")
    map(
      fn(p)
        write_bytes(path, compile_whole(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      process_programs
    )
  end
end

test "the process routines assemble, and the table keeps argv beside the environment"
  stand_ins = flat_map(
    %w[rt_alloc rt_drop],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(assemble(append(PROCESS_ROUTINES, stand_ins))) > 0
  assert ARGV_AT == ENVP_AT + 8
  assert last(save_argv)[:disp] == ARGV_AT
  assert frame_routine("rt_x", 48, [])[0] == {op: "label", name: "rt_x"}
  assert RT_ARGV[0] == {op: "label", name: "rt_argv"}
  assert RT_ARGV_GET[0] == {op: "label", name: "rt_argv_get"}
  assert RT_CWD[0] == {op: "label", name: "rt_cwd"}
  assert RT_RANDOM_BYTES[0] == {op: "label", name: "rt_random_bytes"}
  assert member?(
    {op: "call_label", label: "rt_exec_check"},
    rc_op([], "exec_ok?", ["true"])
  )
  assert last(routine_op([], "argv_get", [1])) ==
    {op: "call_label", label: "rt_argv_get"}
  assert length(process_programs) == 6
end

@doc """
logical: or and and of two forms as a let and an if, so the first is evaluated once: or answers the first when it holds, else the second; and answers the first when it does not hold, else the second.

    logical("or", 1, 2) == read_forms("(let ((__logical 1)) (if __logical __logical 2))")[0] #=> true
"""
def logical(op, a, b)
  t = read_forms("__logical")[0]
  branch = if op == "or"
    [read_forms("if")[0], t, t, b]
  else
    [read_forms("if")[0], t, b, t]
  end
  [read_forms("let")[0], [[t, a]], branch]
end

test "or and and lower to a let and an if, and compile"
  assert bare_calls(read_forms("(or nil 3)")[0]) ==
    read_forms("(let ((__logical nil)) (if __logical __logical 3))")[0]
  assert logical("and", 1, 2) ==
    read_forms("(let ((__logical 1)) (if __logical 2 __logical))")[0]
  assert length(compile_whole(read_forms("(or nil 3)")[0], :exit)) > 0
  assert length(
    compile_program(
      read_forms("(every? (lambda (b) (< b 3)) (list 1 2))")[0],
      :exit
    )
  ) > 0
end

@doc """
RT_STRING_LT: string_lt natively, the prelude's order for sort_strings: true when the string in rdi sorts before the string in rsi byte by byte (a prefix first); both consumed.

    RT_STRING_LT[0] #=> {op: "label", name: "rt_string_lt"}
"""
RT_STRING_LT = frame_routine(
  "rt_string_lt",
  48,
  [
    {op: "store", src: "rdi", base: "rbp", disp: -8},
    {op: "store", src: "rsi", base: "rbp", disp: -16},
    {op: "mov", dst: "rcx", imm: FALSE},
    {op: "store", src: "rcx", base: "rbp", disp: -40},
    {op: "load", dst: "r8", base: "rdi", disp: 24},
    {op: "load", dst: "r9", base: "rsi", disp: 24},
    {op: "mov", dst: "r10", imm: 0},
    {op: "label", name: "rt_sl_byte"},
    {op: "cmp", dst: "r10", src: "r9"},
    {op: "j", cond: "e", label: "rt_sl_done"},
    {op: "cmp", dst: "r10", src: "r8"},
    {op: "j", cond: "e", label: "rt_sl_less"},
    {op: "mov", dst: "rax", src: "rdi"},
    {op: "add", dst: "rax", imm: 32},
    {op: "add", dst: "rax", src: "r10"},
    {op: "load_byte", dst: "rax", base: "rax"},
    {op: "mov", dst: "rdx", src: "rsi"},
    {op: "add", dst: "rdx", imm: 32},
    {op: "add", dst: "rdx", src: "r10"},
    {op: "load_byte", dst: "rdx", base: "rdx"},
    {op: "cmp", dst: "rax", src: "rdx"},
    {op: "j", cond: "l", label: "rt_sl_less"},
    {op: "j", cond: "g", label: "rt_sl_done"},
    {op: "add", dst: "r10", imm: 1},
    {op: "jmp", label: "rt_sl_byte"},
    {op: "label", name: "rt_sl_less"},
    {op: "mov", dst: "rcx", imm: 2},
    {op: "store", src: "rcx", base: "rbp", disp: -40},
    {op: "label", name: "rt_sl_done"},
    {op: "load", dst: "rdi", base: "rbp", disp: -8},
    {op: "call_label", label: "rt_drop"},
    {op: "load", dst: "rdi", base: "rbp", disp: -16},
    {op: "call_label", label: "rt_drop"}
  ]
)

@doc """
RT_LS_RAW: ls_raw natively, the listing ls sorts: the entries of the directory named by the string in rdi (consumed), . and .. passed over, each as the full path dir/name, by openat and getdents64 into the frame; an error carrying the errno when it does not open.

    RT_LS_RAW[0] #=> {op: "label", name: "rt_ls_raw"}
"""
RT_LS_RAW = frame_routine(
  "rt_ls_raw",
  4224,
  append(
    *[
      [
        {op: "store", src: "rdi", base: "rbp", disp: -8},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "store", src: "rcx", base: "rbp", disp: -40},
        {op: "store", src: "rcx", base: "rbp", disp: -48}
      ],
      path_on_stack("rt_lr_path"),
      [
        {op: "mov", dst: "rdi", imm: -100},
        {op: "mov", dst: "rsi", src: "rsp"},
        {op: "mov", dst: "rdx", imm: 589_824},
        {op: "mov", dst: "rax", imm: 257},
        {op: "syscall"},
        {op: "add", dst: "rsp", src: "r9"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "ge", label: "rt_lr_open"}
      ],
      error_from("rax"),
      [
        {op: "store", src: "rax", base: "rbp", disp: -40},
        {op: "jmp", label: "rt_lr_out"},
        {op: "label", name: "rt_lr_open"},
        {op: "store", src: "rax", base: "rbp", disp: -16},
        {op: "label", name: "rt_lr_read"},
        {op: "load", dst: "rdi", base: "rbp", disp: -16},
        {op: "mov", dst: "rsi", src: "rbp"},
        {op: "add", dst: "rsi", imm: -4224},
        {op: "mov", dst: "rdx", imm: 4096},
        {op: "mov", dst: "rax", imm: 217},
        {op: "syscall"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "le", label: "rt_lr_closed"},
        {op: "store", src: "rax", base: "rbp", disp: -56},
        {op: "mov", dst: "rcx", imm: 0},
        {op: "label", name: "rt_lr_entry"},
        {op: "load", dst: "rax", base: "rbp", disp: -56},
        {op: "cmp", dst: "rcx", src: "rax"},
        {op: "j", cond: "ge", label: "rt_lr_read"},
        {op: "store", src: "rcx", base: "rbp", disp: -64},
        {op: "mov", dst: "rsi", src: "rbp"},
        {op: "add", dst: "rsi", imm: -4224},
        {op: "add", dst: "rsi", src: "rcx"},
        {op: "add", dst: "rsi", imm: 19},
        {op: "load_byte", dst: "rax", base: "rsi"},
        {op: "cmp", dst: "rax", imm: 46},
        {op: "j", cond: "ne", label: "rt_lr_take"},
        {op: "mov", dst: "rax", src: "rsi"},
        {op: "add", dst: "rax", imm: 1},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "rt_lr_skip"},
        {op: "cmp", dst: "rax", imm: 46},
        {op: "j", cond: "ne", label: "rt_lr_take"},
        {op: "mov", dst: "rax", src: "rsi"},
        {op: "add", dst: "rax", imm: 2},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "cmp", dst: "rax", imm: 0},
        {op: "j", cond: "e", label: "rt_lr_skip"},
        {op: "label", name: "rt_lr_take"},
        {op: "store", src: "rsi", base: "rbp", disp: -24}
      ],
      env_value("rt_lr"),
      [
        {op: "load", dst: "rdi", base: "rbp", disp: -8},
        {op: "load", dst: "rcx", base: "rdi", disp: 8},
        {op: "add", dst: "rcx", imm: 1},
        {op: "store", src: "rcx", base: "rdi", disp: 8},
        {op: "load", dst: "rsi", base: "rbp", disp: -40},
        {op: "call_label", label: "rt_path_join"},
        {op: "store", src: "rax", base: "rbp", disp: -72}
      ],
      cell(-72, -48, -48),
      [
        {op: "label", name: "rt_lr_skip"},
        {op: "load", dst: "rcx", base: "rbp", disp: -64},
        {op: "mov", dst: "rax", src: "rbp"},
        {op: "add", dst: "rax", imm: -4224},
        {op: "add", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", imm: 16},
        {op: "load_byte", dst: "rdx", base: "rax"},
        {op: "add", dst: "rax", imm: 1},
        {op: "load_byte", dst: "rax", base: "rax"},
        {op: "mov", dst: "r8", imm: 256},
        {op: "imul", dst: "rax", src: "r8"},
        {op: "add", dst: "rax", src: "rdx"},
        {op: "add", dst: "rcx", src: "rax"},
        {op: "jmp", label: "rt_lr_entry"},
        {op: "label", name: "rt_lr_closed"},
        {op: "load", dst: "rdi", base: "rbp", disp: -16},
        {op: "mov", dst: "rax", imm: 3},
        {op: "syscall"}
      ],
      empty_when_none(-48),
      [
        {op: "load", dst: "rax", base: "rbp", disp: -48},
        {op: "store", src: "rax", base: "rbp", disp: -40},
        {op: "label", name: "rt_lr_out"},
        {op: "load", dst: "rdi", base: "rbp", disp: -8},
        {op: "call_label", label: "rt_drop"}
      ]
    ]
  )
)

@doc """
ls_programs: programs over ls natively (compiled with the prelude, which sorts), in :show mode, with what each must write.

    length(ls_programs) #=> 2
"""
def ls_programs()
  d = "(path_join (getenv \"TMPDIR\" \"/tmp\") \"hashiru-ls\")"
  [
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p d) (write_file (path_join d \"b\") \"\") (write_file (path_join d \"a\") \"\") (mkdir (path_join d \"c\")) (let ((r (map (lambda (p) (path_basename p)) (ls d)))) (begin (rm_rf d) r))))",
      "[\"a\", \"b\", \"c\"]"
    ],
    ["(try (ls \"/nonexistent/hashiru\") (catch (e) 7))", "7"]
  ]
end

test "ls lists a directory's full paths, sorted, natively on x86-64", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-ls-run"), "ls.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      ls_programs
    )
  end
end

test "ls is ls_raw sorted by the prelude over string_lt"
  stand_ins = flat_map(
    %w[rt_alloc rt_drop rt_path_join],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(assemble(append(append(RT_LS_RAW, RT_STRING_LT), stand_ins))) >
    0
  assert bare_calls(read_forms("(ls d)")[0]) ==
    read_forms("(sort_strings (ls_raw d))")[0]
  assert length(ls_programs) == 2
end

@doc """
tcp_op: the former name of routine_op, from when only the TCP words went through it; it answers what routine_op answers.

    tcp_op([], "tcp_port", [1]) == routine_op([], "tcp_port", [1]) #=> true
"""
def tcp_op(slots, op, args)
  routine_op(slots, op, args)
end

test "tcp_op answers what routine_op answers"
  assert tcp_op([], "getenv", %w[A b]) == routine_op([], "getenv", %w[A b])
end

@doc """
falsy_jump: the instructions that jump to label when the value in rax is nil (0) or false (FALSE), the two values an if takes as not holding.

    length(falsy_jump("no")) #=> 4
"""
def falsy_jump(label)
  [
    {op: "cmp", dst: "rax", imm: 0},
    {op: "j", cond: "e", label:},
    {op: "cmp", dst: "rax", imm: FALSE},
    {op: "j", cond: "e", label:}
  ]
end

test "false is its own word natively: not nil, taken as not holding by an if, shown as false"
  assert FALSE == 4
  assert tagged_atom([], false, "rax") == [{op: "mov", dst: "rax", imm: FALSE}]
  assert load_atom([], false, "rax") == [{op: "mov", dst: "rax", imm: 0}]
  assert length(AS_BOOLEAN) == 3
  assert falsy_jump("no")[2] == {op: "cmp", dst: "rax", imm: FALSE}
  assert member?({op: "cmp", dst: "rdi", imm: FALSE}, RT_SHOW)
  assert KIND_PREDICATES[4] == ["boolean?", [2, 8]]
end

@doc """
rest_arities: each global a core form defines with a rest parameter, and how many parameters come before it: [name, count] for `(define (f a &rest r) …)` and `(define f (lambda (a &rest r) …))`.

    rest_arities(read_forms("(define (f a &rest r) r)")[0]) #=> [["f", 1]]
"""
def rest_arities(form)
  if not list?(form) or length(form) == 0
    []
  else
    own = if head_is?(form, "define") and list?(form[1])
      k = index_of(map((p) -> to_s(p), rest(form[1])), "&rest")
      if k >= 0
        [[to_s(form[1][0]), k]]
      else
        []
      end
    elsif head_is?(form, "define") and
        list?(form[2]) and
        head_is?(form[2], "lambda")
      k = index_of(map((p) -> to_s(p), form[2][1]), "&rest")
      if k >= 0
        [[to_s(form[1]), k]]
      else
        []
      end
    else
      []
    end
    append(own, flat_map(form, rest_arities))
  end
end

@doc """
without_rest_mark: a parameter list with its &rest marker gone, so the rest parameter is an ordinary last parameter that receives a list.

    without_rest_mark(read_forms("(a &rest r)")[0]) == read_forms("(a r)")[0] #=> true
"""
def without_rest_mark(params)
  filter((p) -> to_s(p) != "&rest", params)
end

@doc """
rest_calls: a core form with every rest parameter made an ordinary last parameter, and every call of a global in table (rest_arities) given its leading arguments, then the rest packed in one list.

    rest_calls(read_forms("(f 1 2 3)")[0], [["f", 1]]) == read_forms("(f 1 (list 2 3))")[0] #=> true
"""
def rest_calls(form, table)
  if not list?(form) or length(form) == 0
    form
  elsif head_is?(form, "define") and list?(form[1])
    append(
      [form[0], without_rest_mark(form[1])],
      map((f) -> rest_calls(f, table), rest(rest(form)))
    )
  elsif head_is?(form, "lambda") and list?(form[1])
    append(
      [form[0], without_rest_mark(form[1])],
      map((f) -> rest_calls(f, table), rest(rest(form)))
    )
  else
    hits = if symbol?(form[0])
      filter((t) -> t[0] == to_s(form[0]), table)
    else
      []
    end
    args = map((f) -> rest_calls(f, table), rest(form))
    if length(hits) > 0 and length(args) >= hits[0][1]
      k = hits[0][1]
      append(
        cons(form[0], take(k, args)),
        [cons(read_forms("list")[0], drop(k, args))]
      )
    else
      cons(rest_calls(form[0], table), args)
    end
  end
end

test "a rest parameter becomes a last parameter that takes the extra arguments as a list"
  assert rest_arities(read_forms("(define f (lambda (h &rest t) t))")[0]) ==
    [["f", 1]]
  assert rest_arities(read_forms("(define (g a) a)")[0]) == []
  assert rest_arities(read_forms("(define g (lambda (h) h))")[0]) == []
  assert without_rest_mark(read_forms("(a &rest r)")[0]) ==
    read_forms("(a r)")[0]
  assert bare_calls(
    read_forms("(begin (define (f a &rest r) r) (f 1 2 3))")[0]
  ) == read_forms("(begin (define (f a r) r) (f 1 (list 2 3)))")[0]
  assert rest_calls(read_forms("(g 1)")[0], [["f", 1]]) ==
    read_forms("(g 1)")[0]
  assert bare_calls(read_forms("(drop 1 l)")[0]) ==
    read_forms("(list_drop 1 l)")[0]
end

test "nth past either end is nil, and a concat makes each non-literal part a string"
  assert bare_calls(read_forms("(concat \"n = \" n)")[0]) ==
    read_forms("(concat \"n = \" (to_s n))")[0]
  assert member?(
    "(define (nth i l) (if (< i 0) nil (if (equal? (length l) 0) nil (if (equal? i 0) (first l) (nth (- i 1) (rest l))))))",
    PRELUDE
  )
end

@doc """
tail_jump: a call of the function itself in tail position: the arguments in ARG_REGS and a jump back to just after its frame is made, where they are stored as its parameters again, so the frame is reused and the stack does not grow.

    last(tail_jump([], "f", [1])) #=> {op: "jmp", label: "g_f_tail"}
"""
def tail_jump(slots, name, args)
  append(
    flat_map(
      range(0, length(args)),
      (k) -> tagged_atom(slots, args[k], ARG_REGS[k])
    ),
    [{op: "jmp", label: "g_#{name}_tail"}]
  )
end

@doc """
returns_var?: whether the rest of a term only answers the variable v: a ret of it, or the check a call's answer goes through (a dup, failed?, an if that rets it either way, and a ret of that).

    returns_var?(read_forms("(ret x)")[0], read_forms("x")[0]) #=> true
"""
def returns_var?(term, v)
  s = to_s(v)
  if head_is?(term, "ret")
    to_s(term[1]) == s
  elsif head_is?(term, "let") and head_is?(term[1][1], "dup")
    c = term[2]
    rest_ok = head_is?(c, "let") and head_is?(c[1][1], "failed?")
    if rest_ok
      r = c[2]
      head_is?(r, "let") and
        head_is?(r[1][1], "if") and
        head_is?(r[1][1][2], "ret") and
        to_s(r[1][1][2][1]) == s and
        head_is?(r[1][1][3], "ret") and
        to_s(r[1][1][3][1]) == s and
        head_is?(r[2], "ret") and
        to_s(r[2][1]) == to_s(r[1][0])
    else
      false
    end
  else
    false
  end
end

@doc """
mark_tail: a global's body with each call of the global itself in tail position made a tailcall: a gcall whose answer the rest only returns, found down the body and into the branches of an if whose value is returned the same way.

    mark_tail(read_forms("(let (t (gcall \"f\" 1)) (ret t))")[0], "f")[1][1][0] == read_forms("tailcall")[0] #=> true
"""
def mark_tail(term, name)
  if not head_is?(term, "let")
    term
  else
    v = term[1][0]
    rhs = term[1][1]
    after = term[2]
    if returns_var?(after, v)
      marked = if head_is?(rhs, "gcall") and rhs[1] == name
        cons(read_forms("tailcall")[0], rest(rhs))
      elsif head_is?(rhs, "if")
        [rhs[0], rhs[1], mark_tail(rhs[2], name), mark_tail(rhs[3], name)]
      else
        rhs
      end
      [term[0], [v, marked], after]
    else
      [term[0], [v, rhs], mark_tail(after, name)]
    end
  end
end

@doc """
tail_programs: programs whose recursion is a self call in tail position, so a native run with a deep count neither grows the stack nor crashes; each must exit with the status given.

    length(tail_programs) #=> 2
"""
def tail_programs()
  [
    [
      "(begin (define (loop n acc) (if (equal? n 0) acc (loop (- n 1) (+ acc 1)))) (if (equal? (loop 1000000 0) 1000000) 0 1))",
      0
    ],
    [
      "(begin (define (count n) (if (< n 1) 7 (count (- n 1)))) (count 2000000))",
      7
    ]
  ]
end

test "a self tail call jumps and reuses the frame natively", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-tail"), "tail.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      tail_programs
    )
  end
end

test "mark_tail finds a self call whose answer is only returned, through an if"
  body = get(
    nth(
      0,
      get(
        whole(
          nth(
            0,
            read_forms("(begin (define (loop n acc) (if (equal? n 0) acc (loop (- n 1) (+ acc 1)))) (loop 5 0))")
          )
        ),
        :globals
      )
    ),
    :body
  )
  insns = rc_global({name: "loop", params: %w[n acc], body:}, 0)[0]
  assert member?({op: "jmp", label: "g_loop_tail"}, insns)
  assert not member?({op: "call_label", label: "g_loop"}, insns)
  assert last(tail_jump([], "f", [1])) == {op: "jmp", label: "g_f_tail"}
  assert returns_var?(read_forms("(ret x)")[0], read_forms("x")[0])
  assert not returns_var?(read_forms("(ret y)")[0], read_forms("x")[0])
  assert not returns_var?(
    read_forms("(let (a (dup x)) (ret x))")[0],
    read_forms("x")[0]
  )
  assert not returns_var?(
    read_forms("(let (a 1) (ret a))")[0],
    read_forms("x")[0]
  )
  assert mark_tail(read_forms("(ret 1)")[0], "f") == read_forms("(ret 1)")[0]
  assert mark_tail(read_forms("(let (a (g 1)) (ret a))")[0], "f") ==
    read_forms("(let (a (g 1)) (ret a))")[0]
  assert length(tail_programs) == 2
end

@doc """
STACK_AT: where the program keeps its stack floor, as an offset from r14: the word after the argument vector.

    STACK_AT #=> 528
"""
STACK_AT = ARGV_AT + 8

@doc """
STACK_DEPTH: how far below the entry stack pointer a global may still be entered: 7.5 MiB, under the 8 MiB stack Linux gives by default, so a call deeper than that raises before it faults.

    STACK_DEPTH #=> 7_864_320
"""
STACK_DEPTH = 7_864_320

@doc """
save_stack_floor: the instructions that keep the stack floor, rsp at entry less STACK_DEPTH, at r14 + STACK_AT.

    last(save_stack_floor)[:disp] #=> STACK_AT
"""
def save_stack_floor()
  [
    {op: "mov", dst: "rcx", src: "rsp"},
    {op: "sub", dst: "rcx", imm: STACK_DEPTH},
    {op: "store", src: "rcx", base: "r14", disp: STACK_AT}
  ]
end

@doc """
stack_guard: the instructions at a global's entry, before its parameters are stored from ARG_REGS (so they use r11, which carries no argument), that answer an error (ENOMEM, 12) and return when the stack pointer is below the floor, so recursion too deep for the stack raises and a try can catch it, where it would fault.

    stack_guard("g_f")[1] #=> {op: "cmp", dst: "rsp", src: "r11"}
"""
def stack_guard(label)
  append(
    *[
      [
        {op: "load", dst: "r11", base: "r14", disp: STACK_AT},
        {op: "cmp", dst: "rsp", src: "r11"},
        {op: "j", cond: "ge", label: "#{label}_deep_ok"},
        {op: "mov", dst: "rax", imm: -12}
      ],
      error_from("rax"),
      [
        {op: "mov", dst: "rsp", src: "rbp"},
        {op: "pop_rbp"},
        {op: "ret"},
        {op: "label", name: "#{label}_deep_ok"}
      ]
    ]
  )
end

@doc """
deep_programs: programs whose recursion is no tail call and runs deeper than the stack allows, each caught by a try natively; each must exit with the status given.

    length(deep_programs) #=> 1
"""
def deep_programs()
  [
    [
      "(begin (define (deep n) (if (equal? n 0) 0 (+ 1 (deep (- n 1))))) (try (deep 10000000) (catch (e) 9)))",
      9
    ]
  ]
end

test "too-deep recursion raises and is caught natively", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-deep"), "deep.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :exit))
        exec_capture("chmod", "+x", path)
        assert status_of(exec_capture(path)) == p[1]
      end,
      deep_programs
    )
  end
end

test "a global checks the stack floor at its entry"
  assert STACK_AT == ARGV_AT + 8
  assert STACK_DEPTH < 8_388_608
  assert last(save_stack_floor)[:disp] == STACK_AT
  assert stack_guard("g_f")[1] == {op: "cmp", dst: "rsp", src: "r11"}
  assert not member?("rcx", map((i) -> i[:dst], take(3, stack_guard("g_f"))))
  g = rc_global({name: "f", params: [], body: read_forms("(ret 1)")[0]}, 0)[0]
  assert member?({op: "label", name: "g_f_deep_ok"}, g)
  assert length(deep_programs) == 1
end

test "the empty list is its own word natively, and a list still ends in 0 inside"
  assert EMPTY == 6
  assert list_code([], []) == [{op: "mov", dst: "rax", imm: EMPTY}]
  assert length(swap_word("rbx", EMPTY, 0, "rax")) == 9
  assert length(empty_when_none(-40)) == 11
  assert KIND_PREDICATES[3] == ["list?", [3, 9]]
  assert member?({op: "cmp", dst: "rdi", imm: EMPTY}, RT_SHOW)
  assert member?({op: "cmp", dst: "rdx", imm: EMPTY}, RT_LENGTH)
end

@doc """
map_calls: a core form with its maps made native maps: a hash-map literal the prelude's map_put over an empty map, pair by pair (a later key replaces an earlier one), get the prelude's map_get, and assoc its map_put; compile_program applies it, as the words it calls are the prelude's.

    map_calls(read_forms("(get m :a)")[0]) == read_forms("(map_get m :a)")[0] #=> true
"""
def map_calls(form)
  if not list?(form) or length(form) == 0
    form
  else
    parts = map(map_calls, rest(form))
    if head_is?(form, "hash-map")
      reduce(
        (m, i) -> [read_forms("map_put")[0], m, parts[2 * i], parts[2 * i + 1]],
        [read_forms("map_wrap")[0], [read_forms("list")[0]]],
        range(0, floor(length(parts) / 2))
      )
    elsif head_is?(form, "get") and length(parts) == 2
      cons(read_forms("map_get")[0], parts)
    elsif head_is?(form, "assoc") and length(parts) == 3
      cons(read_forms("map_put")[0], parts)
    else
      cons(map_calls(form[0]), parts)
    end
  end
end

@doc """
map_programs: programs over native maps, in :show mode, with what each must write, as blue answers them.

    length(map_programs) #=> 6
"""
def map_programs()
  [
    ["(hash-map :a 1 \"k\" 2)", "{\"k\" => 2, a: 1}"],
    %w[(hash-map) {}],
    ["(assoc (hash-map :a 1) :b 2)", "{a: 1, b: 2}"],
    ["(assoc (hash-map :a 1) :a 9)", "{a: 9}"],
    ["(equal? (hash-map :a 1 :b 2) (hash-map :b 2 :a 1))", "true"],
    ["(list (get (hash-map :k 1) :k) (get (hash-map :k 1) :z))", "[1, nil]"]
  ]
end

test "native maps sort, show and compare as blue does", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-map"), "map.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      map_programs
    )
  end
end

test "a map literal, get and assoc become the prelude's map words"
  assert map_calls(read_forms("(hash-map :a 1)")[0]) ==
    read_forms("(map_put (map_wrap (list)) :a 1)")[0]
  assert map_calls(read_forms("(assoc m :a 1)")[0]) ==
    read_forms("(map_put m :a 1)")[0]
  assert map_calls(read_forms("(get m :a)")[0]) ==
    read_forms("(map_get m :a)")[0]
  assert map_calls(7) == 7
  assert MAP_KIND == 7
  assert SHOW_MAP[0] == {op: "label", name: "rt_sh_map"}
  assert member?({op: "cmp", dst: "rax", imm: MAP_KIND}, RT_EQUAL)
  assert member?(
    {op: "store", src: "rcx", base: "rax", disp: 24},
    rc_op([], "map_wrap", [1])
  )
  assert length(rc_op([], "map_alist", [1])) > 0
  assert length(map_programs) == 6
end

@doc """
RT_TO_TEXT: to_s of a list or a map natively: its text as rt_show writes it, gathered by pointing SHOW_FD_AT at a memfd for the show, then read back into a new string; the value in rdi is consumed, and SHOW_FD_AT is put back.

    RT_TO_TEXT[0] #=> {op: "label", name: "rt_to_text"}
"""
RT_TO_TEXT = [
  {op: "label", name: "rt_to_text"},
  {op: "push_rbp"},
  {op: "mov", dst: "rbp", src: "rsp"},
  {op: "sub", dst: "rsp", imm: 64},
  {op: "store", src: "rdi", base: "rbp", disp: -8},
  {op: "mov", dst: "rcx", imm: 115},
  {op: "store", src: "rcx", base: "rbp", disp: -16},
  {op: "mov", dst: "rdi", src: "rbp"},
  {op: "add", dst: "rdi", imm: -16},
  {op: "mov", dst: "rsi", imm: 0},
  {op: "mov", dst: "rax", imm: 319},
  {op: "syscall"},
  {op: "store", src: "rax", base: "rbp", disp: -24},
  {op: "load", dst: "rcx", base: "r14", disp: SHOW_FD_AT},
  {op: "store", src: "rcx", base: "rbp", disp: -32},
  {op: "store", src: "rax", base: "r14", disp: SHOW_FD_AT},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "call_label", label: "rt_show"},
  {op: "load", dst: "rcx", base: "rbp", disp: -32},
  {op: "store", src: "rcx", base: "r14", disp: SHOW_FD_AT},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rsi", imm: 0},
  {op: "mov", dst: "rdx", imm: 2},
  {op: "mov", dst: "rax", imm: 8},
  {op: "syscall"},
  {op: "store", src: "rax", base: "rbp", disp: -40},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rsi", imm: 0},
  {op: "mov", dst: "rdx", imm: 0},
  {op: "mov", dst: "rax", imm: 8},
  {op: "syscall"},
  {op: "load", dst: "rdi", base: "rbp", disp: -40},
  {op: "add", dst: "rdi", imm: 7},
  {op: "shr1", dst: "rdi"},
  {op: "shr1", dst: "rdi"},
  {op: "shr1", dst: "rdi"},
  {op: "add", dst: "rdi", imm: 4},
  {op: "call_label", label: "rt_alloc"},
  {op: "mov", dst: "rcx", imm: 1},
  {op: "store", src: "rcx", base: "rax", disp: 0},
  {op: "load", dst: "rcx", base: "rbp", disp: -40},
  {op: "store", src: "rcx", base: "rax", disp: 24},
  {op: "store", src: "rax", base: "rbp", disp: -48},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rsi", src: "rax"},
  {op: "add", dst: "rsi", imm: 32},
  {op: "load", dst: "rdx", base: "rbp", disp: -40},
  {op: "mov", dst: "rax", imm: 0},
  {op: "syscall"},
  {op: "load", dst: "rdi", base: "rbp", disp: -24},
  {op: "mov", dst: "rax", imm: 3},
  {op: "syscall"},
  {op: "load", dst: "rdi", base: "rbp", disp: -8},
  {op: "call_label", label: "rt_drop"},
  {op: "load", dst: "rax", base: "rbp", disp: -48},
  {op: "mov", dst: "rsp", src: "rbp"},
  {op: "pop_rbp"},
  {op: "ret"}
]

@doc """
text_programs: programs whose to_s of a list or a map is its text natively, in :show mode, with what each must write.

    length(text_programs) #=> 3
"""
def text_programs()
  [
    ["(to_s (hash-map :b 2 :a (list 1)))", "\"{a: [1], b: 2}\""],
    ["(to_s (list 1 \"x\" :k))", "\"[1, \\\"x\\\", :k]\""],
    ["(concat \"n = \" (list 1 2))", "\"n = [1, 2]\""]
  ]
end

test "to_s of a list or a map is its text natively", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-text"), "text.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      text_programs
    )
  end
end

test "rt_show writes to the descriptor at SHOW_FD_AT, which to_s points at a memfd"
  assert SHOW_FD_AT == FREE_CLASSES * 8 + 24
  assert member?(
    {op: "load", dst: "rdi", base: "r14", disp: SHOW_FD_AT},
    RT_PUT_BYTE
  )
  assert member?({op: "j", cond: "e", label: "rt_to_text"}, RT_TO_S)
  stand_ins = flat_map(
    %w[rt_alloc rt_drop rt_show],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(assemble(append(RT_TO_TEXT, stand_ins))) > 0
  assert length(text_programs) == 3
end

test "a board use is dropped, another refused; define-typed is erased", {
  kind: :unit
}
  assert board_use?(read_forms("(use \"kiban\" (list :put_byte :put_int))")[0])
  assert not board_use?(read_forms("(f 1)")[0])
  reclaim = read_forms("(use \"kiban\" (list :reclaim))")[0]
  assert (board_use?(reclaim) rescue :refused) == :refused
  assert board_use?(read_forms("(use \"kiban\")")[0])
  bare = read_forms("(define-typed f Int 1)")[0]
  assert typed_erased(bare) == bare
  mixed = read_forms("(define-typed (g n (m Int)) Int n)")[0]
  assert typed_erased(mixed) == read_forms("(define (g n m) n)")[0]
  short = read_forms("(define-typed (f n))")[0]
  assert typed_erased(short) == short
  assert typed_erased(read_forms("(define-typed (f (n Int)) Int n)")[0]) ==
    read_forms("(define (f n) n)")[0]
  assert typed_erased(read_forms("(f 1)")[0]) == read_forms("(f 1)")[0]
end

@doc """
divide: a routine over the tagged numbers in rdi and rsi that divides with idiv and floors the quotient toward negative infinity, as blue's floor of a quotient does (blue's % is RT_MOD, euclidean); answer "q" gives the quotient, any other the floored remainder. A zero divisor answers an error (EDOM, 33).

    divide("rt_x", "q")[0] #=> {op: "label", name: "rt_x"}
"""
def divide(name, answer)
  append(
    *[
      [
        {op: "label", name:},
        {op: "push_rbp"},
        {op: "mov", dst: "rbp", src: "rsp"},
        {op: "sar1", dst: "rdi"},
        {op: "sar1", dst: "rsi"},
        {op: "cmp", dst: "rsi", imm: 0},
        {op: "j", cond: "ne", label: "#{name}_go"},
        {op: "mov", dst: "rax", imm: -33}
      ],
      error_from("rax"),
      [
        {op: "jmp", label: "#{name}_out"},
        {op: "label", name: "#{name}_go"},
        {op: "mov", dst: "rax", src: "rdi"},
        {op: "cqo"},
        {op: "idiv", src: "rsi"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "e", label: "#{name}_exact"},
        {op: "cmp", dst: "rdx", imm: 0},
        {op: "j", cond: "l", label: "#{name}_negative"},
        {op: "cmp", dst: "rsi", imm: 0},
        {op: "j", cond: "g", label: "#{name}_exact"},
        {op: "jmp", label: "#{name}_adjust"},
        {op: "label", name: "#{name}_negative"},
        {op: "cmp", dst: "rsi", imm: 0},
        {op: "j", cond: "l", label: "#{name}_exact"},
        {op: "label", name: "#{name}_adjust"},
        {op: "sub", dst: "rax", imm: 1},
        {op: "add", dst: "rdx", src: "rsi"},
        {op: "label", name: "#{name}_exact"}
      ],
      if answer == "q"
        []
      else
        [{op: "mov", dst: "rax", src: "rdx"}]
      end,
      [
        {op: "mov", dst: "rcx", src: "rax"},
        {op: "add", dst: "rax", src: "rcx"},
        {op: "add", dst: "rax", imm: 1},
        {op: "label", name: "#{name}_out"},
        {op: "mov", dst: "rsp", src: "rbp"},
        {op: "pop_rbp"},
        {op: "ret"}
      ]
    ]
  )
end

@doc """
RT_FLOOR_DIV: int_div natively, the floor of a quotient (blue's floor(a / b) of two Ints).

    RT_FLOOR_DIV[0] #=> {op: "label", name: "rt_floor_div"}
"""
RT_FLOOR_DIV = divide("rt_floor_div", "q")

@doc """
clock_programs: programs over division, a fourth parameter (which the stack guard once overwrote), the date, walk_dir and the byte readers natively, in :show mode, with what each must write.

    length(clock_programs) #=> 6
"""
def clock_programs()
  d = "(path_join (getenv \"TMPDIR\" \"/tmp\") \"hashiru-clock\")"
  [
    [
      "(list (int_div (- 0 7) 2) (mod (- 0 7) 2) (int_div 7 2) (mod 7 (- 0 2)))",
      "[-4, 1, 3, 1]"
    ],
    ["(begin (define (four a b c d) d) (four 1 2 3 7))", "7"],
    ["(rfc3339 1700000000)", "\"2023-11-14T22:13:20Z\""],
    ["(string? now_rfc3339)", "true"],
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p (path_join d \"s\")) (write_file (path_join d \"s/f\") \"\") (let ((r (length (walk_dir d)))) (begin (rm_rf d) r))))",
      "1"
    ],
    [
      "(let ((d #{d})) (begin (rm_rf d) (mkdir_p d) (write_bytes (path_join d \"b\") (list 0 255 7 128)) (let ((f (path_join d \"b\"))) (let ((r (list (read_bytes f 1 2) (read_bytes f 9 1) (read_u32s f 0 2)))) (begin (rm_rf d) r)))))",
      "[[255, 7], [], [2148007680]]"
    ]
  ]
end

test "division, the date, walk_dir and the byte readers natively", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-clock"), "clock.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      clock_programs
    )
  end
end

test "floor of a quotient and read_bytes with a range lower to the prelude's words"
  assert bare_calls(read_forms("(sh_exec s)")[0]) ==
    read_forms("(exec_capture \"sh\" \"-c\" s)")[0]
  assert bare_calls(read_forms("(floor (/ a b))")[0]) ==
    read_forms("(int_div a b)")[0]
  assert bare_calls(read_forms("(read_bytes f 1 2)")[0]) ==
    read_forms("(bytes_slice (read_bytes f) 1 2)")[0]
  stand_ins = flat_map(
    ["rt_alloc"],
    (n) -> [{op: "label", name: n}, {op: "ret"}]
  )
  assert length(
    assemble(append(append(RT_FLOOR_DIV, divide("rt_r", "r")), stand_ins))
  ) > 0
  assert divide("rt_x", "q")[0] == {op: "label", name: "rt_x"}
  assert length(clock_programs) == 6
end

@doc """
symbols_in: the name of every symbol anywhere in a core form.

    symbols_in(read_forms("(f (g x) 1)")[0]) #=> %w[f g x]
"""
def symbols_in(form)
  if symbol?(form)
    [to_s(form)]
  elsif list?(form)
    flat_map(form, symbols_in)
  else
    []
  end
end

@doc """
defined_name: the name a (define (f …) …) form defines, or nil for any other form.

    defined_name(read_forms("(define (f a) a)")[0]) #=> "f"
"""
def defined_name(form)
  if head_is?(form, "define") and list?(form[1])
    to_s(form[1][0])
  end
end

@doc """
reached: the names reachable from roots through the definitions in defs, each name adding the symbols of the definition it names, until nothing new is reached.

    reached([read_forms("(define (f) (g))")[0]], ["f"]) #=> %w[f define g]
"""
def reached(defs, roots)
  grown = distinct(
    append(
      roots,
      flat_map(filter((d) -> member?(defined_name(d), roots), defs), symbols_in)
    )
  )
  if length(grown) == length(distinct(roots))
    grown
  else
    reached(defs, grown)
  end
end

@doc """
shake: a (begin …) program with each function definition its own forms do not reach taken out, so a program compiles only the prelude words it calls.

    shake(read_forms("(begin (define (f) 1) (define (g) 2) (f))")[0]) == read_forms("(begin (define (f) 1) (f))")[0] #=> true
"""
def shake(form)
  if not head_is?(form, "begin")
    form
  else
    items = rest(form)
    defs = filter((i) -> not defined_name(i).nil?, items)
    roots = flat_map(filter((i) -> defined_name(i).nil?, items), symbols_in)
    keep = reached(defs, roots)
    cons(
      form[0],
      filter(
        (i) -> defined_name(i).nil? or member?(defined_name(i), keep),
        items
      )
    )
  end
end

test "a program keeps only the definitions its own forms reach"
  assert symbols_in(read_forms("(f (g x) 1)")[0]) == %w[f g x]
  assert defined_name(read_forms("(define x 1)")[0]).nil?
  assert shake(
    read_forms("(begin (define (f) (g)) (define (g) 2) (define (h) 3) (f))")[0]
  ) == read_forms("(begin (define (f) (g)) (define (g) 2) (f))")[0]
  assert shake(read_forms("7")[0]) == 7
  assert reached([read_forms("(define (f) (g))")[0]], %w[f f]) == %w[f define g]
  assert length(compile_program(read_forms("(drop 1 (list 1 2))")[0], :exit)) >
    0
end

@doc """
within_programs: programs over exec_within natively, compiled with the prelude, in :show mode, with what each must write: a command that ends in time, and one the deadline ends with its process group.

    length(within_programs) #=> 2
"""
def within_programs()
  [
    [
      "(exec_within 5000 \"printf\" \"x\")",
      "[[:status, 0], [:stdout, \"x\"], [:stderr, \"\"], [:timed_out, false]]"
    ],
    [
      "(exec_within 200 \"sleep\" \"5\")",
      "[[:status, -1], [:stdout, \"\"], [:stderr, \"\"], [:timed_out, true]]"
    ]
  ]
end

test "exec_within runs a command to its end or its deadline natively", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    path = path_join(temp_dir("hashiru-within"), "within.out")
    map(
      fn(p)
        write_bytes(path, compile_program(read_forms(p[0])[0], :show))
        exec_capture("chmod", "+x", path)
        assert stdout_of(exec_capture(path)) == p[1]
      end,
      within_programs
    )
  end
end

test "exec_within is a timed exec_capture with its time out appended"
  assert EXEC_MS_AT == FREE_CLASSES * 8 + 32
  assert EXEC_TIMED_AT == EXEC_MS_AT + 8
  assert length(now_ms_rax) == 14
  assert exec_deadline[0] == {op: "mov", dst: "rcx", imm: 0}
  assert exec_own_group[1] == {op: "cmp", dst: "rcx", imm: 0}
  assert last(exec_poll_until)[:name] == "rt_xc_polled"
  assert exec_status_when_timed[1] == {op: "cmp", dst: "rcx", imm: 0}
  assert member?(
    {op: "store", src: "rcx", base: "r14", disp: EXEC_MS_AT},
    rc_op([], "exec_within_raw", [5, "true"])
  )
  assert length(rc_op([], "exec_timed_out", [])) == 4
  assert head_is?(bare_calls(read_forms("(exec_within 5 \"true\")")[0]), "let")
  assert length(within_programs) == 2
end
