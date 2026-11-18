@moduledoc """
hashiru (走る) — blue code that runs: kuzushi's A-normal form compiled to x86-64 instructions (kikaigo) inside a static executable (erufu), with no other language in the path (docs/PURE-BLUE.md B3).

This first code generator is the simplest correct one: every named value lives in its own stack slot below rbp, every operation loads its atoms into rax and rcx, computes in rax and stores the result back. A comparison leaves 1 or 0; an if tests its condition against 0 and jumps; a program's value becomes its exit status. Register allocation replaces the slots later; the slots are the oracle it must agree with.

    length(compile(read_forms("(+ 1 2)")[0])) > 120 #=> true
"""

use("kaaneru/erufu", [:executable])
use("kikaigo", [:assemble])
use("kuzushi", %i[anf closure_convert head_is?])
use("retsu", %i[first flat_map index_of last rest])
use("shisutemu", %i[status_of stdout_of])

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
run_exit: compile a form, run it, and answer its exit status.

    integer?(1) #=> true
"""
def run_exit(form)
  path = path_join(temp_dir("hashiru"), "a.out")
  write_bytes(path, compile(form))
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
    map((p) -> assert run_exit(read_forms(p[0])[0]) == p[1], PROGRAMS)
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
    call_code(slots, rhs[1], rest(rest(rhs)))
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
call_code: a call through a closure: the arguments in ARG_REGS, the closure in r11, then a call through its code address; the answer comes back in rax.

    last(call_code(["f"], read_forms("f")[0], [1]))[:op] #=> "call_r11"
"""
def call_code(slots, f, args)
  if length(args) > 6
    raise(:unsupported, "hashiru: a call passes at most six arguments")
  end
  append(
    *[
      flat_map(
        range(0, length(args)),
        (k) -> load_atom(slots, args[k], ARG_REGS[k])
      ),
      load_atom(slots, f, "r11"),
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

@doc """
run_closures_exit: compile a form with lambdas, run it, and answer its exit status.

    integer?(1) #=> true
"""
def run_closures_exit(form)
  path = path_join(temp_dir("hashiru"), "c.out")
  write_bytes(path, compile_closures(form))
  exec_capture("chmod", "+x", path)
  status_of(exec_capture(path))
end

test "every closure program's exit status is its value when run on x86-64 Linux", {
  kind: :integration,
  allow: %i[filesystem process]
}
  if linux_x86?
    map(
      (p) -> assert run_closures_exit(read_forms(p[0])[0]) == p[1],
      CLOSURE_PROGRAMS
    )
  end
end

test "a closure is a record at r15 and a call goes through r11"
  c = closure_code([], "f", [3])
  assert c[0] == {op: "lea_label", label: "f"}
  assert last(c) == {op: "add", dst: "r15", imm: 16}
  k = call_code(["g"], read_forms("g")[0], [1, 2])
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
    call_code([], 1, [1, 2, 3, 4, 5, 6, 7])
  rescue e
    e.kind
  end
  assert refused == :unsupported
end
