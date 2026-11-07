use tatara_lisp::{Spanned, SpannedForm};

use crate::parse::{list_at, sym_at};
use crate::record::{record_parts, Record};

pub const UNION_WORD: &str = "union";

pub const LOWERED_UNION: &str = "blue-union";

pub const ARM_SEPARATOR: &str = "|";

#[derive(Clone, Debug)]
pub struct Union<'a> {
    pub name: &'a Spanned,
    pub predicate: &'a Spanned,
    pub arms: Vec<Record<'a>>,
}

#[derive(Clone, Debug)]
pub struct Declared<'a> {
    pub name: &'a Spanned,
    pub predicate: &'a Spanned,
    pub arms: &'a [Spanned],
}

fn headed<'a>(form: &'a Spanned, head: &str) -> Option<&'a [Spanned]> {
    let items = form.as_list()?;
    (items.first()?.as_symbol()? == head).then_some(items)
}

#[must_use]
pub fn union_parts(form: &Spanned) -> Option<Union<'_>> {
    let items = headed(form, LOWERED_UNION)?;
    let (name, predicate) = (items.get(1)?, items.get(2)?);
    name.as_symbol()?;
    predicate.as_symbol()?;
    let arms = items[3..]
        .iter()
        .map(record_parts)
        .collect::<Option<Vec<_>>>()?;
    (!arms.is_empty()).then_some(Union {
        name,
        predicate,
        arms,
    })
}

#[must_use]
pub fn declared(form: &Spanned) -> Option<Declared<'_>> {
    let items = headed(form, LOWERED_UNION)?;
    let (name, predicate) = (items.get(1)?, items.get(2)?);
    name.as_symbol()?;
    predicate.as_symbol()?;
    let arms = &items[3..];
    (!arms.is_empty() && arms.iter().all(|a| a.as_symbol().is_some())).then_some(Declared {
        name,
        predicate,
        arms,
    })
}

#[must_use]
pub fn lower(forms: Vec<Spanned>) -> Vec<Spanned> {
    if !forms.iter().any(|f| union_parts(f).is_some()) {
        return forms;
    }
    let mut out = Vec::with_capacity(forms.len());
    for form in forms {
        let Some(u) = union_parts(&form) else {
            out.push(form);
            continue;
        };
        let mut marker = vec![
            sym_at(
                form.as_list().map_or(form.span, |i| i[0].span),
                LOWERED_UNION,
            ),
            u.name.clone(),
            u.predicate.clone(),
        ];
        for arm in &u.arms {
            marker.push(arm.predicate.clone());
        }
        let arms: Vec<Spanned> = form.as_list().map(|i| i[3..].to_vec()).unwrap_or_default();
        out.extend(arms);
        out.push(list_at(form.span, marker));
    }
    out
}

#[must_use]
pub fn raise(forms: Vec<Spanned>) -> Vec<Spanned> {
    if !forms.iter().any(|f| declared(f).is_some()) {
        return forms;
    }
    let mut out: Vec<Spanned> = Vec::with_capacity(forms.len());
    for form in forms {
        let Some(d) = declared(&form) else {
            out.push(form);
            continue;
        };
        let n = d.arms.len();
        let matches = out.len() >= n
            && out[out.len() - n..].iter().zip(d.arms).all(|(f, arm)| {
                record_parts(f).is_some_and(|r| r.predicate.as_symbol() == arm.as_symbol())
            });
        if !matches {
            out.push(form);
            continue;
        }
        let arms = out.split_off(out.len() - n);
        let SpannedForm::List(items) = &form.form else {
            out.push(form);
            continue;
        };
        let mut nested = items[..3].to_vec();
        nested.extend(arms);
        out.push(list_at(form.span, nested));
    }
    out
}
