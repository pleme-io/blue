use std::collections::BTreeMap;
use std::path::Path;

use blue_lang_syntax::{Atom, Sexp};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Gap {
    pub id: String,
    pub open: bool,
}

pub const LEDGER: &str = "spec/gaps/gaps.b";

pub fn load(path: &Path) -> (Vec<Gap>, Vec<String>) {
    match std::fs::read_to_string(path) {
        Ok(text) => parse(&text, &path.display().to_string()),
        Err(e) => (Vec::new(), vec![format!("{}: {e}", path.display())]),
    }
}

pub fn parse(text: &str, file: &str) -> (Vec<Gap>, Vec<String>) {
    let forms = match blue_lang_syntax::parse_program(text) {
        Ok(f) => f,
        Err(e) => return (Vec::new(), vec![format!("{file}: {e}")]),
    };
    let mut ledger: Vec<Gap> = Vec::new();
    let mut refused = Vec::new();
    for form in &forms {
        match gap_of(form) {
            Ok(g) if ledger.iter().any(|h| h.id == g.id) => refused.push(format!(
                "{file}: gap {} has two rows; one id names one gap",
                g.id
            )),
            Ok(g) => ledger.push(g),
            Err(why) => refused.push(format!("{file}: {why}")),
        }
    }
    (ledger, refused)
}

fn gap_id(id: &str) -> bool {
    id.strip_prefix('G')
        .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}

fn gap_of(form: &Sexp) -> Result<Gap, String> {
    let shape = "gap(ID, :open or :closed, WHAT IS MISSING, opened(DATE), OPTION...)";
    let Sexp::List(items) = form else {
        return Err(format!("the ledger holds only {shape} calls"));
    };
    let [head, id, state, what, options @ ..] = items.as_slice() else {
        return Err(format!("a gap row is {shape}"));
    };
    if head.as_symbol() != Some("gap") {
        return Err(format!("the ledger holds only {shape} calls"));
    }
    let id = blue_lang_syntax::constant_text(id).ok_or(format!("a gap row is {shape}"))?;
    if !gap_id(&id) {
        return Err(format!("`{id}` is not a gap id: G and a number"));
    }
    let open = match state {
        Sexp::Atom(Atom::Keyword(k)) if k == "open" => true,
        Sexp::Atom(Atom::Keyword(k)) if k == "closed" => false,
        _ => return Err(format!("gap {id}: its state is :open or :closed")),
    };
    if blue_lang_syntax::constant_text(what).is_none_or(|w| w.trim().is_empty()) {
        return Err(format!("gap {id}: it says what is missing, as a string"));
    }
    let mut said = BTreeMap::new();
    for option in options {
        let named = match option {
            Sexp::List(call) => match call.as_slice() {
                [name, arg] => name.as_symbol().zip(blue_lang_syntax::constant_text(arg)),
                _ => None,
            },
            _ => None,
        };
        match named {
            Some((name, arg)) if ["opened", "closed", "owner", "was"].contains(&name) => {
                if said.insert(name.to_owned(), arg).is_some() {
                    return Err(format!(
                        "gap {id}: {name}(…) is said twice; a row says each option once"
                    ));
                }
            }
            _ => {
                return Err(format!(
                    "gap {id}: an option is opened(DATE), closed(DATE), owner(DOC) or was(ID)"
                ));
            }
        }
    }
    if !said.contains_key("opened") {
        return Err(format!("gap {id}: opened(DATE) says when it was opened"));
    }
    if open == said.contains_key("closed") {
        return Err(format!(
            "gap {id}: a closed gap says closed(DATE), and an open one does not"
        ));
    }
    if said.get("was").is_some_and(|w| !gap_id(w)) {
        return Err(format!("gap {id}: was(ID) names a gap id"));
    }
    Ok(Gap { id, open })
}

pub fn gate(
    ledger: &[Gap],
    row_marks: &[(String, String)],
    written: Result<usize, String>,
    door_marks: &[(String, String)],
) -> Vec<String> {
    let mut found = Vec::new();
    match written {
        Ok(n) if n == row_marks.len() => {}
        Ok(n) => found.push(format!(
            "spec/rows/ writes {n} pending and flaky marks, and the loader read {}; a mark the loader does not read is held by no gate",
            row_marks.len()
        )),
        Err(why) => found.push(format!(
            "the text of spec/rows/ could not be read to count its marks: {why}"
        )),
    }
    let marks: Vec<(String, String)> = row_marks.iter().chain(door_marks).cloned().collect();
    found.extend(refusals(ledger, &marks));
    found
}

pub fn written_in(text: &str) -> usize {
    let mut count = 0;
    let mut before = None;
    let mut string = false;
    let mut escaped = false;
    let mut comment = false;
    for (at, c) in text.char_indices() {
        if comment {
            comment = c != '\n';
        } else if string {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                string = false;
                before = Some(c);
            }
        } else if c == '"' {
            string = true;
        } else if c == '#' {
            comment = true;
        } else if !c.is_whitespace() {
            if matches!(before, Some(',' | '('))
                && ["pending(", "flaky("]
                    .iter()
                    .any(|word| text[at..].starts_with(word))
            {
                count += 1;
            }
            before = Some(c);
        }
    }
    count
}

pub fn marks_written(dir: &Path) -> Result<usize, String> {
    let unread = |at: &Path, e: std::io::Error| format!("{}: {e}", at.display());
    let mut written = 0;
    for entry in std::fs::read_dir(dir).map_err(|e| unread(dir, e))? {
        let path = entry.map_err(|e| unread(dir, e))?.path();
        if path.extension().is_some_and(|e| e == "b") {
            let text = std::fs::read_to_string(&path).map_err(|e| unread(&path, e))?;
            written += written_in(&text);
        }
    }
    Ok(written)
}

pub fn refusals(ledger: &[Gap], marks: &[(String, String)]) -> Vec<String> {
    marks
        .iter()
        .filter_map(|(at, gap)| match ledger.iter().find(|g| &g.id == gap) {
            None => Some(format!(
                "{at} names gap {gap}, which {LEDGER} does not hold; add its row there"
            )),
            Some(g) if !g.open => Some(format!(
                "{at} names gap {gap}, which {LEDGER} has closed; remove the mark"
            )),
            Some(_) => None,
        })
        .collect()
}

pub fn row_marks(rows: &[crate::rows::Row]) -> Vec<(String, String)> {
    rows.iter()
        .flat_map(|r| {
            r.pending
                .iter()
                .map(move |p| (format!("row {}", r.id), p.gap.clone()))
        })
        .collect()
}

pub fn door_marks() -> Vec<(String, String)> {
    use blue_lang_runtime::door::{Reason, TABLE};
    TABLE
        .iter()
        .filter_map(|rule| match rule.reason {
            Reason::Disagrees { gap, row } => {
                Some((format!("door::TABLE's rule for {row}"), gap.to_owned()))
            }
            _ => None,
        })
        .collect()
}
