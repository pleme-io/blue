//! One line for every name a blue program can call without a `use`.
//!
//! The interpreter [`crate::interpreter`] builds binds 228 names a blue
//! call can spell (`blue_lang_syntax::is_callable_name`, measured 2026-09-29).
//! The reserved words among its bindings (`if`, `fn`, `case`, …) are described
//! with the keywords, and the kebab-case rest of tatara-lisp's stdlib is
//! unreachable, because the lexer reads `-` as an operator. Most are installed by tatara-lisp, which records no description,
//! and the rest by this crate's own layers. This table is where blue says what
//! each one does, in blue's calling form: `blue reference` prints it and
//! `docs/REFERENCE.md` is rendered from it.
//!
//! **It cannot drift from the runtime.** `blue-lang-cli/tests/reference.rs`
//! compares it with a live interpreter in both directions: a name the runtime
//! binds with no row here, a row naming nothing the runtime binds, and a
//! signature whose parameter count disagrees with the bound function's arity
//! are each a red build. A new primitive therefore arrives with its line or
//! does not arrive.
//!
//! Every line was checked against the runtime by running it, not read off a
//! name. Where a builtin is partial or surprising the line says so, because
//! that is what an author needs from it.
//!
//! # Signatures
//!
//! `name(a, b)` takes exactly two; `name(a[, b])` takes one or two;
//! `name(a, more...)` takes one or more. A name that is not a function (a
//! special form, a macro, a constant) is written the way a blue program uses
//! it, and its arity is not checked.

/// What a name is for, so a reference can group it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Topic {
    /// Evaluation forms: conditionals, bindings, quoting.
    Form,
    /// tatara-lisp forms whose arguments are Lisp shapes; usable from blue
    /// only where the shape is plain values.
    Lisp,
    Number,
    Text,
    List,
    Map,
    /// Functions that take or return functions.
    Function,
    /// Questions about a value's kind or sign.
    Predicate,
    Error,
    Json,
    File,
    Process,
    Environment,
    Clock,
    Crypto,
    /// Delayed values.
    Lazy,
    /// tatara-lisp's channels and fibers.
    Concurrency,
    /// Printing to the terminal.
    Output,
}

impl Topic {
    /// Every topic, in the order a reference presents them.
    pub const ALL: &'static [Topic] = &[
        Topic::Form,
        Topic::Number,
        Topic::Text,
        Topic::List,
        Topic::Map,
        Topic::Function,
        Topic::Predicate,
        Topic::Error,
        Topic::Json,
        Topic::File,
        Topic::Process,
        Topic::Environment,
        Topic::Clock,
        Topic::Crypto,
        Topic::Output,
        Topic::Lazy,
        Topic::Concurrency,
        Topic::Lisp,
    ];

    /// The heading a reference gives the topic.
    #[must_use]
    pub fn title(self) -> &'static str {
        match self {
            Topic::Form => "Forms",
            Topic::Lisp => "tatara-lisp forms",
            Topic::Number => "Numbers",
            Topic::Text => "Strings",
            Topic::List => "Lists",
            Topic::Map => "Maps",
            Topic::Function => "Functions",
            Topic::Predicate => "Predicates",
            Topic::Error => "Errors",
            Topic::Json => "JSON",
            Topic::File => "Files and paths",
            Topic::Process => "Processes",
            Topic::Environment => "Environment and arguments",
            Topic::Clock => "Time",
            Topic::Crypto => "Hashing and signatures",
            Topic::Lazy => "Delayed values",
            Topic::Concurrency => "Channels and fibers",
            Topic::Output => "Terminal output",
        }
    }
}

/// One bound name, described.
#[derive(Clone, Copy, Debug)]
pub struct NameDoc {
    pub name: &'static str,
    pub topic: Topic,
    /// How a blue program calls it. See the module docs for the grammar.
    pub signature: &'static str,
    /// One line: what it returns, and the trap in it when there is one.
    pub doc: &'static str,
}

/// `names! { topic: "name" "signature" "doc"; … }` — one row per name, so the
/// table reads as a table.
macro_rules! names {
    ($($topic:ident: $name:literal $sig:literal $doc:literal;)*) => {
        &[$(NameDoc { name: $name, topic: Topic::$topic, signature: $sig, doc: $doc },)*]
    };
}

/// Every name the full interpreter binds that a blue identifier can spell.
pub const NAMES: &[NameDoc] = names! {
    // ── forms ─────────────────────────────────────────────────────────────
    Form: "and" "and(a, b, more...)" "The last value if every one is truthy, else the first falsy one; stops early. The operator form is a && b.";
    Form: "or" "or(a, b, more...)" "The first truthy value, else the last; stops early. The operator form is a || b.";
    Form: "not" "not(x)" "true when x is false or nil. Written !x.";
    Form: "when" "when(c, body...)" "The body's last value when c is truthy, else nil. An if with no else says the same thing.";
    Form: "define" "define(name, value)" "Bind a name. Written name = value; the formatter prints that form.";
    Form: "set!" "set!(name, value)" "Rebind an existing name. A name a forked process inherited is sealed and refuses it.";
    Form: "begin" "begin(a, b, more...)" "Evaluate in order; the value is the last. A def body already does this.";
    Form: "lambda" "fn(x) … end" "The function form fn lowers to. Write fn.";
    Form: "quasiquote" "quote … end" "What quote with unquote lowers to inside defmacro.";
    Form: "try" "try(expr, catch(e(), handler))" "The value of expr, or of handler when expr throws. The binding is written e(). The kind and message of e cannot be read.";
    Form: "while" "while(c, body)" "Evaluate body while c is truthy; nil. Needs set! to make progress, so map, filter and reduce are usually the better word.";
    Form: "comment" "comment(anything...)" "Ignores its arguments and is nil. Use # comments instead.";
    Form: "eval" "eval(form)" "Evaluate a quoted form.";
    Form: "macroexpand" "macroexpand(form)" "The expansion of a quoted macro call, for debugging a defmacro.";
    Form: "delay" "delay(expr)" "A promise that evaluates expr once, on the first force.";
    // ── tatara-lisp forms ─────────────────────────────────────────────────
    Lisp: "let" "(let ((x 1)) …)" "Lisp binding form; its binding list has no blue spelling. In blue, write x = 1.";
    Lisp: "letrec" "(letrec ((f …)) …)" "Lisp recursive binding; its binding list has no blue spelling. In blue, use def.";
    Lisp: "cond" "(cond (test expr) …)" "Lisp multi-way conditional; its clauses have no blue spelling. In blue, use if … elsif … end.";
    Lisp: "require" "(require …)" "tatara-lisp's module loader. In blue, use(\"pkg\") imports a bidama.";
    Lisp: "provide" "(provide …)" "tatara-lisp's module export. A bidama exports every def.";
    Lisp: "dolist" "(dolist (x xs) …)" "Lisp loop; its binding list has no blue spelling. In blue, map(fn(x) … end, xs).";
    Lisp: "doseq" "(doseq (x xs) …)" "Same as dolist. In blue, map(fn(x) … end, xs).";
    Lisp: "dotimes" "(dotimes (i n) …)" "Lisp counted loop. In blue, map(fn(i) … end, range(n)).";
    Lisp: "match" "(match v (pattern expr) …)" "Lisp pattern matching; its patterns have no blue spelling. blue's case compares values and does not destructure.";
    Lisp: "defflow" "defflow(name, f, g, more...)" "Define name as a function that pipes its argument through f, then g: defflow(slug, trim, downcase).";
    Lisp: "defsm" "defsm(name, :initial, s, :transitions, [[from, event, to], …])" "Define a state machine. name(:send, event) moves it and returns the state; name(:current) reads it.";
    Lisp: "defstrategy" "defstrategy(name, :variant, f, …, :default, g)" "Define name(variant, args...) dispatching to the function under that keyword, or :default.";
    Lisp: "defvisitor" "defvisitor(name, :tag, f, …, :default, g)" "Define name(tagged) dispatching on the first element of a tagged list.";
    Lisp: "defactor" "defactor(name, initial, behaviour)" "A single-threaded actor with a mailbox. Its step message is :step!, which blue cannot spell, so from blue it can only be told, never stepped.";
    Lisp: "defcommand" "defcommand(bus, name, params, body)" "Register a command on a tatara-lisp command bus; params is a Lisp list.";
    Lisp: "defquery" "defquery(bus, name, params, body)" "Register a query on a tatara-lisp command bus; params is a Lisp list.";
    // ── numbers ───────────────────────────────────────────────────────────
    Number: "abs" "abs(x)" "Absolute value, keeping Int or Float.";
    Number: "min" "min(x, more...)" "The smallest argument. Takes numbers, not a list: apply(min, xs).";
    Number: "max" "max(x, more...)" "The largest argument. Takes numbers, not a list: apply(max, xs).";
    Number: "inc" "inc(x)" "x + 1.";
    Number: "dec" "dec(x)" "x - 1.";
    Number: "floor" "floor(x)" "The largest Int not above x. floor(a / b) is integer division.";
    Number: "ceiling" "ceiling(x)" "The smallest Int not below x.";
    Number: "round" "round(x)" "The nearest Int, halves away from zero: round(2.5) is 3, round(-2.5) is -3.";
    Number: "truncate" "truncate(x)" "The Int part of x, toward zero: truncate(-2.7) is -2.";
    Number: "mod" "mod(a, b)" "Euclidean remainder, never negative; what % lowers to.";
    Number: "modulo" "modulo(a, b)" "The same as mod.";
    Number: "rem" "rem(a, b)" "The same as mod here: mod(-7, 3), modulo and rem are all 2.";
    Number: "gcd" "gcd(xs...)" "Greatest common divisor of the arguments; 0 for none.";
    Number: "lcm" "lcm(xs...)" "Least common multiple of the arguments.";
    Number: "expt" "expt(base, power)" "base raised to power: expt(2, 10) is 1024.";
    Number: "sqrt" "sqrt(x)" "Square root, always a Float: sqrt(16) is 4.0, and 4.0 == 4.";
    Number: "exp" "exp(x)" "e to the x, a Float.";
    Number: "log" "log(x[, base])" "Natural logarithm, or log to base: log(100, 10) is 2.0.";
    Number: "sin" "sin(x)" "Sine of x radians.";
    Number: "cos" "cos(x)" "Cosine of x radians.";
    Number: "tan" "tan(x)" "Tangent of x radians.";
    Number: "asin" "asin(x)" "Arcsine; refuses x outside [-1, 1] rather than returning NaN.";
    Number: "acos" "acos(x)" "Arccosine; refuses x outside [-1, 1] rather than returning NaN.";
    Number: "atan" "atan(x)" "Arctangent in radians.";
    Number: "atan2" "atan2(y, x)" "The angle of the point (x, y); y comes first.";
    Number: "hypot" "hypot(x, y)" "sqrt(x * x + y * y) without the overflow: hypot(3, 4) is 5.0.";
    Number: "to_int" "to_int(x)" "An Int from a string or a number, truncating a Float; nil for text that is not an integer (\"3.7\" too).";
    Number: "to_int!" "to_int!(x)" "Like to_int, but raises instead of returning nil.";
    Number: "to_float" "to_float(x)" "A Float from a number or a numeric string.";
    Number: "compare" "compare(a, b)" "-1, 0 or 1. Total over two numbers or two strings, which < is not; mixing them raises.";
    // ── strings ───────────────────────────────────────────────────────────
    Text: "concat" "concat(x, more...)" "The text of every argument joined, each rendered with to_s. What interpolation lowers to.";
    Text: "to_s" "to_s(x)" "Text for any value (okite D0005, D0006): nil is \"\", 1.0 is \"1.0\", a list or map its blue literal, a keyword its name.";
    Text: "string" "string(x)" "tatara-lisp's rendering: :a stays \":a\" and a list prints as (1). Use to_s.";
    Text: "upcase" "upcase(s)" "The string in upper case. Raises on nil.";
    Text: "downcase" "downcase(s)" "The string in lower case. Raises on nil.";
    Text: "trim" "trim(s)" "The string without leading and trailing whitespace.";
    Text: "split" "split(s, sep)" "The fields between separators, empty ones kept (okite D0012): split(\"a,b,\", \",\") is [\"a\", \"b\", \"\"]. An empty sep splits into characters.";
    Text: "join" "join(xs, sep)" "The elements' text with sep between. The LIST comes first here, and the string first in split.";
    Text: "replace" "replace(s, from, to)" "Every occurrence of from replaced by to.";
    Text: "chars" "chars(s)" "The characters as one-character strings.";
    Text: "starts_with?" "starts_with?(s, prefix)" "Whether s begins with prefix.";
    Text: "ends_with?" "ends_with?(s, suffix)" "Whether s ends with suffix.";
    Text: "contains?" "contains?(s, sub)" "Whether the STRING s contains sub. On a list it raises: use member?(x, xs).";
    // ── lists ─────────────────────────────────────────────────────────────
    List: "list" "list(xs...)" "A list of the arguments. Written [a, b].";
    List: "length" "length(xs)" "The length of a list or string. Raises on nil: retsu's size(xs) is total.";
    List: "count" "count(xs)" "The number of elements; 0 for nil.";
    List: "nth" "nth(i, xs)" "The element at index i, from 0; nil past either end. The INDEX comes first.";
    List: "first" "first(xs)" "The first element; raises on []. retsu's first answers nil.";
    List: "second" "second(xs)" "The second element; raises when there is none.";
    List: "third" "third(xs)" "The third element; raises when there is none.";
    List: "fourth" "fourth(xs)" "The fourth element; raises when there is none.";
    List: "last" "last(xs)" "The last element; raises on []. retsu's last answers nil.";
    List: "rest" "rest(xs)" "All but the first; raises on []. retsu's rest answers [].";
    List: "next" "next(xs)" "All but the first; raises on [].";
    List: "butlast" "butlast(xs)" "All but the last; raises on [].";
    List: "car" "car(xs)" "The first element. Prefer first.";
    List: "cdr" "cdr(xs)" "All but the first ([] for a one-element list); raises on []. Prefer rest.";
    List: "cons" "cons(x, xs)" "A new list with x in front. Copies xs.";
    List: "append" "append(lists...)" "The lists joined, in order; nil counts as []. Copies, so growing a list one element at a time is quadratic.";
    List: "take" "take(n, xs)" "The first n elements, or all of them. The COUNT comes first.";
    List: "drop" "drop(n, xs)" "All but the first n. The COUNT comes first.";
    List: "reverse" "reverse(xs)" "The list or string backwards. Raises on nil.";
    List: "range" "range(a[, b][, step])" "Ints from a up to but not including b by step; range(n) is 0 to n - 1. Native, so any length is safe.";
    List: "flatten" "flatten(xs)" "Every nested list spliced in, to any depth.";
    List: "distinct" "distinct(xs)" "The elements with repeats removed, first occurrence kept, compared with ==.";
    List: "frequencies" "frequencies(xs)" "A map from each element to how many times it occurs.";
    List: "zip" "zip(xs, ys)" "[[x1, y1], [x2, y2], …], as long as the shorter list.";
    List: "interleave" "interleave(xs, ys)" "[x1, y1, x2, y2, …], as long as the shorter list allows.";
    List: "intersperse" "intersperse(sep, xs)" "xs with sep between each pair. The SEPARATOR comes first.";
    List: "position" "position(x, xs)" "The index of the first element == x, or -1.";
    List: "member?" "member?(x, xs)" "Whether some element == x. The ELEMENT comes first.";
    List: "partition" "partition(f, xs)" "[kept, rejected]: the elements f accepts, then the rest.";
    List: "sort_keyed" "sort_keyed(key, xs)" "A stable sort by key(x), under compare's rules; native, so safe at any length. Mixed key kinds raise.";
    List: "iterate" "iterate(f, x, n)" "[x, f(x), f(f(x)), …], n elements.";
    List: "repeatedly" "repeatedly(f, n)" "A list of n calls to the zero-argument function f. The FUNCTION comes first.";
    // ── maps ──────────────────────────────────────────────────────────────
    Map: "get" "get(m, k)" "The value at key k, or nil. Raises on nil and on a list.";
    Map: "assoc" "assoc(m, k, v)" "A new map with k set to v. Copies m; raises on nil.";
    Map: "dissoc" "dissoc(m, k)" "A new map without k; unchanged when k is absent.";
    Map: "zipmap" "zipmap(keys, values)" "A map pairing keys with values, as long as the shorter list.";
    // ── functions ─────────────────────────────────────────────────────────
    Function: "map" "map(f, xs, more...)" "f applied to each element; with two lists, f(x, y) pairwise. The FUNCTION comes first. nil maps to [].";
    Function: "filter" "filter(f, xs)" "The elements f accepts. The FUNCTION comes first.";
    Function: "remove" "remove(f, xs)" "The elements f rejects.";
    Function: "reduce" "reduce(f, [init, ]xs)" "Fold from the left: reduce(fn(acc, x) … end, 0, xs). Without init, the first element is the start.";
    Function: "foldl" "foldl(f, init, xs)" "reduce with an init: f(acc, x) from the left.";
    Function: "foldr" "foldr(f, init, xs)" "Fold from the right: f(x, acc).";
    Function: "find" "find(f, xs)" "The first element f accepts, or nil.";
    Function: "some" "some(f, xs)" "true when f accepts an element, else nil (not false).";
    Function: "any?" "any?(f, xs)" "Whether f accepts some element; false for [].";
    Function: "every?" "every?(f, xs)" "Whether f accepts every element; true for [].";
    Function: "apply" "apply(f, args..., xs)" "Call f with the elements of the last list as its arguments: apply(max, [3, 1]).";
    Function: "identity" "identity(x)" "x.";
    Function: "const" "const(x)" "A function that ignores its argument and returns x.";
    Function: "comp" "comp(f, g)" "The function x -> f(g(x)).";
    Function: "compose" "compose(fs...)" "Right to left: compose(f, g)(x) is f(g(x)).";
    Function: "pipe" "pipe(fs...)" "Left to right: pipe(f, g)(x) is g(f(x)).";
    Function: "partial" "partial(f, args...)" "f with its first arguments fixed: partial(f, 1)(2) is f(1, 2).";
    Function: "flip" "flip(f)" "f with its two arguments swapped.";
    Function: "juxt" "juxt(fs...)" "The function x -> [f(x), g(x), …].";
    Function: "tap" "tap(f, x)" "Call f(x) for its effect and return x.";
    Function: "memoize" "memoize(f)" "f, remembering each argument's answer.";
    Function: "decorate" "decorate(f, keys-and-values...)" "f with metadata attached; it still calls as f.";
    Function: "visit" "visit(f, x)" "f(x).";
    // ── predicates ────────────────────────────────────────────────────────
    Predicate: "nil?" "nil?(x)" "Whether x is nil (okite D0010). x == nil says the same.";
    Predicate: "bool?" "bool?(x)" "Whether x is true or false.";
    Predicate: "boolean?" "boolean?(x)" "The same as bool?.";
    Predicate: "integer?" "integer?(x)" "Whether x is an Int; integer?(1.0) is false.";
    Predicate: "float?" "float?(x)" "Whether x is a Float. 6 / 2 is the Int 3, while 7 / 2 is 3.5.";
    Predicate: "number?" "number?(x)" "Whether x is an Int or a Float.";
    Predicate: "string?" "string?(x)" "Whether x is a string.";
    Predicate: "keyword?" "keyword?(x)" "Whether x is a keyword such as :done.";
    Predicate: "symbol?" "symbol?(x)" "Whether x is a Lisp symbol; false for keywords.";
    Predicate: "list?" "list?(x)" "Whether x is a list. list?(nil) is true, so test x == nil first.";
    Predicate: "map?" "map?(x)" "Whether x is a map. A parsed JSON object is not one.";
    Predicate: "procedure?" "procedure?(x)" "Whether x can be called.";
    Predicate: "empty?" "empty?(xs)" "Whether xs is nil or has no elements.";
    Predicate: "null?" "null?(x)" "Whether x is nil or []. The Lisp word; prefer retsu's is_empty.";
    Predicate: "pair?" "pair?(x)" "Whether x is a non-empty list.";
    Predicate: "atom?" "atom?(x)" "Whether x is a scalar rather than a list; false for nil.";
    Predicate: "some?" "some?(x)" "Whether x is not nil.";
    Predicate: "even?" "even?(n)" "Whether n is even.";
    Predicate: "odd?" "odd?(n)" "Whether n is odd.";
    Predicate: "zero?" "zero?(n)" "Whether n is 0.";
    Predicate: "positive?" "positive?(n)" "Whether n > 0.";
    Predicate: "negative?" "negative?(n)" "Whether n < 0.";
    Predicate: "equal?" "equal?(a, b)" "Structural equality; what == lowers to.";
    Predicate: "eq?" "eq?(a, b)" "Identity: true for the same keyword or string, false for two equal lists. Use ==.";
    Predicate: "is?" "is?(x, type)" "Whether x has the type named by a keyword: is?(5, :int). Value first.";
    Predicate: "the" "the(type, x)" "x, after asserting its type: the(:int, 5). Type first.";
    Predicate: "cast" "cast(type, x)" "x checked against, or narrowed to, the type a keyword names: cast(:float, 5) is 5.0. Type first.";
    Predicate: "foreign?" "foreign?(x)" "Whether x is an opaque value a host handed in.";
    Predicate: "promise?" "promise?(x)" "Whether x is a delayed value.";
    Predicate: "chan?" "chan?(x)" "Whether x is a channel.";
    Predicate: "go?" "go?(x)" "Whether x is a fiber.";
    // ── errors ────────────────────────────────────────────────────────────
    Error: "error" "error(kind, message[, data])" "An error VALUE. It raises nothing until throw(error(…)).";
    Error: "throw" "throw(err)" "Raise err. Uncaught, the run fails with its kind and message.";
    Error: "error?" "error?(x)" "Whether x is an error value; true inside a catch handler.";
    Error: "gensym" "gensym([prefix])" "A fresh unique symbol, for macros that need a private name.";
    Lisp: "builtin_names" "builtin_names()" "Every name this reference documents, as strings: what a bare name falls to when no definition or import has it. A catalogue reads it to say which definitions share a builtin's name.";
    // ── JSON ──────────────────────────────────────────────────────────────
    Json: "json_parse" "json_parse(text)" "Parse JSON. An object becomes a list of [key, value] pairs, not a map; read it with json_get or deeta. null is nil.";
    Json: "json_stringify" "json_stringify(v)" "Compact JSON text, a map's keys sorted, a keyword as its name.";
    Json: "json_get" "json_get(obj, key)" "The field of a parsed JSON object, or nil. Raises when obj is not an object.";
    Json: "json_get_or" "json_get_or(obj, key, default)" "The field of a parsed JSON object, or default.";
    // ── files ─────────────────────────────────────────────────────────────
    File: "read_file" "read_file(path)" "The file's text. Raises when it cannot be read; shisutemu's read_or(path, default) does not.";
    File: "write_file" "write_file(path, text)" "Replace the file's contents with text; nil.";
    File: "append_file" "append_file(path, text)" "Add text to the end of the file, creating it; nil.";
    File: "rename_file" "rename_file(from, to)" "Move a file, atomically on one filesystem: write a temporary beside to, then rename.";
    File: "rm" "rm(path)" "Delete a file; raises when it is absent.";
    File: "rm_rf" "rm_rf(path)" "Delete a file or a directory tree; nil when there is nothing.";
    File: "mkdir" "mkdir(path)" "Create one directory; nil if it exists.";
    File: "mkdir_p" "mkdir_p(path)" "Create a directory and its parents.";
    File: "path_exists" "path_exists(path)" "Whether anything is at path.";
    File: "is_file?" "is_file?(path)" "Whether path is a regular file.";
    File: "is_dir?" "is_dir?(path)" "Whether path is a directory.";
    File: "file_size" "file_size(path)" "The size in bytes.";
    File: "file_mtime_ms" "file_mtime_ms(path)" "The last modification time, in Unix milliseconds.";
    File: "ls" "ls(dir)" "The entries of a directory as full paths, sorted.";
    File: "walk_dir" "walk_dir(root)" "Every file under root, as paths, in no fixed order: sort before comparing.";
    File: "glob" "glob(pattern)" "Paths matching * and ** relative to the current directory. An absolute pattern finds nothing; walk_dir and filter instead.";
    File: "path_join" "path_join(part, more...)" "The parts joined with /.";
    File: "path_basename" "path_basename(path)" "The last component: \"b.txt\" of \"a/b.txt\".";
    File: "path_dirname" "path_dirname(path)" "Everything before the last component.";
    File: "path_extension" "path_extension(path)" "The extension without its dot, or nil.";
    File: "cwd" "cwd()" "The current directory.";
    // ── processes ─────────────────────────────────────────────────────────
    Process: "exec_capture" "exec_capture(cmd, args...)" "Run a command, no shell: [[:status, n], [:stdout, s], [:stderr, s]]. Read it with shisutemu's status_of and stdout_of.";
    Process: "exec_check" "exec_check(cmd, args...)" "Run a command, no shell; its exit status as an Int. Output passes through.";
    Process: "exec_ok?" "exec_ok?(cmd, args...)" "Whether a command exits 0.";
    Process: "exec_with_stdin" "exec_with_stdin(input, cmd, args...)" "exec_capture, with input written to the command's stdin. The INPUT comes first.";
    Process: "exec_with_env" "exec_with_env(env, cmd, args...)" "exec_capture with extra environment variables, given as [[name, value], …].";
    Process: "exec_into" "exec_into(env, cmd, args...)" "Replace this process with a command run with extra environment variables, given as [[name, value], …]; stdio is inherited. Returns only by raising, when the command cannot start.";
    Process: "sh_exec" "sh_exec(script)" "Run a script through sh; the same result as exec_capture. Prefer exec_capture, which cannot be injected into.";
    // ── environment ───────────────────────────────────────────────────────
    Environment: "getenv" "getenv(name[, default])" "An environment variable, or default (nil when none is given).";
    Environment: "env_required" "env_required(name)" "An environment variable; raises, naming it, when unset.";
    Environment: "argv" "argv()" "The program's own arguments: what follows the file in blue run file -- a b.";
    Environment: "argv_get" "argv_get(i[, default])" "One argument by index, or default.";
    Environment: "self_exe" "self_exe()" "The path of the blue running this program, or nil outside the CLI. Spawn it to run blue; a sandbox has no blue on PATH.";
    // ── time ──────────────────────────────────────────────────────────────
    Clock: "now" "now()" "Unix time in seconds.";
    Clock: "now_ms" "now_ms()" "Unix time in milliseconds.";
    Clock: "now_ns" "now_ns()" "Unix time in nanoseconds.";
    Clock: "now_rfc3339" "now_rfc3339()" "The current UTC time as RFC 3339 text.";
    Clock: "elapsed_since" "elapsed_since(start_ns)" "Nanoseconds since start_ns, a value of now_ns().";
    Clock: "sleep" "sleep(seconds)" "Pause for whole seconds.";
    Clock: "sleep_ms" "sleep_ms(ms)" "Pause for milliseconds.";
    // ── crypto ────────────────────────────────────────────────────────────
    Crypto: "blake3_hex" "blake3_hex(data)" "The BLAKE3-256 hash of a string or byte list, in lowercase hex. shomei's hash_message wraps it.";
    Crypto: "ed25519_keypair" "ed25519_keypair(seed_hex)" "[secret, public] in hex for a 32-byte seed. There is no entropy source: the caller supplies the seed.";
    Crypto: "ed25519_sign" "ed25519_sign(secret_hex, message)" "The Ed25519 signature of a message, in hex.";
    Crypto: "ed25519_verify" "ed25519_verify(public_hex, message, signature_hex)" "Whether the signature is valid.";
    // ── output ────────────────────────────────────────────────────────────
    Output: "write_stdout" "write_stdout(text)" "Write text to stdout exactly, no newline added. The way a command prints.";
    Output: "write_stderr" "write_stderr(text)" "Write text to stderr exactly.";
    Output: "println" "println(xs...)" "Print values with a newline, strings with their quotes. For output a person reads, use write_stdout.";
    Output: "print" "print(x)" "Print a value and a newline, a string with its quotes.";
    Output: "display" "display(x)" "Print a value's Lisp rendering, no newline.";
    Output: "newline" "newline()" "Print a newline.";
    // ── delayed values ────────────────────────────────────────────────────
    Lazy: "force" "force(p)" "The value of a promise, computed once; a non-promise is returned as is.";
    Lazy: "cycle" "cycle(xs)" "A tatara-lisp lazy sequence repeating xs. blue's list words do not force it: take(2, cycle(xs)) is not a plain list.";
    Lazy: "realize" "realize(lazy)" "A finite tatara-lisp lazy sequence forced into a list. On anything built from cycle it does not terminate.";
    // ── concurrency ───────────────────────────────────────────────────────
    Concurrency: "chan" "chan([capacity])" "A tatara-lisp channel. Its put and take words (>! and <!) have no blue spelling.";
    Concurrency: "close!" "close!(ch)" "Close a channel.";
    Concurrency: "drain!" "drain!(ch)" "Every value waiting in a channel, as a list.";
    Concurrency: "go" "go(f)" "A pending fiber for a zero-argument function. Running it (go-run) has no blue spelling.";
};

/// The row for a name, if blue describes it.
#[must_use]
pub fn doc_of(name: &str) -> Option<&'static NameDoc> {
    NAMES.iter().find(|d| d.name == name)
}
