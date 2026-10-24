use std::collections::{BTreeMap, BTreeSet};

use tatara_lisp::{Span, Spanned, SpannedForm};

use crate::{Code, Diagnostic, Edit};

pub const CODES: &[Code] = &[
    Code::B0048,
    Code::B0049,
    Code::B0050,
    Code::B0051,
    Code::B0052,
];
pub const FRAGMENT_HEADS: &[&str] = &["fragment", "danpen/fragment"];
pub const LABELS_HEADS: &[&str] = &["labels", "gamen/labels"];
pub const OPERATION_WORDS: &[&str] = &["query", "mutation", "subscription"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Field {
    pub name: String,
    pub span: Span,
    pub sub: Option<Selection>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Selection {
    pub fragment: String,
    pub path: Vec<String>,
    pub fields: Vec<Field>,
    pub spreads: Vec<(String, Span)>,
    pub list: Span,
}

impl Selection {
    #[must_use]
    pub fn field(&self, name: &str) -> Option<&Field> {
        self.fields.iter().find(|f| f.name == name)
    }

    #[must_use]
    pub fn spreads(&self, fragment: &str) -> bool {
        self.spreads.iter().any(|(n, _)| n == fragment)
    }

    #[must_use]
    pub fn type_name(&self) -> String {
        let root = type_name(&self.fragment);
        if self.path.is_empty() {
            root
        } else {
            format!("{root}.{}", self.path.join("."))
        }
    }

    #[must_use]
    pub fn place(&self) -> String {
        if self.path.is_empty() {
            format!("fragment `{}`", self.fragment)
        } else {
            format!("`{}` in fragment `{}`", self.path.join("."), self.fragment)
        }
    }

    fn insertion(&self, text: &str) -> Option<Edit> {
        if self.list.start == usize::MAX || self.list.end <= self.list.start {
            return None;
        }
        let empty = self.fields.is_empty() && self.spreads.is_empty();
        let sep = if empty { "" } else { ", " };
        Some(Edit {
            span: Span::new(self.list.end - 1, self.list.end),
            original: "]".to_string(),
            replacement: format!("{sep}{text}]"),
        })
    }

    #[must_use]
    pub fn add_spread(&self, fragment: &str) -> Option<Edit> {
        self.insertion(&format!("\"...{fragment}\""))
    }

    #[must_use]
    pub fn add_field(&self, field: &str) -> Option<Edit> {
        self.insertion(&format!(":{field}"))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Fragment {
    pub name: String,
    pub on: String,
    pub on_span: Span,
    pub top_level: usize,
    pub selection: Selection,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Fragments(BTreeMap<String, Fragment>);

#[must_use]
pub fn type_name(fragment: &str) -> String {
    fragment
        .split('_')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let mut c = p.chars();
            c.next()
                .map(|h| h.to_uppercase().chain(c).collect::<String>())
                .unwrap_or_default()
        })
        .collect()
}

fn head(s: &Spanned) -> Option<&str> {
    s.as_list()?.first()?.as_symbol()
}

fn text_of(s: &Spanned) -> Option<&str> {
    s.as_keyword().or_else(|| s.as_string())
}

fn map_entries(s: &Spanned) -> Option<Vec<(&Spanned, &Spanned)>> {
    let items = s.as_list()?;
    if items.first()?.as_symbol()? != "hash-map" || items.len() % 2 == 0 {
        return None;
    }
    Some(items[1..].chunks(2).map(|kv| (&kv[0], &kv[1])).collect())
}

fn map_get<'a>(s: &'a Spanned, key: &str) -> Option<&'a Spanned> {
    map_entries(s)?
        .into_iter()
        .find(|(k, _)| text_of(k) == Some(key))
        .map(|(_, v)| v)
}

fn list_items(s: &Spanned) -> Option<&[Spanned]> {
    let items = s.as_list()?;
    (items.first()?.as_symbol()? == "list").then(|| &items[1..])
}

fn selection_of(list: &Spanned, fragment: &str, path: &[String]) -> Option<Selection> {
    let mut sel = Selection {
        fragment: fragment.to_string(),
        path: path.to_vec(),
        fields: Vec::new(),
        spreads: Vec::new(),
        list: list.span,
    };
    for item in list_items(list)? {
        if let Some(entries) = map_entries(item) {
            for (k, v) in entries {
                let name = text_of(k)?.to_string();
                let mut deeper = path.to_vec();
                deeper.push(name.clone());
                let sub = selection_of(v, fragment, &deeper)?;
                sel.fields.push(Field {
                    name,
                    span: k.span,
                    sub: Some(sub),
                });
            }
        } else {
            let text = text_of(item)?;
            if let Some(spread) = text.strip_prefix("...") {
                sel.spreads.push((spread.to_string(), item.span));
            } else {
                sel.fields.push(Field {
                    name: text.to_string(),
                    span: item.span,
                    sub: None,
                });
            }
        }
    }
    Some(sel)
}

fn fragment_call(s: &Spanned) -> Option<&Spanned> {
    let h = head(s)?;
    if FRAGMENT_HEADS.contains(&h) {
        return Some(s);
    }
    if h != "define" {
        return None;
    }
    let items = s.as_list()?;
    let value = items.get(2)?;
    let h = head(value)?;
    FRAGMENT_HEADS.contains(&h).then_some(value)
}

fn fragment_of(call: &Spanned, top_level: usize) -> Option<Fragment> {
    let items = call.as_list()?;
    if items.len() != 3 {
        return None;
    }
    let name = text_of(&items[1])?.to_string();
    let on = map_get(&items[2], "on")?;
    let fields = map_get(&items[2], "fields")?;
    Some(Fragment {
        on: on.as_string()?.to_string(),
        on_span: on.span,
        top_level,
        selection: selection_of(fields, &name, &[])?,
        name,
    })
}

impl Fragments {
    #[must_use]
    pub fn collect(forms: &[Spanned]) -> Self {
        let mut out = BTreeMap::new();
        for (i, form) in forms.iter().enumerate() {
            if let Some(f) = fragment_call(form).and_then(|c| fragment_of(c, i)) {
                out.entry(f.name.clone()).or_insert(f);
            }
        }
        Self(out)
    }

    #[must_use]
    pub fn get(&self, name: &str) -> Option<&Fragment> {
        self.0.get(name)
    }

    #[must_use]
    pub fn by_type(&self, ty: &str) -> Option<&Fragment> {
        self.0.values().find(|f| type_name(&f.name) == ty)
    }

    pub fn iter(&self) -> impl Iterator<Item = &Fragment> {
        self.0.values()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    #[must_use]
    pub fn declaring(&self, sel: &Selection, field: &str) -> Option<String> {
        let mut seen = BTreeSet::new();
        let mut todo: Vec<String> = sel.spreads.iter().map(|(n, _)| n.clone()).collect();
        while let Some(n) = todo.pop() {
            if !seen.insert(n.clone()) {
                continue;
            }
            let Some(f) = self.get(&n) else {
                continue;
            };
            if f.selection.field(field).is_some() {
                return Some(n);
            }
            todo.extend(f.selection.spreads.iter().map(|(m, _)| m.clone()));
        }
        None
    }

    #[must_use]
    pub fn table(&self) -> Vec<(String, String, Vec<String>, Vec<String>)> {
        self.0
            .values()
            .map(|f| {
                (
                    f.name.clone(),
                    f.on.clone(),
                    f.selection.fields.iter().map(|x| x.name.clone()).collect(),
                    f.selection.spreads.iter().map(|(n, _)| n.clone()).collect(),
                )
            })
            .collect()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Schema {
    pub types: BTreeMap<String, BTreeMap<String, String>>,
    pub enums: BTreeMap<String, Vec<String>>,
}

fn string_map(s: &Spanned) -> Result<Vec<(String, &Spanned)>, String> {
    map_entries(s)
        .ok_or("expected a map literal")?
        .into_iter()
        .map(|(k, v)| {
            text_of(k)
                .map(|k| (k.to_string(), v))
                .ok_or_else(|| "a key is not a name".to_string())
        })
        .collect()
}

impl Schema {
    pub fn read(text: &str) -> Result<Self, String> {
        let forms = blue_lang_syntax::parse_program_tree(text).map_err(|e| e.to_string())?;
        let [table] = forms.as_slice() else {
            return Err("the table is one map literal".to_string());
        };
        let mut out = Schema::default();
        for (key, value) in string_map(table)? {
            match key.as_str() {
                "types" => {
                    for (ty, fields) in string_map(value)? {
                        let mut row = BTreeMap::new();
                        for (field, base) in string_map(fields)? {
                            let base = base
                                .as_string()
                                .ok_or_else(|| format!("{ty}.{field} names no type"))?;
                            row.insert(field, base.to_string());
                        }
                        out.types.insert(ty, row);
                    }
                }
                "enums" => {
                    for (name, values) in string_map(value)? {
                        let values = list_items(values)
                            .ok_or_else(|| format!("enum {name} is not a list"))?
                            .iter()
                            .map(|v| text_of(v).map(str::to_string))
                            .collect::<Option<Vec<_>>>()
                            .ok_or_else(|| {
                                format!("enum {name} holds a value that is not a name")
                            })?;
                        out.enums.insert(name, values);
                    }
                }
                other => return Err(format!("the table has no key `{other}`")),
            }
        }
        Ok(out)
    }
}

pub struct Context<'a> {
    pub fragments: &'a Fragments,
    pub schema: Option<&'a Schema>,
    pub is_entry: &'a dyn Fn(usize) -> bool,
    pub view: bool,
}

#[must_use]
pub fn check(forms: &[Spanned], cx: &Context<'_>) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    for f in cx.fragments.iter() {
        spreads(&f.selection, cx.fragments, f.top_level, &mut out);
        if let Some(schema) = cx.schema {
            if schema.types.contains_key(&f.on) {
                in_schema(&f.selection, &f.on, schema, f.top_level, &mut out);
            } else {
                out.push(
                    Diagnostic::new(
                        Code::B0050,
                        format!(
                            "fragment `{}` is on `{}`, which the schema does not define",
                            f.name, f.on
                        ),
                        f.on_span,
                    )
                    .at_top_level(f.top_level)
                    .with_help("name a type of the SDL; the generated table lists them"),
                );
            }
        }
    }
    for (i, form) in forms.iter().enumerate() {
        if let Some(schema) = cx.schema {
            walk(form, &mut |s| labels(s, schema, i, &mut out));
            if (cx.is_entry)(i) {
                walk_outside_fragments(form, &mut |s| mirror(s, schema, i, &mut out));
            }
        }
        if cx.view && (cx.is_entry)(i) && head(form) != Some("deftest") {
            walk(form, &mut |s| query_text(s, i, &mut out));
        }
    }
    let mut seen = BTreeSet::new();
    out.retain(|d| seen.insert((d.code, d.span.start, d.span.end)));
    out
}

fn spreads(sel: &Selection, frags: &Fragments, top: usize, out: &mut Vec<Diagnostic>) {
    for (name, span) in &sel.spreads {
        if frags.get(name).is_none() {
            out.push(
                Diagnostic::new(
                    Code::B0049,
                    format!(
                        "{} spreads `...{name}`, and no fragment `{name}` is declared",
                        sel.place()
                    ),
                    *span,
                )
                .at_top_level(top)
                .with_help("declare the fragment, or remove the spread"),
            );
        }
    }
    for f in &sel.fields {
        if let Some(sub) = &f.sub {
            spreads(sub, frags, top, out);
        }
    }
}

fn in_schema(sel: &Selection, on: &str, schema: &Schema, top: usize, out: &mut Vec<Diagnostic>) {
    let Some(fields) = schema.types.get(on) else {
        return;
    };
    for f in &sel.fields {
        if f.name == "__typename" {
            continue;
        }
        match fields.get(&f.name) {
            Some(base) => {
                if let Some(sub) = &f.sub {
                    in_schema(sub, base, schema, top, out);
                }
            }
            None => {
                let nearest = fields
                    .keys()
                    .filter_map(|k| crate::suggest::closeness(&f.name, k).map(|d| (d, k)))
                    .min();
                let help = match nearest {
                    Some((_, k)) => format!(
                        "did you mean `{k}`? select a field `{on}` defines, or add it to the SDL"
                    ),
                    None => format!("select a field `{on}` defines, or add it to the SDL"),
                };
                let d = Diagnostic::new(
                    Code::B0050,
                    format!(
                        "`{}` is not a field of `{on}` in the schema ({})",
                        f.name,
                        sel.place()
                    ),
                    f.span,
                )
                .at_top_level(top)
                .with_help(help);
                out.push(d);
            }
        }
    }
}

fn walk(s: &Spanned, f: &mut dyn FnMut(&Spanned)) {
    f(s);
    match &s.form {
        SpannedForm::List(items) => items.iter().for_each(|i| walk(i, f)),
        SpannedForm::Quote(x)
        | SpannedForm::Quasiquote(x)
        | SpannedForm::Unquote(x)
        | SpannedForm::UnquoteSplice(x) => walk(x, f),
        _ => {}
    }
}

fn walk_outside_fragments(s: &Spanned, f: &mut dyn FnMut(&Spanned)) {
    if head(s).is_some_and(|h| FRAGMENT_HEADS.contains(&h) || LABELS_HEADS.contains(&h)) {
        return;
    }
    f(s);
    if let SpannedForm::List(items) = &s.form {
        items.iter().for_each(|i| walk_outside_fragments(i, f));
    }
}

fn labels(s: &Spanned, schema: &Schema, top: usize, out: &mut Vec<Diagnostic>) {
    if !head(s).is_some_and(|h| LABELS_HEADS.contains(&h)) {
        return;
    }
    let Some(items) = s.as_list() else {
        return;
    };
    let Some(set) = items.get(1).and_then(Spanned::as_keyword) else {
        return;
    };
    let Some(values) = schema.enums.get(set) else {
        out.push(
            Diagnostic::new(
                Code::B0050,
                format!("labels names `{set}`, which is not an enum of the schema"),
                items[1].span,
            )
            .at_top_level(top)
            .with_help("name an enum the SDL defines; labels are keyed by its values"),
        );
        return;
    };
    let Some(entries) = items.get(2).and_then(map_entries) else {
        return;
    };
    for (k, _) in entries {
        if let Some(key) = text_of(k) {
            if !values.iter().any(|v| v == key) {
                out.push(
                    Diagnostic::new(
                        Code::B0050,
                        format!("`{key}` is not a value of enum `{set}` in the schema"),
                        k.span,
                    )
                    .at_top_level(top)
                    .with_help(format!(
                        "label the values `{set}` has: {}",
                        values.join(", ")
                    )),
                );
            }
        }
    }
}

fn mirror(s: &Spanned, schema: &Schema, top: usize, out: &mut Vec<Diagnostic>) {
    let Some(items) = list_items(s) else {
        return;
    };
    if items.len() < 2 {
        return;
    }
    let Some(texts) = items.iter().map(text_of).collect::<Option<BTreeSet<_>>>() else {
        return;
    };
    if texts.len() != items.len() {
        return;
    }
    for (name, values) in &schema.enums {
        let set: BTreeSet<&str> = values.iter().map(String::as_str).collect();
        if set == texts {
            out.push(
                Diagnostic::new(
                    Code::B0051,
                    format!("this list mirrors enum `{name}` of the schema"),
                    s.span,
                )
                .at_top_level(top)
                .with_help(format!(
                    "the values belong to the backend; key display text by them with `labels(:{name}, {{…}})`"
                )),
            );
            return;
        }
    }
}

fn query_text(s: &Spanned, top: usize, out: &mut Vec<Diagnostic>) {
    let Some(text) = s.as_string() else {
        return;
    };
    let t = text.trim_start();
    let word = t
        .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
        .next()
        .unwrap_or("");
    let operation = OPERATION_WORDS.contains(&word)
        && t[word.len()..]
            .chars()
            .next()
            .is_some_and(|c| c.is_whitespace() || c == '{' || c == '(');
    if operation && t.contains('{') {
        out.push(
            Diagnostic::new(
                Code::B0052,
                format!("a view writes GraphQL `{word}` text; its operation is composed from fragments"),
                s.span,
            )
            .at_top_level(top)
            .with_help("declare a fragment on the root type and let danpen::compose write the operation; hanabi receives its hash"),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn forms(src: &str) -> Vec<Spanned> {
        blue_lang_syntax::parse_program_tree(src).unwrap()
    }

    #[test]
    fn a_fragment_is_read_from_its_declaration() {
        let f = Fragments::collect(&forms(
            "card = danpen::fragment(:user_card, {on: \"User\", fields: [:id, \"...face\", {avatar: [:url]}]})\n",
        ));
        let card = f.get("user_card").unwrap();
        assert_eq!(card.on, "User");
        assert_eq!(card.selection.fields.len(), 2);
        assert!(card.selection.spreads("face"));
        let avatar = card
            .selection
            .field("avatar")
            .unwrap()
            .sub
            .as_ref()
            .unwrap();
        assert_eq!(avatar.type_name(), "UserCard.avatar");
        assert_eq!(f.by_type("UserCard").unwrap().name, "user_card");
    }

    #[test]
    fn the_type_name_is_the_pascal_spelling() {
        assert_eq!(type_name("user_card"), "UserCard");
        assert_eq!(type_name("Profile"), "Profile");
    }

    #[test]
    fn a_table_reads_types_and_enums() {
        let s = Schema::read(
            "{types: {\"User\" => {\"id\" => \"ID\"}}, enums: {\"Tone\" => [\"A\", \"B\"]}}\n",
        )
        .unwrap();
        assert_eq!(s.types["User"]["id"], "ID");
        assert_eq!(s.enums["Tone"], vec!["A", "B"]);
        assert!(Schema::read("{other: {}}\n").is_err());
    }

    #[test]
    fn the_spread_edit_closes_the_list() {
        let src = "x = fragment(:p, {on: \"Query\", fields: [{user: [:id]}]})\n";
        let f = Fragments::collect(&forms(src));
        let user = f
            .get("p")
            .unwrap()
            .selection
            .field("user")
            .unwrap()
            .sub
            .clone()
            .unwrap();
        let e = user.add_spread("card").unwrap();
        let mut out = src.to_string();
        assert_eq!(&out[e.span.start..e.span.end], "]");
        out.replace_range(e.span.start..e.span.end, &e.replacement);
        assert!(out.contains("[:id, \"...card\"]"), "{out}");
    }
}
