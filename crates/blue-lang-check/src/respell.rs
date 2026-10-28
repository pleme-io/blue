use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::rules::Code;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Respell {
    Rename(&'static str),
    CompareNil(&'static str),
    Field(&'static str),
    Raise,
    Chain(&'static crate::chains::ChainRule),
    TextName(usize),
}

pub struct Synonym {
    pub name: &'static str,
    pub argc: usize,
    pub respell: Respell,
    pub code: Code,
    pub written: &'static str,
}

pub const SYNONYMS: &[Synonym] = &[
    Synonym {
        name: "car",
        argc: 1,
        respell: Respell::Rename("first"),
        code: Code::B0036,
        written: "first(xs)",
    },
    Synonym {
        name: "cdr",
        argc: 1,
        respell: Respell::Rename("rest"),
        code: Code::B0036,
        written: "rest(xs)",
    },
    Synonym {
        name: "next",
        argc: 1,
        respell: Respell::Rename("rest"),
        code: Code::B0036,
        written: "rest(xs)",
    },
    Synonym {
        name: "modulo",
        argc: 2,
        respell: Respell::Rename("mod"),
        code: Code::B0036,
        written: "a % b",
    },
    Synonym {
        name: "rem",
        argc: 2,
        respell: Respell::Rename("mod"),
        code: Code::B0036,
        written: "a % b",
    },
    Synonym {
        name: "bool?",
        argc: 1,
        respell: Respell::Rename("boolean?"),
        code: Code::B0036,
        written: "boolean?(x)",
    },
    Synonym {
        name: "comp",
        argc: 2,
        respell: Respell::Rename("compose"),
        code: Code::B0036,
        written: "compose(f, g)",
    },
    Synonym {
        name: "foldl",
        argc: 3,
        respell: Respell::Rename("reduce"),
        code: Code::B0036,
        written: "reduce(f, init, xs)",
    },
    Synonym {
        name: "nil?",
        argc: 1,
        respell: Respell::Field("nil?"),
        code: Code::B0047,
        written: "x.nil?",
    },
    Synonym {
        name: "some?",
        argc: 1,
        respell: Respell::CompareNil("not="),
        code: Code::B0036,
        written: "x != nil",
    },
    Synonym {
        name: "error_kind",
        argc: 1,
        respell: Respell::Field("kind"),
        code: Code::B0036,
        written: "e.kind",
    },
    Synonym {
        name: "error_message",
        argc: 1,
        respell: Respell::Field("message"),
        code: Code::B0036,
        written: "e.message",
    },
    Synonym {
        name: "throw",
        argc: 1,
        respell: Respell::Raise,
        code: Code::B0037,
        written: "raise(…)",
    },
];

pub const TEXT_NAMES: &[(&str, usize)] = &[("error", 1), ("json_get", 2), ("json_get_or", 2)];

#[must_use]
pub fn text_name(builtin: &str) -> Option<usize> {
    TEXT_NAMES
        .iter()
        .find(|(name, _)| *name == builtin)
        .map(|(_, at)| *at)
}

#[must_use]
pub fn name_string(node: &Spanned) -> Option<&str> {
    match &node.form {
        SpannedForm::Atom(Atom::Str(s))
            if blue_lang_syntax::words::is_symbol_name(s)
                && node.span.end - node.span.start == s.len() + 2 =>
        {
            Some(s)
        }
        _ => None,
    }
}

#[must_use]
pub fn synonym(name: &str, argc: usize) -> Option<&'static Synonym> {
    SYNONYMS.iter().find(|s| s.name == name && s.argc == argc)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Respelling {
    pub span: Span,
    pub respell: Respell,
    pub qualify: bool,
    pub error_builtin: bool,
}

fn sym(span: Span, s: &str) -> Spanned {
    Spanned::new(span, SpannedForm::Atom(Atom::Symbol(s.to_string())))
}

fn qualified(name: &str, qualify: bool) -> String {
    if qualify {
        blue_lang_syntax::qualify(blue_lang_syntax::BUILTIN_QUALIFIER, name)
    } else {
        name.to_string()
    }
}

#[must_use]
pub fn apply(call: &Spanned, items: &[Spanned], r: &Respelling) -> Spanned {
    let head = &items[0];
    let list = |v: Vec<Spanned>| Spanned::new(call.span, SpannedForm::List(v));
    match r.respell {
        Respell::Chain(_) => items[1].clone(),
        Respell::TextName(at) => {
            let mut out = items.to_vec();
            if let Some(SpannedForm::Atom(Atom::Str(text))) = out.get(at).map(|a| a.form.clone()) {
                out[at] = Spanned::new(out[at].span, SpannedForm::Atom(Atom::Keyword(text)));
            }
            list(out)
        }
        Respell::Rename(to) => {
            let mut out = items.to_vec();
            out[0] = sym(head.span, &qualified(to, r.qualify && to != "mod"));
            list(out)
        }
        Respell::CompareNil(op) => list(vec![
            sym(head.span, op),
            items[1].clone(),
            Spanned::new(head.span, SpannedForm::Nil),
        ]),
        Respell::Field(f) => list(vec![
            sym(head.span, blue_lang_syntax::LOWERED_FIELD),
            items[1].clone(),
            Spanned::new(head.span, SpannedForm::Atom(Atom::Keyword(f.to_string()))),
        ]),
        Respell::Raise => {
            let raise = sym(head.span, &qualified("raise", r.qualify));
            let inner = items[1].as_list().filter(|i| {
                r.error_builtin
                    && (i.len() == 3 || i.len() == 4)
                    && i[0].as_symbol() == Some("error")
            });
            match inner {
                Some(i) => {
                    let mut out = vec![raise, i[1].clone(), i[2].clone()];
                    let empty = |d: &Spanned| {
                        matches!(d.as_list(), Some([h]) if h.as_symbol() == Some("list"))
                            || matches!(d.form, SpannedForm::Nil)
                    };
                    if let Some(d) = i.get(3).filter(|d| !empty(d)) {
                        out.push(Spanned::new(
                            d.span,
                            SpannedForm::List(vec![
                                sym(d.span, blue_lang_syntax::LOWERED_MAP),
                                Spanned::new(
                                    d.span,
                                    SpannedForm::Atom(Atom::Keyword("data".to_string())),
                                ),
                                d.clone(),
                            ]),
                        ));
                    }
                    list(out)
                }
                None => list(vec![raise, items[1].clone()]),
            }
        }
    }
}
