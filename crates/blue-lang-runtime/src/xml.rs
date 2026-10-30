use std::sync::Arc;

use quick_xml::escape::resolve_predefined_entity;
use quick_xml::events::{BytesStart, Event};
use quick_xml::Reader;
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

use crate::errors::raise_kind;

pub const MALFORMED: &str = "xml_malformed";
pub const REFUSED: &str = "xml_refused";
pub const MAX_DEPTH: usize = 1024;

pub fn install_xml_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "xml_parse",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| match &args[0] {
            Value::Str(s) => parse(s).map_err(|f| f.raise(span)),
            other => Err(EvalError::native_fn(
                "xml_parse",
                format!("expected a string of XML text, got {}", other.type_name()),
                span,
            )),
        },
    );
    interp.register_fn(
        "xml_render",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            render(&args[0])
                .map(|s| Value::Str(Arc::from(s)))
                .map_err(|f| f.raise(span))
        },
    );
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Fault {
    Malformed(String),
    Refused(String),
}

impl Fault {
    fn raise(self, span: tatara_lisp::Span) -> EvalError {
        match self {
            Fault::Malformed(m) => raise_kind(MALFORMED, m, span),
            Fault::Refused(m) => raise_kind(REFUSED, m, span),
        }
    }
}

struct Open {
    name: String,
    attributes: Vec<(String, String)>,
    children: Vec<Value>,
    texts: Vec<String>,
}

impl Open {
    fn close(self) -> Value {
        let text = if self.children.is_empty() {
            self.texts.concat()
        } else {
            self.texts
                .into_iter()
                .filter(|t| !t.chars().all(char::is_whitespace))
                .collect::<String>()
        };
        element(self.name, self.attributes, self.children, text)
    }
}

fn key(name: &str) -> MapKey {
    MapKey::Keyword(Arc::from(name))
}

fn element(
    name: String,
    attributes: Vec<(String, String)>,
    children: Vec<Value>,
    text: String,
) -> Value {
    Value::map([
        (key("name"), Value::Str(Arc::from(name))),
        (
            key("attributes"),
            Value::map(
                attributes
                    .into_iter()
                    .map(|(k, v)| (MapKey::Str(Arc::from(k)), Value::Str(Arc::from(v)))),
            ),
        ),
        (key("children"), Value::list(children)),
        (key("text"), Value::Str(Arc::from(text))),
    ])
}

fn position(src: &str, byte: u64) -> String {
    let end = usize::try_from(byte).unwrap_or(src.len()).min(src.len());
    let before = src.get(..end).unwrap_or(src);
    let line = before.matches('\n').count() + 1;
    let col = before.rsplit('\n').next().map_or(0, |l| l.chars().count()) + 1;
    format!("line {line}, column {col}")
}

fn entity_refused(name: &str) -> Fault {
    Fault::Refused(format!(
        "entity &{name}; is not expanded: blue reads only the five predefined entities and character references, never a DTD entity"
    ))
}

fn resolve_ref(name: &str) -> Result<String, Fault> {
    if let Some(num) = name.strip_prefix('#') {
        let code = match num.strip_prefix('x') {
            Some(hex) => u32::from_str_radix(hex, 16).ok(),
            None => num.parse::<u32>().ok(),
        };
        return code
            .and_then(char::from_u32)
            .filter(|c| legal_char(*c))
            .map(String::from)
            .ok_or_else(|| {
                Fault::Malformed(format!("&{name}; is not a legal character reference"))
            });
    }
    resolve_predefined_entity(name)
        .map(str::to_owned)
        .ok_or_else(|| entity_refused(name))
}

fn legal_char(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\r') || (c >= ' ' && c != '\u{FFFE}' && c != '\u{FFFF}')
}

fn open(start: &BytesStart<'_>, src: &str, at: u64) -> Result<Open, Fault> {
    let name = std::str::from_utf8(start.name().as_ref())
        .map_err(|e| Fault::Malformed(e.to_string()))?
        .to_owned();
    let mut attributes: Vec<(String, String)> = Vec::new();
    for attr in start.attributes() {
        let attr = attr.map_err(|e| Fault::Malformed(format!("{e} at {}", position(src, at))))?;
        let k = std::str::from_utf8(attr.key.as_ref())
            .map_err(|e| Fault::Malformed(e.to_string()))?
            .to_owned();
        let mut unknown: Option<String> = None;
        let v = attr
            .unescape_value_with(|ent| {
                let hit = resolve_predefined_entity(ent);
                if hit.is_none() {
                    unknown = Some(ent.to_owned());
                }
                hit
            })
            .map_err(|e| match unknown.take() {
                Some(ent) => entity_refused(&ent),
                None => Fault::Malformed(format!("{e} at {}", position(src, at))),
            })?
            .into_owned();
        attributes.push((k, v));
    }
    Ok(Open {
        name,
        attributes,
        children: Vec::new(),
        texts: Vec::new(),
    })
}

fn doctype_declares_entity(body: &str) -> bool {
    body.contains("<!ENTITY")
}

pub fn parse(src: &str) -> Result<Value, Fault> {
    let mut reader = Reader::from_str(src);
    reader.config_mut().check_end_names = true;
    reader.config_mut().expand_empty_elements = false;
    reader.config_mut().check_comments = true;
    let mut stack: Vec<Open> = Vec::new();
    let mut root: Option<Value> = None;
    loop {
        let at = reader.buffer_position();
        let event = reader.read_event().map_err(|e| {
            Fault::Malformed(format!("{e} at {}", position(src, reader.error_position())))
        })?;
        match event {
            Event::Start(start) => {
                if root.is_some() && stack.is_empty() {
                    return Err(Fault::Malformed(format!(
                        "a second root element at {}",
                        position(src, at)
                    )));
                }
                if stack.len() >= MAX_DEPTH {
                    return Err(Fault::Refused(format!(
                        "elements nest deeper than {MAX_DEPTH} at {}",
                        position(src, at)
                    )));
                }
                stack.push(open(&start, src, at)?);
            }
            Event::Empty(start) => {
                if root.is_some() && stack.is_empty() {
                    return Err(Fault::Malformed(format!(
                        "a second root element at {}",
                        position(src, at)
                    )));
                }
                let done = open(&start, src, at)?.close();
                match stack.last_mut() {
                    Some(parent) => parent.children.push(done),
                    None => root = Some(done),
                }
            }
            Event::End(_) => {
                let done = stack
                    .pop()
                    .ok_or_else(|| {
                        Fault::Malformed(format!(
                            "an end tag with no start at {}",
                            position(src, at)
                        ))
                    })?
                    .close();
                match stack.last_mut() {
                    Some(parent) => parent.children.push(done),
                    None => root = Some(done),
                }
            }
            Event::Text(t) => {
                let text = t
                    .decode()
                    .map_err(|e| Fault::Malformed(e.to_string()))?
                    .into_owned();
                match stack.last_mut() {
                    Some(el) => el.texts.push(text),
                    None if text.chars().all(char::is_whitespace) => {}
                    None => {
                        return Err(Fault::Malformed(format!(
                            "text outside the root element at {}",
                            position(src, at)
                        )))
                    }
                }
            }
            Event::CData(c) => {
                let text = c
                    .decode()
                    .map_err(|e| Fault::Malformed(e.to_string()))?
                    .into_owned();
                match stack.last_mut() {
                    Some(el) => el.texts.push(text),
                    None => {
                        return Err(Fault::Malformed(format!(
                            "CDATA outside the root element at {}",
                            position(src, at)
                        )))
                    }
                }
            }
            Event::GeneralRef(r) => {
                let name = r.decode().map_err(|e| Fault::Malformed(e.to_string()))?;
                let text = resolve_ref(&name)?;
                match stack.last_mut() {
                    Some(el) => el.texts.push(text),
                    None => {
                        return Err(Fault::Malformed(format!(
                            "a reference outside the root element at {}",
                            position(src, at)
                        )))
                    }
                }
            }
            Event::DocType(d) => {
                let body = d.decode().map_err(|e| Fault::Malformed(e.to_string()))?;
                if root.is_some() || !stack.is_empty() {
                    return Err(Fault::Malformed(format!(
                        "a DOCTYPE after the root element began at {}",
                        position(src, at)
                    )));
                }
                if doctype_declares_entity(&body) {
                    return Err(Fault::Refused(
                        "the DOCTYPE declares an entity: blue never expands or fetches DTD entities"
                            .to_owned(),
                    ));
                }
            }
            Event::Comment(_) | Event::Decl(_) | Event::PI(_) => {}
            Event::Eof => break,
        }
    }
    if let Some(unclosed) = stack.last() {
        return Err(Fault::Malformed(format!(
            "<{}> is never closed",
            unclosed.name
        )));
    }
    root.ok_or_else(|| Fault::Malformed("the document has no root element".to_owned()))
}

fn field<'a>(el: &'a Value, name: &str) -> Option<&'a Value> {
    match el {
        Value::Map(m) => m
            .iter()
            .find(|(k, _)| matches!(k, MapKey::Keyword(s) | MapKey::Str(s) if &**s == name))
            .map(|(_, v)| v),
        _ => None,
    }
}

fn scalar(v: &Value) -> Option<String> {
    match v {
        Value::Str(s) | Value::Symbol(s) | Value::Keyword(s) => Some(s.to_string()),
        Value::Int(n) => Some(n.to_string()),
        Value::Float(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}

fn map_key_text(k: &MapKey) -> Option<String> {
    match k {
        MapKey::Str(s) | MapKey::Symbol(s) | MapKey::Keyword(s) => Some(s.to_string()),
        _ => None,
    }
}

fn name_char(c: char, first: bool) -> bool {
    c == '_'
        || c == ':'
        || c.is_alphabetic()
        || (!first && (c == '-' || c == '.' || c.is_numeric()))
        || (!c.is_ascii() && !c.is_whitespace() && !c.is_control())
}

fn checked_name(name: &str, what: &str) -> Result<(), Fault> {
    let mut chars = name.chars();
    let ok = chars.next().is_some_and(|c| name_char(c, true)) && chars.all(|c| name_char(c, false));
    if ok {
        Ok(())
    } else {
        Err(Fault::Refused(format!(
            "{what} {name:?} is not an XML name"
        )))
    }
}

fn escape_into(out: &mut String, text: &str, in_attribute: bool) -> Result<(), Fault> {
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' if in_attribute => out.push_str("&quot;"),
            '\t' if in_attribute => out.push_str("&#9;"),
            '\n' if in_attribute => out.push_str("&#10;"),
            '\r' => out.push_str("&#13;"),
            c if legal_char(c) => out.push(c),
            c => {
                return Err(Fault::Refused(format!(
                    "U+{:04X} cannot appear in an XML 1.0 document",
                    u32::from(c)
                )))
            }
        }
    }
    Ok(())
}

fn render_into(out: &mut String, el: &Value, depth: usize) -> Result<(), Fault> {
    if depth >= MAX_DEPTH {
        return Err(Fault::Refused(format!(
            "elements nest deeper than {MAX_DEPTH}"
        )));
    }
    let name = field(el, "name").and_then(scalar).ok_or_else(|| {
        Fault::Refused(format!(
            "an element is a map with a name; got {}",
            el.type_name()
        ))
    })?;
    checked_name(&name, "element name")?;
    out.push('<');
    out.push_str(&name);
    match field(el, "attributes") {
        None | Some(Value::Nil) => {}
        Some(Value::Map(attrs)) => {
            let mut pairs: Vec<(String, &Value)> = Vec::new();
            for (k, v) in attrs.iter() {
                let k = map_key_text(k)
                    .ok_or_else(|| Fault::Refused("an attribute name is text".to_owned()))?;
                pairs.push((k, v));
            }
            pairs.sort_by(|a, b| a.0.cmp(&b.0));
            for (k, v) in pairs {
                checked_name(&k, "attribute name")?;
                let v = scalar(v).ok_or_else(|| {
                    Fault::Refused(format!("attribute {k} is not text: {}", v.type_name()))
                })?;
                out.push(' ');
                out.push_str(&k);
                out.push_str("=\"");
                escape_into(out, &v, true)?;
                out.push('"');
            }
        }
        Some(other) => {
            return Err(Fault::Refused(format!(
                "attributes is a map; got {}",
                other.type_name()
            )))
        }
    }
    let text = match field(el, "text") {
        None | Some(Value::Nil) => String::new(),
        Some(v) => scalar(v)
            .ok_or_else(|| Fault::Refused(format!("text is text; got {}", v.type_name())))?,
    };
    let children: Vec<Value> = match field(el, "children") {
        None | Some(Value::Nil) => Vec::new(),
        Some(Value::List(xs)) => xs.iter().cloned().collect(),
        Some(other) => {
            return Err(Fault::Refused(format!(
                "children is a list; got {}",
                other.type_name()
            )))
        }
    };
    if text.is_empty() && children.is_empty() {
        out.push_str("/>");
        return Ok(());
    }
    out.push('>');
    escape_into(out, &text, false)?;
    for child in &children {
        render_into(out, child, depth + 1)?;
    }
    out.push_str("</");
    out.push_str(&name);
    out.push('>');
    Ok(())
}

pub fn render(el: &Value) -> Result<String, Fault> {
    let mut out = String::new();
    render_into(&mut out, el, 0)?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get<'a>(el: &'a Value, k: &str) -> &'a Value {
        field(el, k).unwrap_or_else(|| panic!("no {k} in {el:?}"))
    }

    fn text(el: &Value) -> String {
        scalar(get(el, "text")).unwrap_or_default()
    }

    fn kids(el: &Value) -> Vec<Value> {
        match get(el, "children") {
            Value::List(xs) => xs.iter().cloned().collect(),
            other => panic!("children {other:?}"),
        }
    }

    #[test]
    fn an_empty_document_is_malformed_not_nil() {
        assert!(matches!(parse(""), Err(Fault::Malformed(_))));
        assert!(matches!(parse("   \n"), Err(Fault::Malformed(_))));
    }

    #[test]
    fn a_parsed_document_renders_and_parses_back_to_itself() {
        let src = "<?xml version=\"1.0\"?><!DOCTYPE r><r a=\"1 &amp; &lt;2&gt; &quot;q&quot;\" ns:b=\"x&#10;y\"><c>t &amp; u</c><c/><![CDATA[<raw>&]]></r>";
        let once = render(&parse(src).expect("parses")).expect("renders");
        let again = render(&parse(&once).expect("reparses")).expect("renders again");
        assert_eq!(once, again);
        assert_eq!(
            once,
            "<r a=\"1 &amp; &lt;2&gt; &quot;q&quot;\" ns:b=\"x&#10;y\">&lt;raw&gt;&amp;<c>t &amp; u</c><c/></r>"
        );
    }

    #[test]
    fn values_are_unescaped_and_prefixes_kept() {
        let el = parse("<x:r xmlns:x=\"urn:example\" a=\"&lt;&#65;&#x42;\">1 &gt; 0</x:r>")
            .expect("parses");
        assert_eq!(scalar(get(&el, "name")).as_deref(), Some("x:r"));
        let Value::Map(attrs) = get(&el, "attributes") else {
            panic!()
        };
        assert_eq!(
            attrs
                .get(&MapKey::Str(Arc::from("a")))
                .and_then(scalar)
                .as_deref(),
            Some("<AB")
        );
        assert_eq!(
            attrs
                .get(&MapKey::Str(Arc::from("xmlns:x")))
                .and_then(scalar)
                .as_deref(),
            Some("urn:example")
        );
        assert_eq!(text(&el), "1 > 0");
    }

    #[test]
    fn whitespace_between_elements_is_not_text() {
        let el = parse("<a>\n  <b> x </b>\n  <c/>\n</a>").expect("parses");
        assert_eq!(text(&el), "");
        assert_eq!(kids(&el).len(), 2);
        assert_eq!(text(&kids(&el)[0]), " x ");
    }

    #[test]
    fn malformed_documents_are_refused_by_kind() {
        for bad in [
            "<a>",
            "<a></b>",
            "<a><b></a></b>",
            "</a>",
            "<a/><b/>",
            "text<a/>",
            "<a x=1/>",
            "<a x=\"1\" x=\"2\"/>",
            "<a>&#0;</a>",
        ] {
            assert!(
                matches!(parse(bad), Err(Fault::Malformed(_))),
                "{bad}: {:?}",
                parse(bad)
            );
        }
    }

    #[test]
    fn external_and_internal_entities_are_never_expanded() {
        let xxe = "<?xml version=\"1.0\"?><!DOCTYPE r [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><r>&x;</r>";
        assert!(matches!(parse(xxe), Err(Fault::Refused(_))));
        let laughs = "<!DOCTYPE r [<!ENTITY a \"ha\"><!ENTITY b \"&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;\">]><r>&b;</r>";
        assert!(matches!(parse(laughs), Err(Fault::Refused(_))));
        assert!(matches!(parse("<r>&x;</r>"), Err(Fault::Refused(_))));
        assert!(matches!(parse("<r a=\"&x;\"/>"), Err(Fault::Refused(_))));
        let unreferenced = "<!DOCTYPE r [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><r/>";
        assert!(matches!(parse(unreferenced), Err(Fault::Refused(_))));
        let declared_only =
            "<!DOCTYPE issues [<!ELEMENT issues (issue*)><!ATTLIST issues v CDATA \"\">]><issues/>";
        assert!(parse(declared_only).is_ok());
    }

    #[test]
    fn nesting_beyond_the_bound_is_refused() {
        let deep = format!(
            "{}{}",
            "<a>".repeat(MAX_DEPTH + 1),
            "</a>".repeat(MAX_DEPTH + 1)
        );
        assert!(matches!(parse(&deep), Err(Fault::Refused(_))));
        let ok = format!("{}{}", "<a>".repeat(MAX_DEPTH), "</a>".repeat(MAX_DEPTH));
        assert!(parse(&ok).is_ok());
    }

    #[test]
    fn faults_name_their_line_and_column() {
        let Err(Fault::Malformed(m)) = parse("<a>\n\n  x <b></a>") else {
            panic!()
        };
        assert!(m.contains("line 3, column"), "{m}");
        let Err(Fault::Malformed(m)) = parse("<a/>\n  <b/>") else {
            panic!()
        };
        assert!(m.ends_with("line 2, column 3"), "{m}");
        let Err(Fault::Malformed(m)) = parse("<a/>\n<!DOCTYPE a>") else {
            panic!()
        };
        assert!(m.contains("DOCTYPE"), "{m}");
        assert!(parse("\n <r/>\n").is_ok());
    }

    #[test]
    fn render_is_bounded_like_parse_and_checks_names() {
        let mut el = element("a".into(), vec![], vec![], String::new());
        for _ in 1..MAX_DEPTH {
            el = element("a".into(), vec![], vec![el], String::new());
        }
        let text = render(&el).expect("the deepest document parse accepts renders");
        assert!(parse(&text).is_ok());
        let deeper = element("a".into(), vec![], vec![el], String::new());
        assert!(matches!(render(&deeper), Err(Fault::Refused(_))));
        for ok in ["a", "a1", "a-b.c", "_x", "x:y", "\u{e9}t\u{e9}"] {
            let el = element(ok.into(), vec![], vec![], String::new());
            assert!(render(&el).is_ok(), "{ok}");
        }
        for bad in ["1a", "-a", ".a", "a b", "a\u{2003}b", "a\u{85}b", ""] {
            let el = element(bad.into(), vec![], vec![], String::new());
            assert!(matches!(render(&el), Err(Fault::Refused(_))), "{bad:?}");
        }
        let kinds = Value::map([
            (key("name"), Value::Str(Arc::from("r"))),
            (
                key("attributes"),
                Value::map([
                    (MapKey::Str(Arc::from("b")), Value::Bool(true)),
                    (MapKey::Str(Arc::from("f")), Value::Float(1.5)),
                    (MapKey::Str(Arc::from("n")), Value::Int(7)),
                ]),
            ),
        ]);
        assert_eq!(
            render(&kinds).expect("renders"),
            "<r b=\"true\" f=\"1.5\" n=\"7\"/>"
        );
    }

    #[test]
    fn render_escapes_and_refuses_what_xml_cannot_hold() {
        let el = element(
            "r".into(),
            vec![("q".into(), "a\"<&>\t".into())],
            vec![],
            "x < y & z".into(),
        );
        assert_eq!(
            render(&el).expect("renders"),
            "<r q=\"a&quot;&lt;&amp;&gt;&#9;\">x &lt; y &amp; z</r>"
        );
        let plain = element("r".into(), vec![], vec![], "a\"b\n\tc".into());
        assert_eq!(render(&plain).expect("renders"), "<r>a\"b\n\tc</r>");
        let bad = element("r x".into(), vec![], vec![], String::new());
        assert!(matches!(render(&bad), Err(Fault::Refused(_))));
        let ctl = element("r".into(), vec![], vec![], "\u{1}".into());
        assert!(matches!(render(&ctl), Err(Fault::Refused(_))));
        assert!(matches!(render(&Value::Int(1)), Err(Fault::Refused(_))));
    }

    #[test]
    fn the_primitives_raise_typed_kinds_in_blue() {
        let err = crate::run(r#"xml_parse("<a>")"#).expect_err("must raise");
        assert!(err.to_string().contains(MALFORMED), "{err}");
        let err = crate::run(r#"xml_parse("<r>&x;</r>")"#).expect_err("must raise");
        assert!(err.to_string().contains(REFUSED), "{err}");
        let v = crate::run(r#"xml_render(xml_parse("<a b=\"1\"><c/></a>"))"#)
            .expect("runs")
            .value;
        assert_eq!(scalar(&v).as_deref(), Some("<a b=\"1\"><c/></a>"));
    }
}
