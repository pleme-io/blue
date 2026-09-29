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
        doc: "An Int. Underscores may separate digits: 1_000.",
    },
    Form {
        example: "3.5",
        lowers_to: "3.5",
        doc: "A Float.",
    },
    Form {
        example: "\"text\"",
        lowers_to: "\"text\"",
        doc: "A string. Escapes: \\n, \\t, \\\", \\\\, \\u{1b}.",
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
        example: "{a: 1, \"k\" => 2}",
        lowers_to: "(hash-map :a 1 \"k\" 2)",
        doc: "A map. `a:` is the keyword key :a; `=>` takes any key. Read with get(m, k), extend with assoc(m, k, v).",
    },
    Form {
        example: "x = 5",
        lowers_to: "(define x 5)",
        doc: "A binding, only as a statement. There is no `let`; a binding lasts to the end of its body.",
    },
    Form {
        example: "f(x, y)",
        lowers_to: "(f x y)",
        doc: "A call. This is the one form the formatter writes.",
    },
    Form {
        example: "x.f(y)",
        lowers_to: "(f x y)",
        doc: "A method-style call: the receiver becomes the first argument. Formatted as f(x, y).",
    },
    Form {
        example: "xs |> f(a)",
        lowers_to: "(f xs a)",
        doc: "A pipe: the value becomes the FIRST argument, so it suits data-first words. map(f, xs) is function-first: xs |> map(f) is map(xs, f), an error.",
    },
    Form {
        example: "!x",
        lowers_to: "(not x)",
        doc: "Negation. `not(x)` is the same tree.",
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
        example: "throw(error(:parse, \"bad row\"))",
        lowers_to: "(throw (error :parse \"bad row\"))",
        doc: "Raise. error(kind, message) alone only builds the value; throw raises it, and uncaught it fails the run.",
    },
    Form {
        example: "try(risky(), catch(e(), fallback(e)))",
        lowers_to: "(try (risky) (catch (e) (fallback e)))",
        doc: "Catch a throw. The binding is written as a call, e(). error?(e) is true inside; the kind and message are not readable, so return refusals as data when a caller must tell them apart.",
    },
];

#[cfg(test)]
mod tests {
    use super::FORMS;
    use crate::parse::{keyword_doc, parse_program, BLOCK_KEYWORDS, INFIX, SURFACE_KEYWORDS};

    fn lowered(src: &str) -> String {
        parse_program(src)
            .unwrap_or_else(|e| panic!("`{src}` does not parse: {e}"))
            .iter()
            .map(ToString::to_string)
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
