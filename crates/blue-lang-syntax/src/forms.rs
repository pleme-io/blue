//! The surface forms, one row each: how a form is written, the tatara-lisp
//! tree it lowers to, and one line on what it means.
//!
//! This is the table `blue reference` prints as the grammar card. A reference
//! written by hand next to a parser drifts the first time the parser changes;
//! here every row's `example` is parsed by the real parser in
//! `every_form_lowers_as_its_row_says`, and the tree must be exactly
//! `lowers_to`. So a row that stops being true is a red build, not a stale
//! document.
//!
//! Operators live in [`crate::parse::INFIX`] and reserved words in
//! [`crate::parse::SURFACE_KEYWORDS`] / [`crate::parse::BLOCK_KEYWORDS`],
//! each with its own line; this table holds the forms that are neither.

/// One surface form.
#[derive(Clone, Copy, Debug)]
pub struct Form {
    /// The form as an author writes it. Parsed by the gate.
    pub example: &'static str,
    /// The tree `example` parses to, as `Sexp`'s `Display` prints it.
    pub lowers_to: &'static str,
    /// One line for a reader.
    pub doc: &'static str,
}

/// Every surface form that is not an operator or a keyword.
pub const FORMS: &[Form] = &[
    Form {
        example: "42",
        lowers_to: "42",
        doc: "An Int. Six or more digits are grouped by threes, 1_000_000; fewer are not (B0033).",
    },
    Form {
        example: "3.5",
        lowers_to: "3.5",
        doc: "A Float.",
    },
    Form {
        example: "\"text\"",
        lowers_to: "\"text\"",
        doc: "A string. Escapes: \\n, \\t, \\\", \\\\, \\u{1b}; a character a reader cannot see is always escaped (B0033).",
    },
    Form {
        example: "\"n = #{n}!\"",
        lowers_to: "(concat (concat \"n = \" n) \"!\")",
        doc: "Interpolation: any expression inside #{…}, rendered with to_s. A literal that must contain #{ is built with concat(\"#\", \"{\").",
    },
    Form {
        example: ":done",
        lowers_to: ":done",
        doc: "A keyword: a name as a value. It may not end in ? or !.",
    },
    Form {
        example: "[1, \"a\"]",
        lowers_to: "(list 1 \"a\")",
        doc: "A list. Indexing is nth(i, xs); blue has no xs[i].",
    },
    Form {
        example: "%w[a b]",
        lowers_to: "(list \"a\" \"b\")",
        doc: "A list of strings, one per word, separated by spaces. The formatter writes any literal list of two or more such strings this way. Only [ ] delimits it, and a word holds no , \" ' # \\ [ ].",
    },
    Form {
        example: "%i[a b]",
        lowers_to: "(list :a :b)",
        doc: "A list of keywords, one per name: [:a, :b], written this way from two names on.",
    },
    Form {
        example: "{a: 1, \"k\" => 2}",
        lowers_to: "(hash-map :a 1 \"k\" 2)",
        doc: "A map. `a:` is the keyword key :a; `=>` takes any key. Read with get(m, k), extend with assoc(m, k, v).",
    },
    Form {
        example: "{a:, b:}",
        lowers_to: "(hash-map :a a :b b)",
        doc: "A map whose values are the variables of the same names: `{a:}` is `{a: a}`. Mix it with `{a:, n: 1}`.",
    },
    Form {
        example: "{**a, b: 1}",
        lowers_to: "(blue-merge (blue-splice a) (hash-map :b 1))",
        doc: "A map that inherits every key of a map, `**a`, and lets a later entry override it. nil spreads as an empty map; anything else that is not a map is a type error. The map sibling of the splat `*xs`.",
    },
    Form {
        example: "f(x, **a, b: 1)",
        lowers_to: "(f x (blue-kwargs (blue-splice a) (hash-map :b 1)))",
        doc: "A call whose last argument is the map built from `**` spreads and entries, `f(x, {**a, b: 1})` without the braces. Entries after a `**` are the call's last argument, so it cannot also carry a splat `*xs`.",
    },
    Form {
        example: "x = 5",
        lowers_to: "(define x 5)",
        doc: "A binding, only as a statement. There is no `let`; a binding lasts to the end of its body.",
    },
    Form {
        example: "f(x, y)",
        lowers_to: "(f x y)",
        doc: "A call. This is the one form the formatter writes, except for a function that takes no parameters: that is called by its bare name, now_ms, never now_ms() (B0023), and passed as a value as fn() now_ms end.",
    },
    Form {
        example: "f(a, *xs)",
        lowers_to: "(apply f a xs)",
        doc: "A splat: the list's elements are the call's last arguments. The one spelling of apply(f, a, xs) with f a name (B0042).",
    },
    Form {
        example: "(a, *rest) -> rest",
        lowers_to: "(lambda (a &rest rest) rest)",
        doc: "A rest parameter: `*name` last in a def, fn or arrow parameter list collects the remaining arguments into a list, the signature-side sibling of the call-side splat. A call passes every fixed parameter and any number more.",
    },
    Form {
        example: "def f(a, b?) b end",
        lowers_to: "(define (f a &optional b) b)",
        doc: "An optional parameter: `name?` after the required ones in a def is nil when the call leaves it out. A call passes every required parameter and up to the optional ones; more raises, naming the range. A required or rest parameter cannot follow an optional one.",
    },
    Form {
        example: "cap.status",
        lowers_to: "(blue-field cap :status)",
        doc: "A field read: a map's keyword or string key, a keyed list such as exec_capture's result or a parsed JSON object, or an error's kind, message, data, cause or trace. A missing field raises naming the fields there are; get(m, :k) reads one that may be absent.",
    },
    Form {
        example: "x == nil",
        lowers_to: "(blue-field x :nil?)",
        doc: "A nil test: x.nil? is true of nil and of nothing else. Read, and written x.nil?, from nil?(x), x == nil and nil == x (B0047).",
    },
    Form {
        example: "x.f(y)",
        lowers_to: "(f x y)",
        doc: "A method-style call: the receiver becomes the first argument. Read, and written f(x, y) (B0028).",
    },
    Form {
        example: "xs |> f(a)",
        lowers_to: "(f xs a)",
        doc: "A pipe: the value becomes the FIRST argument. Read, and written f(xs, a) (B0028). map(f, xs) is function-first: xs |> map(f) is map(xs, f), an error.",
    },
    Form {
        example: "not x",
        lowers_to: "(not x)",
        doc: "Negation; `!x` is read and written `not x` (B0025).",
    },
    Form {
        example: "-x",
        lowers_to: "(- 0 x)",
        doc: "Unary minus. The formatter writes 0 - x as -x.",
    },
    Form {
        example: "use(\"retsu\")",
        lowers_to: "(use \"retsu\")",
        doc: "Import a bidama by name, found on BLUE_PATH. Every definition it makes joins one flat namespace.",
    },
    Form {
        example: "raise(:parse, \"bad row\")",
        lowers_to: "(raise :parse \"bad row\")",
        doc: "Raise an error; raise(:k, \"m\", {data: d, cause: e}) attaches data and the error it wraps, raise(e) raises e again. throw(error(…)) is read as this (B0037).",
    },
    Form {
        example: "risky(x) rescue fallback",
        lowers_to: "(try (risky x) (catch (_) fallback))",
        doc: "The value of risky(x), or fallback when it raises. Binds loosest of all, below |>.",
    },
    Form {
        example: "begin\n  risky(x)\nrescue :timeout as e\n  wait(e)\nend",
        lowers_to: "(try (risky x) (catch (rescued-error) (cond ((blue-rescues? rescued-error :timeout) (let ((e rescued-error)) (wait e))) (else (blue-reraise rescued-error)))))",
        doc: "Catch by kind, binding the error; `rescue e` (last) catches every error, an unmatched kind raises again, and `ensure` runs on both paths. A def body takes the same clauses without begin.",
    },
    Form {
        example: "test \"isolated\", {satisfies: [:nist_ac_6], target: parse}\n  assert parse(1)\nend",
        lowers_to: "(deftest \"isolated\" (blue-test-meta (hash-map :satisfies (list :nist_ac_6) :target parse)) (blue-assert '(parse 1) (parse 1)))",
        doc: "A test that declares the controls it verifies, each a catalog keyword (:nist_ac_6 is NIST_SP_800_53R5_AC_6, B0069), and the definition it targets. `blue test --facts` hands both, with each one's def_hash, to tameshi. Written satisfies then target, the controls sorted (B0068).",
    },
    Form {
        example: "@doc \"\"\"\ninc adds one to a number.\n\n    inc(1) #=> 2\n\"\"\"\ndef inc(n)\n  n + 1\nend",
        lowers_to: "(blue-doc \"inc adds one to a number.\\n\\n    inc(1) #=> 2\" (define (inc n) (+ n 1)))",
        doc: "Documents the definition below it: one sentence of intent starting with its name, then an indented example whose `expr #=> value` lines `blue test` runs as tests. A heredoc: no escapes, no interpolation. Everything else about a definition is derived (B0056–B0060).",
    },
    Form {
        example: "@moduledoc \"\"\"\nkazu holds the number verbs.\n\n    kazu::clamp(9, 1, 5) #=> 5\n\"\"\"",
        lowers_to: "(blue-moduledoc \"kazu holds the number verbs.\\n\\n    kazu::clamp(9, 1, 5) #=> 5\")",
        doc: "Documents a whole file, a bidama: its purpose and one whole example. The first form of the file.",
    },
];

#[cfg(test)]
mod tests {
    use super::FORMS;
    use crate::parse::{
        keyword_doc, parse_program_documented, BLOCK_KEYWORDS, INFIX, SURFACE_KEYWORDS,
    };

    fn lowered(src: &str) -> String {
        parse_program_documented(src)
            .unwrap_or_else(|e| panic!("`{src}` does not parse: {e}"))
            .iter()
            .map(|f| f.to_sexp().to_string())
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Red run, 2026-09-29: changing the pipe row's `lowers_to` to
    /// `(f a xs)` failed with "`xs |> f(a)` lowers to (f xs a), and its row
    /// says (f a xs)".
    #[test]
    fn every_form_lowers_as_its_row_says() {
        for form in FORMS {
            let got = lowered(form.example);
            assert_eq!(
                got, form.lowers_to,
                "`{}` lowers to {got}, and its row says {}",
                form.example, form.lowers_to
            );
        }
    }

    /// Red run, 2026-09-29: emptying the `"%"` row's doc failed with
    /// "the operator `%` has no doc"; deleting the `"case"` arm of
    /// `keyword_doc` failed with "the keyword `case` has no doc".
    #[test]
    fn every_operator_and_keyword_is_described() {
        for op in INFIX {
            assert!(
                !op.doc.trim().is_empty(),
                "the operator `{}` has no doc",
                op.op
            );
        }
        for word in SURFACE_KEYWORDS.iter().chain(BLOCK_KEYWORDS) {
            assert!(
                !keyword_doc(word).trim().is_empty(),
                "the keyword `{word}` has no doc"
            );
        }
        for form in FORMS {
            assert!(
                !form.doc.trim().is_empty(),
                "the form `{}` has no doc",
                form.example
            );
        }
    }
}
