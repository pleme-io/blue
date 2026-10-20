use std::collections::HashMap;

use blue_lang_syntax::{lex, parse_program, Atom, Sexp, TokenKind};

fn main() {
    let list = std::env::args().nth(1).expect("file list");
    let files = std::fs::read_to_string(list).expect("read list");
    println!("file\tkind\tn");
    for f in files.lines() {
        let Ok(src) = std::fs::read_to_string(f) else {
            continue;
        };
        let mut c: HashMap<String, usize> = HashMap::new();
        let mut bump = |k: &str| *c.entry(k.to_string()).or_default() += 1;
        if let Ok(toks) = lex(&src) {
            let sig: Vec<_> = toks
                .iter()
                .filter(|t| !matches!(t.kind, TokenKind::Comment(_)))
                .collect();
            for (i, t) in sig.iter().enumerate() {
                let text = &src[t.span.start..t.span.end];
                let next = sig.get(i + 1).map(|t| &t.kind);
                let prev = if i > 0 { Some(&sig[i - 1].kind) } else { None };
                match &t.kind {
                    TokenKind::Op(o) => {
                        bump(&format!("op {o}"));
                        if text != o {
                            bump(&format!("alias {text}"));
                        }
                    }
                    TokenKind::Pipe => bump("pipe"),
                    TokenKind::Dot => bump("send"),
                    TokenKind::Rocket => {
                        if matches!(prev, Some(TokenKind::Sym(_))) {
                            bump("rocket keyword key");
                        } else {
                            bump("rocket other key");
                        }
                    }
                    TokenKind::Label(_) => bump("label"),
                    TokenKind::Int(_) | TokenKind::Float(_) => {
                        if text.contains('_') {
                            bump("number underscore");
                        }
                        if text.contains(['e', 'E']) {
                            bump("number exponent");
                        }
                        let digits = text.chars().filter(char::is_ascii_digit).count();
                        if matches!(t.kind, TokenKind::Int(_)) && digits >= 6 {
                            bump("int 6+ digits");
                        }
                        if matches!(t.kind, TokenKind::Int(_)) && digits == 5 {
                            bump("int 5 digits");
                        }
                    }
                    TokenKind::Str(_) | TokenKind::InterpolatedStr { .. } => {
                        if text.contains("\\u{") {
                            bump("string unicode escape");
                        }
                        if text
                            .chars()
                            .any(|ch| ch.is_control() && ch != '\n' && ch != '\t')
                        {
                            bump("string raw control char");
                        }
                    }
                    TokenKind::Comma => {
                        let mut j = i + 1;
                        while matches!(sig.get(j).map(|t| &t.kind), Some(TokenKind::Newline)) {
                            j += 1;
                        }
                        if matches!(
                            sig.get(j).map(|t| &t.kind),
                            Some(TokenKind::RParen | TokenKind::RBracket | TokenKind::RBrace)
                        ) {
                            bump("trailing comma");
                        }
                    }
                    TokenKind::Ident(n) => {
                        match n.as_str() {
                            "unless" => bump("unless"),
                            "else" => {
                                let mut j = i + 1;
                                while matches!(
                                    sig.get(j).map(|t| &t.kind),
                                    Some(TokenKind::Newline)
                                ) {
                                    j += 1;
                                }
                                if matches!(sig.get(j).map(|t| &t.kind), Some(TokenKind::Ident(x)) if x == "if")
                                {
                                    bump("else then if");
                                }
                            }
                            "def" | "fn" => {
                                let paren_at = if n == "def" { i + 2 } else { i + 1 };
                                if !matches!(
                                    sig.get(paren_at).map(|t| &t.kind),
                                    Some(TokenKind::LParen)
                                ) {
                                    bump(&format!("{n} without parens"));
                                }
                            }
                            "and" | "or" | "not" => {
                                if matches!(next, Some(TokenKind::LParen)) {
                                    bump(&format!("call {n}("));
                                } else {
                                    bump(&format!("bare word {n}"));
                                }
                            }
                            _ => {}
                        }
                        if matches!(next, Some(TokenKind::LParen)) {
                            if let "car" | "cdr" | "next" | "modulo" | "rem" | "mod" | "bool?"
                            | "boolean?" | "comp" | "compose" | "foldl" | "reduce" | "nil?"
                            | "some?" | "when" | "eq?" | "null?" | "empty?" | "list"
                            | "equal?" | "concat" | "define" | "first" | "rest" | "print"
                            | "println" | "is_empty" = n.as_str()
                            {
                                bump(&format!("call {n}("));
                            }
                        }
                    }
                    _ => {}
                }
            }
            for ch in src.chars() {
                if "≠≤≥×÷−∧∨¬≡".contains(ch) {
                    bump(&format!("unicode {ch}"));
                }
            }
        }
        match parse_program(&src) {
            Ok(forms) => {
                let mut tests: HashMap<String, usize> = HashMap::new();
                for f in &forms {
                    walk(f, &mut |s| tree(s, &mut bump, &mut tests));
                }
                for (_, n) in tests {
                    if n > 1 {
                        bump("duplicate test name");
                    }
                }
            }
            Err(_) => bump("PARSE ERROR"),
        }
        for (k, n) in c {
            println!("{f}\t{k}\t{n}");
        }
    }
}

fn walk(s: &Sexp, f: &mut dyn FnMut(&Sexp)) {
    f(s);
    match s {
        Sexp::List(items) => items.iter().for_each(|i| walk(i, f)),
        Sexp::Quote(i) | Sexp::Quasiquote(i) | Sexp::Unquote(i) | Sexp::UnquoteSplice(i) => {
            walk(i, f)
        }
        _ => {}
    }
}

fn sym(s: &Sexp) -> Option<&str> {
    match s {
        Sexp::Atom(Atom::Symbol(n)) => Some(n),
        _ => None,
    }
}

fn tree(s: &Sexp, bump: &mut dyn FnMut(&str), tests: &mut HashMap<String, usize>) {
    let Sexp::List(items) = s else { return };
    let Some(head) = items.first().and_then(sym) else {
        return;
    };
    match head {
        "not" if items.len() == 2 => {
            if let Sexp::List(inner) = &items[1] {
                match inner.first().and_then(sym) {
                    Some("equal?") => bump("not (a == b)"),
                    Some("not=") => bump("not (a != b)"),
                    Some("<" | "<=" | ">" | ">=") => bump("not (a < b)"),
                    Some("not") => bump("not not x"),
                    _ => {}
                }
            }
        }
        "if" if items.len() == 4 => {
            if matches!(items[3], Sexp::Nil) {
                bump("if else nil");
            }
            if matches!(&items[1], Sexp::List(c) if c.first().and_then(sym) == Some("not")) {
                bump("if not c else");
            }
        }
        "equal?" | "not=" if items.len() == 3 => {
            let is = |x: &Sexp, n: &str| matches!(x, Sexp::List(c) if c.first().and_then(sym) == Some(n));
            for counter in ["count", "length", "size"] {
                if (is(&items[1], counter) && matches!(items[2], Sexp::Atom(Atom::Int(0))))
                    || (is(&items[2], counter) && matches!(items[1], Sexp::Atom(Atom::Int(0))))
                {
                    bump(&format!("{counter}(x) {head} 0"));
                }
            }
            if matches!(items[2], Sexp::Nil) || matches!(items[1], Sexp::Nil) {
                bump(&format!("x {head} nil"));
            }
            if matches!(items[2], Sexp::Atom(Atom::Bool(_))) {
                bump(&format!("x {head} bool literal"));
            }
        }
        ">" if items.len() == 3 => {
            if matches!(&items[1], Sexp::List(c) if matches!(c.first().and_then(sym), Some("count" | "length" | "size")))
                && matches!(items[2], Sexp::Atom(Atom::Int(0)))
            {
                bump("count(x) > 0");
            }
        }
        "deftest" if items.len() == 3 => {
            if let Sexp::Atom(Atom::Str(n)) = &items[1] {
                *tests.entry(n.to_string()).or_default() += 1;
            }
        }
        "define" | "define-typed" if items.len() >= 3 => {
            let names: Vec<&str> = match &items[1] {
                Sexp::List(sig) => sig
                    .iter()
                    .filter_map(|p| match p {
                        Sexp::List(pair) => pair.first().and_then(sym),
                        other => sym(other),
                    })
                    .collect(),
                other => sym(other).into_iter().collect(),
            };
            for n in names {
                if n.chars().any(|c| c.is_ascii_uppercase()) {
                    bump("name with uppercase");
                }
            }
        }
        "lambda" if items.len() == 3 => {
            if let Sexp::List(ps) = &items[1] {
                for p in ps {
                    if sym(p).is_some_and(|n| n.chars().any(|c| c.is_ascii_uppercase())) {
                        bump("name with uppercase");
                    }
                }
            }
        }
        _ => {}
    }
    for a in &items[1..] {
        if let Some(n) = sym(a) {
            if matches!(n, "and" | "or" | "not") {
                bump(&format!("{n} as value"));
            }
        }
    }
}
