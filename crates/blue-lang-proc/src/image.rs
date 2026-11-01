use std::collections::{BTreeMap, VecDeque};

use serde_json::{json, Value as Json};
use tatara_lisp_eval::Value;

use crate::code::Code;
use crate::receipt::canonical;
use crate::scheduling::Scheduling;
use crate::trace::{code_from_json, code_to_json, value_from_json, value_to_json};

pub const FORMAT: &str = "blue-image";

pub const VERSION: u64 = 1;

pub const HANDED: u64 = 2;

pub const FRAME: &str = "blue-image ";

pub const MAX_FRAMES: usize = 9999;

pub const ARRIVING: usize = 16;

pub const ADMITTED: usize = 256;

const HEX: usize = 64;

#[derive(Clone, Debug)]
pub struct Image {
    pub definition: Option<String>,
    pub scheduling: Scheduling,
    pub trap_exit: bool,
    pub code: Code,
    pub mailbox: Vec<Value>,
    pub supervision: Option<Supervision>,
    pub dispatch_steps: Option<usize>,
}

#[derive(Clone, Debug)]
pub struct Supervision {
    pub max_restarts: usize,
    pub restarts: usize,
    pub initial: Value,
}

impl Supervision {
    fn to_json(&self) -> Json {
        json!({
            "max_restarts": self.max_restarts,
            "restarts": self.restarts,
            "initial": value_to_json(&self.initial),
        })
    }

    fn from_json(j: &Json) -> Result<Self, String> {
        let count = |key: &str| {
            j.get(key)
                .and_then(Json::as_u64)
                .and_then(|n| usize::try_from(n).ok())
                .ok_or_else(|| format!("{FORMAT}: `supervision` has no `{key}` count"))
        };
        Ok(Self {
            max_restarts: count("max_restarts")?,
            restarts: count("restarts")?,
            initial: value_from_json(
                j.get("initial")
                    .ok_or_else(|| format!("{FORMAT}: `supervision` has no `initial` state"))?,
            )?,
        })
    }
}

impl Image {
    #[must_use]
    pub fn to_json(&self) -> Json {
        let mut j = json!({
            "format": FORMAT,
            "version": VERSION,
            "definition": self.definition,
            "scheduling": self.scheduling.label(),
            "trap_exit": self.trap_exit,
            "code": code_to_json(&self.code),
            "mailbox": self.mailbox.iter().map(value_to_json).collect::<Vec<_>>(),
        });
        if let Some(s) = &self.supervision {
            j["supervision"] = s.to_json();
        }
        if let Some(n) = self.dispatch_steps {
            j["dispatch_steps"] = json!(n);
        }
        if self.hands_over() {
            j["version"] = json!(HANDED);
        }
        j
    }

    #[must_use]
    pub fn hands_over(&self) -> bool {
        self.supervision.is_some() || self.dispatch_steps.is_some()
    }

    pub fn from_json(j: &Json) -> Result<Self, String> {
        if j.get("format").and_then(Json::as_str) != Some(FORMAT) {
            return Err(format!("not a {FORMAT}"));
        }
        let version = j.get("version").and_then(Json::as_u64).unwrap_or(0);
        if version != VERSION && version != HANDED {
            return Err(format!(
                "{FORMAT} version {version}; this blue reads versions {VERSION} and {HANDED}"
            ));
        }
        let supervision = j
            .get("supervision")
            .map(Supervision::from_json)
            .transpose()?;
        let dispatch_steps = j
            .get("dispatch_steps")
            .map(|n| {
                n.as_u64()
                    .and_then(|n| usize::try_from(n).ok())
                    .filter(|n| *n > 0)
                    .ok_or_else(|| format!("{FORMAT}: `dispatch_steps` is not a positive count"))
            })
            .transpose()?;
        match (version, supervision.is_some() || dispatch_steps.is_some()) {
            (VERSION, true) => {
                return Err(format!(
                    "{FORMAT} version {VERSION} carries no supervision or dispatch_steps, and this one does"
                ))
            }
            (HANDED, false) => {
                return Err(format!(
                    "{FORMAT} version {HANDED} carries supervision or dispatch_steps, and this one carries neither"
                ))
            }
            _ => {}
        }
        let scheduling = j
            .get("scheduling")
            .and_then(Json::as_str)
            .ok_or_else(|| format!("{FORMAT}: missing `scheduling`"))
            .and_then(|w| Scheduling::named(w).map_err(|r| r.to_string()))?;
        let code = code_from_json(
            j.get("code")
                .ok_or_else(|| format!("{FORMAT}: missing `code`"))?,
        )?;
        if code.start.is_none() {
            return Err(format!("{FORMAT}: its code starts nowhere"));
        }
        let mailbox = j
            .get("mailbox")
            .and_then(Json::as_array)
            .ok_or_else(|| format!("{FORMAT}: missing `mailbox`"))?
            .iter()
            .map(value_from_json)
            .collect::<Result<_, _>>()?;
        Ok(Self {
            definition: j
                .get("definition")
                .and_then(Json::as_str)
                .map(str::to_string),
            scheduling,
            trap_exit: j.get("trap_exit").and_then(Json::as_bool).unwrap_or(false),
            code,
            mailbox,
            supervision,
            dispatch_steps,
        })
    }

    #[must_use]
    pub fn text(&self) -> String {
        canonical(&self.to_json())
    }

    pub fn parse(text: &str) -> Result<Self, String> {
        let j: Json =
            serde_json::from_str(text).map_err(|e| format!("{FORMAT} is not JSON: {e}"))?;
        Self::from_json(&j)
    }
}

#[must_use]
pub fn id_of(text: &str) -> String {
    blake3::hash(text.as_bytes()).to_hex().to_string()
}

fn header(id: &str, index: usize, count: usize) -> String {
    format!("{FRAME}{VERSION} {id} {index:04} {count:04}\n")
}

pub fn frames(id: &str, text: &str, room: usize) -> Result<Vec<String>, String> {
    let head = header(id, 0, 0).len();
    let budget = room
        .checked_sub(head)
        .filter(|b| *b >= 4)
        .ok_or_else(|| format!("a frame of {room} bytes cannot hold a {head}-byte image header"))?;
    let mut chunks = Vec::new();
    let mut rest = text;
    while !rest.is_empty() {
        let mut cut = budget.min(rest.len());
        while !rest.is_char_boundary(cut) {
            cut -= 1;
        }
        let (chunk, tail) = rest.split_at(cut);
        chunks.push(chunk);
        rest = tail;
    }
    let count = chunks.len();
    if count > MAX_FRAMES {
        return Err(format!(
            "the image is {} bytes, {count} frames, past the {MAX_FRAMES} one image may take",
            text.len()
        ));
    }
    Ok(chunks
        .iter()
        .enumerate()
        .map(|(i, chunk)| format!("{}{chunk}", header(id, i, count)))
        .collect())
}

struct Partial {
    count: usize,
    chunks: BTreeMap<usize, String>,
}

#[derive(Default)]
pub struct Arrivals {
    order: VecDeque<String>,
    partial: BTreeMap<String, Partial>,
    admitted: VecDeque<String>,
}

fn parsed(payload: &str) -> Result<(String, usize, usize, &str), String> {
    let rest = payload
        .strip_prefix(FRAME)
        .ok_or_else(|| "not an image frame".to_string())?;
    let (head, chunk) = rest
        .split_once('\n')
        .ok_or_else(|| "an image frame with no header line".to_string())?;
    let fields: Vec<&str> = head.split(' ').collect();
    let [version, id, index, count] = fields.as_slice() else {
        return Err(format!(
            "an image frame header `{head}` is not `version id index count`"
        ));
    };
    if *version != VERSION.to_string() {
        return Err(format!(
            "an image frame of version {version}; this blue reads version {VERSION}"
        ));
    }
    if id.len() != HEX || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(format!("an image frame names `{id}`, not a BLAKE3 hash"));
    }
    let number = |s: &str| {
        s.parse::<usize>()
            .map_err(|_| format!("an image frame header `{head}` has no count"))
    };
    let (index, count) = (number(index)?, number(count)?);
    if count == 0 || count > MAX_FRAMES || index >= count {
        return Err(format!("an image frame header `{head}` is out of range"));
    }
    Ok(((*id).to_string(), index, count, chunk))
}

impl Arrivals {
    pub fn file(&mut self, payload: &str) -> Result<(), String> {
        let (id, index, count, chunk) = parsed(payload)?;
        if self.admitted.contains(&id) {
            return Ok(());
        }
        if !self.partial.contains_key(&id) {
            if self.order.len() == ARRIVING {
                if let Some(oldest) = self.order.pop_front() {
                    self.partial.remove(&oldest);
                }
            }
            self.order.push_back(id.clone());
            self.partial.insert(
                id.clone(),
                Partial {
                    count,
                    chunks: BTreeMap::new(),
                },
            );
        }
        let had = self.partial.get(&id).map_or(count, |p| p.count);
        if had != count {
            self.forget(&id);
            return Err(format!(
                "image {id} arrived as {had} frames and as {count}; it is dropped"
            ));
        }
        if let Some(p) = self.partial.get_mut(&id) {
            p.chunks.insert(index, chunk.to_string());
        }
        Ok(())
    }

    fn forget(&mut self, id: &str) {
        self.partial.remove(id);
        self.order.retain(|o| o != id);
    }

    pub fn complete(&mut self) -> Option<Result<String, String>> {
        let id = self
            .order
            .iter()
            .find(|id| {
                self.partial
                    .get(*id)
                    .is_some_and(|p| p.chunks.len() == p.count)
            })?
            .clone();
        let p = self.partial.remove(&id)?;
        self.order.retain(|o| *o != id);
        let text: String = p.chunks.into_values().collect();
        if id_of(&text) != id {
            return Some(Err(format!(
                "image {id} arrived whole, and its bytes hash to another name; it is dropped"
            )));
        }
        if self.admitted.len() == ADMITTED {
            self.admitted.pop_front();
        }
        self.admitted.push_back(id);
        Some(Ok(text))
    }

    #[must_use]
    pub fn waiting(&self) -> usize {
        self.partial.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn image(text: &str) -> Image {
        Image {
            definition: Some("%root/h".to_string()),
            scheduling: Scheduling::Idle,
            trap_exit: true,
            code: Code {
                defs: tatara_lisp::read_spanned("(define (h m s) s)").expect("reads"),
                bindings: vec![(std::sync::Arc::from("%state"), Value::Str(text.into()))],
                start: tatara_lisp::read_spanned("(h 1 2)").expect("reads").pop(),
            },
            mailbox: vec![Value::Int(4), Value::Str("ünï".into())],
            supervision: None,
            dispatch_steps: None,
        }
    }

    #[test]
    fn an_image_survives_its_text_and_every_frame_fits_the_room() {
        let original = image(&"日本語".repeat(400));
        let text = original.text();
        let id = id_of(&text);
        let frames = frames(&id, &text, 1271).expect("frames");
        assert!(frames.len() > 1);
        assert!(frames
            .iter()
            .all(|f| f.len() <= 1271 && f.starts_with(FRAME)));
        let mut arrivals = Arrivals::default();
        for f in frames.iter().rev() {
            arrivals.file(f).expect("a frame");
        }
        let whole = arrivals.complete().expect("complete").expect("intact");
        assert_eq!(whole, text);
        let back = Image::parse(&whole).expect("parses");
        assert_eq!(back.text(), text);
        assert_eq!(back.scheduling, Scheduling::Idle);
        assert!(back.trap_exit);
        assert_eq!(back.mailbox.len(), 2);
    }

    #[test]
    fn a_frame_of_an_image_already_admitted_completes_nothing_again() {
        let text = image("x").text();
        let id = id_of(&text);
        let frames = frames(&id, &text, 1271).expect("frames");
        let mut arrivals = Arrivals::default();
        for f in &frames {
            arrivals.file(f).expect("a frame");
        }
        assert!(matches!(arrivals.complete(), Some(Ok(_))));
        for f in &frames {
            arrivals.file(f).expect("a re-delivered frame");
        }
        assert!(
            arrivals.complete().is_none(),
            "a duplicate is not a second process"
        );
        assert_eq!(arrivals.waiting(), 0);
    }

    #[test]
    fn a_missing_frame_leaves_the_image_waiting_and_a_mismatched_count_drops_it() {
        let text = image(&"y".repeat(3000)).text();
        let id = id_of(&text);
        let frames = frames(&id, &text, 1271).expect("frames");
        let mut arrivals = Arrivals::default();
        arrivals.file(&frames[0]).expect("a frame");
        assert!(arrivals.complete().is_none());
        assert_eq!(arrivals.waiting(), 1);
        let lying = frames[1].replacen(&format!(" {:04}\n", frames.len()), " 0099\n", 1);
        assert!(arrivals.file(&lying).is_err());
        assert_eq!(arrivals.waiting(), 0);
    }

    #[test]
    fn an_image_that_hands_over_nothing_stays_version_one_and_one_that_does_is_version_two() {
        let plain = image("x");
        let text = plain.text();
        assert!(text.contains("\"version\":1"), "{text}");
        assert!(
            !text.contains("supervision") && !text.contains("dispatch_steps"),
            "{text}"
        );
        let mut held = image("x");
        held.supervision = Some(Supervision {
            max_restarts: 3,
            restarts: 1,
            initial: Value::Str("start".into()),
        });
        held.dispatch_steps = Some(2000);
        let text = held.text();
        assert!(text.contains("\"version\":2"), "{text}");
        let back = Image::parse(&text).expect("parses");
        let s = back.supervision.clone().expect("carried");
        assert_eq!((s.max_restarts, s.restarts), (3, 1));
        assert_eq!(s.initial.to_string(), "\"start\"");
        assert_eq!(back.dispatch_steps, Some(2000));
        assert_eq!(back.text(), text);
        let mut bounded = image("x");
        bounded.dispatch_steps = Some(7);
        let only = bounded.text();
        assert!(only.contains("\"version\":2"), "{only}");
        assert_eq!(Image::parse(&only).expect("parses").dispatch_steps, Some(7));
        let neither = only.replacen("\"dispatch_steps\":", "\"lost\":", 1);
        assert!(Image::parse(&neither).is_err_and(|e| e.contains("carries neither")));
        let carried_one = text.replacen("\"version\":2", "\"version\":1", 1);
        assert!(Image::parse(&carried_one)
            .is_err_and(|e| e.contains("carries no supervision or dispatch_steps")));
        let zero = only.replacen("\"dispatch_steps\":7", "\"dispatch_steps\":0", 1);
        assert!(Image::parse(&zero).is_err_and(|e| e.contains("not a positive count")));
        let three = text.replacen("\"version\":2", "\"version\":3", 1);
        assert!(Image::parse(&three).is_err_and(|e| e.contains("versions 1 and 2")));
    }

    #[test]
    fn a_header_that_is_no_header_is_refused_by_name() {
        let zeros = "0".repeat(64);
        let mut arrivals = Arrivals::default();
        for bad in [
            "blue-image 1 abc 0000 0001\nx".to_string(),
            format!("blue-image 2 {zeros} 0000 0001\nx"),
            format!("blue-image 1 {zeros} 0003 0002\nx"),
            "blue-image no newline".to_string(),
        ] {
            assert!(arrivals.file(&bad).is_err(), "{bad}");
        }
        assert_eq!(arrivals.waiting(), 0);
        assert!(
            frames("a", "b", 10).is_err(),
            "a room smaller than the header holds nothing"
        );
    }
}
