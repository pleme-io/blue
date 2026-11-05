use tatara_lisp::{Atom, Spanned, SpannedForm};

pub const LOWERED_RECORD: &str = "blue-record";

pub const RECORD_TAG: &str = "$record";

pub const RECORD_ALIASES: &[&str] = &["struct", "class", "defstruct", "defrecord"];

pub const VALUE_TYPES: &[&str] = &["Int", "Float", "Str", "Bool", "Sym", "Nil", "Map"];

pub const LIST_TYPE: &str = "List";

#[derive(Clone, Copy, Debug)]
pub struct Field<'a> {
    pub node: &'a Spanned,
    pub name: &'a str,
    pub ty: Option<&'a Spanned>,
}

#[derive(Clone, Debug)]
pub struct Record<'a> {
    pub name: &'a Spanned,
    pub predicate: &'a Spanned,
    pub fields: Vec<Field<'a>>,
}

impl Record<'_> {
    #[must_use]
    pub fn field_names(&self) -> Vec<&str> {
        self.fields.iter().map(|f| f.name).collect()
    }
}

fn keyword(node: &Spanned) -> Option<&str> {
    match &node.form {
        SpannedForm::Atom(Atom::Keyword(k)) => Some(k),
        _ => None,
    }
}

#[must_use]
pub fn record_parts(form: &Spanned) -> Option<Record<'_>> {
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != LOWERED_RECORD {
        return None;
    }
    let (name, predicate) = (items.get(1)?, items.get(2)?);
    name.as_symbol()?;
    predicate.as_symbol()?;
    let fields = items[3..]
        .iter()
        .map(|f| match f.as_list() {
            Some([n, ty]) => Some(Field {
                node: f,
                name: keyword(n)?,
                ty: Some(ty),
            }),
            _ => Some(Field {
                node: f,
                name: keyword(f)?,
                ty: None,
            }),
        })
        .collect::<Option<Vec<_>>>()?;
    Some(Record {
        name,
        predicate,
        fields,
    })
}

pub fn type_references<'a>(ty: &'a Spanned, out: &mut dyn FnMut(&'a Spanned)) {
    if let Some(name) = ty.as_symbol() {
        if !VALUE_TYPES.contains(&name) {
            out(ty);
        }
    } else if let Some([head, rest @ ..]) = ty.as_list() {
        if head.as_symbol() == Some(LIST_TYPE) {
            for t in rest {
                type_references(t, out);
            }
        }
    }
}
