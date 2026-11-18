use tatara_lisp::{Atom, Spanned, SpannedForm};

pub const LOWERED_RECORD: &str = "blue-record";

pub const RECORD_TAG: &str = "$record";

pub const RECORD_ALIASES: &[&str] = &["struct", "class", "defstruct", "defrecord"];

pub const VALUE_TYPES: &[&str] = &[
    "Int", "Float", "Str", "Bool", "Sym", "Nil", "Map", "u8", "u16", "u32", "u64", "i8", "i16",
    "i32", "i64",
];

pub const WIDTH_TYPES: &[(&str, bool, u32)] = &[
    ("u8", false, 8),
    ("u16", false, 16),
    ("u32", false, 32),
    ("u64", false, 64),
    ("i8", true, 8),
    ("i16", true, 16),
    ("i32", true, 32),
    ("i64", true, 64),
];

#[must_use]
pub fn width_of(name: &str) -> Option<(bool, u32)> {
    WIDTH_TYPES
        .iter()
        .find(|(n, _, _)| *n == name)
        .map(|(_, signed, bits)| (*signed, *bits))
}

#[must_use]
pub fn width_bounds(signed: bool, bits: u32) -> (i128, i128) {
    if signed {
        (-(1i128 << (bits - 1)), (1i128 << (bits - 1)) - 1)
    } else if bits >= 64 {
        (0, i128::from(i64::MAX))
    } else {
        (0, (1i128 << bits) - 1)
    }
}

#[cfg(test)]
mod widths {
    use super::*;

    #[test]
    fn every_width_is_a_value_type_with_its_bounds() {
        for (n, signed, bits) in WIDTH_TYPES {
            assert!(VALUE_TYPES.contains(n), "{n}");
            assert_eq!(width_of(n), Some((*signed, *bits)));
        }
        assert_eq!(width_bounds(false, 8), (0, 255));
        assert_eq!(width_bounds(true, 8), (-128, 127));
        assert_eq!(
            width_bounds(true, 64),
            (i128::from(i64::MIN), i128::from(i64::MAX))
        );
        assert_eq!(width_of("Int"), None);
    }
}

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
