//! Signature help: which call the cursor is inside, and which argument.
//!
//! Read off the token stream, not the tree, because the buffer is mid-call
//! (`add(1, `) and does not parse; the callee is then resolved against the
//! newest analysis that did.

use blue_lang_syntax::TokenKind;

use crate::{Engine, Symbol};

/// The call at the cursor.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Signature {
    /// `def add(a, b)`, or a builtin's calling form.
    pub label: String,
    pub parameters: Vec<String>,
    /// Which parameter the cursor is on.
    pub active: usize,
    pub doc: Option<String>,
}

impl Engine {
    /// The signature of the call around byte `offset` of document `id`.
    #[must_use]
    pub fn signature_at(&self, id: &str, offset: usize) -> Option<Signature> {
        let text = self.document_text(id)?;
        let (callee, _, active) = open_call(&text, offset)?;
        let a = self.last_good(id)?;
        let symbol = a.resolve_name(&callee)?;
        let (label, doc) = match symbol {
            Symbol::Def(ns, name) => {
                let l = a.definition_of(self, &ns, &name)?;
                let item = self.item_at(&a, &l)?;
                (item.signature, item.doc)
            }
            Symbol::Builtin(name) => {
                let d = blue_lang_runtime::docs::doc_of(&name)?;
                (d.signature.to_string(), Some(d.doc.to_string()))
            }
            Symbol::Local(_) | Symbol::Package(_) => return None,
        };
        let parameters = parameters_of(&label);
        Some(Signature {
            active: active.min(parameters.len().saturating_sub(1)),
            label,
            parameters,
            doc,
        })
    }
}

/// The callee of the innermost unclosed `name(` before `offset`, where its
/// name is, and how many commas at its depth precede the cursor.
fn open_call(text: &str, offset: usize) -> Option<(String, usize, usize)> {
    let before = text.get(..offset)?;
    let tokens = lex_prefix(before);
    let mut depth = 0usize;
    let mut commas = 0usize;
    for i in (0..tokens.len()).rev() {
        match &tokens[i].0 {
            TokenKind::RParen | TokenKind::RBracket | TokenKind::RBrace => depth += 1,
            TokenKind::LBracket | TokenKind::LBrace if depth > 0 => depth -= 1,
            TokenKind::LBracket | TokenKind::LBrace => return None,
            TokenKind::LParen if depth > 0 => depth -= 1,
            TokenKind::LParen => {
                let (TokenKind::Ident(name), at) = tokens.get(i.checked_sub(1)?)? else {
                    return None;
                };
                let mut name = name.clone();
                let mut at = *at;
                if i >= 3 {
                    if let (TokenKind::PathSep, TokenKind::Ident(pkg)) =
                        (&tokens[i - 2].0, &tokens[i - 3].0)
                    {
                        name = blue_lang_syntax::qualify(pkg, &name);
                        at = tokens[i - 3].1;
                    }
                }
                return Some((name, at, commas));
            }
            TokenKind::Comma if depth == 0 => commas += 1,
            _ => {}
        }
    }
    None
}

/// The tokens of a prefix that may end mid-token: lexed whole, or, when the
/// tail does not lex (an open string), up to the last line that does.
fn lex_prefix(src: &str) -> Vec<(TokenKind, usize)> {
    let mut end = src.len();
    loop {
        if let Ok(toks) = blue_lang_syntax::lex(&src[..end]) {
            return toks.into_iter().map(|t| (t.kind, t.span.start)).collect();
        }
        match src[..end].rfind('\n') {
            Some(n) if n > 0 => end = n,
            _ => return Vec::new(),
        }
    }
}

/// `def add(a: Int, b) -> Int` → `["a: Int", "b"]`.
fn parameters_of(signature: &str) -> Vec<String> {
    let Some(open) = signature.find('(') else {
        return Vec::new();
    };
    let mut depth = 0usize;
    let mut out = Vec::new();
    let mut current = String::new();
    for c in signature[open + 1..].chars() {
        match c {
            '(' | '[' | '{' => {
                depth += 1;
                current.push(c);
            }
            ')' if depth == 0 => {
                if !current.trim().is_empty() {
                    out.push(current.trim().to_string());
                }
                return out;
            }
            ')' | ']' | '}' => {
                depth = depth.saturating_sub(1);
                current.push(c);
            }
            ',' if depth == 0 => {
                out.push(current.trim().to_string());
                current.clear();
            }
            _ => current.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_open_call_and_the_argument_index_are_read_off_the_tokens() {
        let text = "x = add(1, f(2, 3), ";
        let (name, at, active) = open_call(text, text.len()).expect("a call");
        assert_eq!((name.as_str(), at, active), ("add", 4, 2));
        let text = "kueri::join(a, ";
        let (name, at, active) = open_call(text, text.len()).expect("a call");
        assert_eq!((name.as_str(), at, active), ("kueri/join", 0, 1));
        assert!(open_call("add(1)", 6).is_none());
    }

    #[test]
    fn parameters_split_at_the_top_level_only() {
        assert_eq!(
            parameters_of("def f(a: List[Int], b, c) -> Int"),
            vec!["a: List[Int]", "b", "c"]
        );
        assert_eq!(parameters_of("first(xs)"), vec!["xs"]);
        assert!(parameters_of("def f()").is_empty());
    }
}
