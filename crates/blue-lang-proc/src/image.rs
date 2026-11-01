use std::collections::{BTreeMap, VecDeque};

use serde_json::{json, Value as Json};
use tatara_lisp_eval::vm::Parked;
use tatara_lisp_eval::Value;

use crate::code::Code;
use crate::receipt::canonical;
use crate::scheduling::Scheduling;
use crate::trace::{
    code_from_json, code_to_json, tape_from_json, tape_to_json, value_from_json, value_to_json,
    TapeEntry,
};

pub const FORMAT: &str = "blue-image";

pub const VERSION: u64 = 1;

pub const HANDED: u64 = 2;

pub const PARKED: u64 = 3;

pub const TAPED: u64 = 4;

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
    pub parked: Option<Continuation>,
    pub tape: Option<Vec<TapeEntry>>,
}

#[derive(Clone, Debug)]
pub struct Continuation {
    pub vm: Parked,
    pub functions: Vec<(String, usize)>,
    pub wait_ms: Option<u64>,
}

impl Continuation {
    fn to_json(&self) -> Json {
        let mut j = json!({
            "vm": serde_json::to_value(&self.vm).unwrap_or(Json::Null),
            "functions": self
                .functions
                .iter()
                .map(|(name, index)| json!([name, index]))
                .collect::<Vec<_>>(),
        });
        if let Some(ms) = self.wait_ms {
            j["wait_ms"] = json!(ms);
        }
        j
    }

    fn from_json(j: &Json) -> Result<Self, String> {
        let vm = j
            .get("vm")
            .cloned()
            .ok_or_else(|| format!("{FORMAT}: `parked` has no `vm`"))
            .and_then(|vm| {
                serde_json::from_value(vm)
                    .map_err(|e| format!("{FORMAT}: `parked.vm` is not a parked VM: {e}"))
            })?;
        let functions = j
            .get("functions")
            .and_then(Json::as_array)
            .ok_or_else(|| format!("{FORMAT}: `parked` has no `functions`"))?
            .iter()
            .map(|f| match f.as_array().map(Vec::as_slice) {
                Some([name, index]) => name
                    .as_str()
                    .zip(index.as_u64().and_then(|n| usize::try_from(n).ok()))
                    .map(|(name, index)| (name.to_string(), index)),
                _ => None,
            })
            .map(|f| f.ok_or_else(|| format!("{FORMAT}: a `parked` function is not [name, index]")))
            .collect::<Result<_, _>>()?;
        let wait_ms = j
            .get("wait_ms")
            .map(|n| {
                n.as_u64()
                    .ok_or_else(|| format!("{FORMAT}: `parked.wait_ms` is not a count"))
            })
            .transpose()?;
        Ok(Self {
            vm,
            functions,
            wait_ms,
        })
    }
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
        if let Some(c) = &self.parked {
            j["parked"] = c.to_json();
            j["version"] = json!(PARKED);
        }
        if let Some(t) = &self.tape {
            j["tape"] = tape_to_json(t);
            j["version"] = json!(TAPED);
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
        if ![VERSION, HANDED, PARKED, TAPED].contains(&version) {
            return Err(format!(
                "{FORMAT} version {version}; this blue reads versions {VERSION}, {HANDED}, {PARKED} and {TAPED}"
            ));
        }
        let parked = j.get("parked").map(Continuation::from_json).transpose()?;
        let tape = j.get("tape").map(tape_from_json).transpose()?;
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
        match (
            version,
            supervision.is_some() || dispatch_steps.is_some(),
            parked.is_some(),
            tape.is_some(),
        ) {
            (VERSION, true, _, _) => {
                return Err(format!(
                    "{FORMAT} version {VERSION} carries no supervision or dispatch_steps, and this one does"
                ))
            }
            (VERSION | HANDED, _, true, _) => {
                return Err(format!(
                    "{FORMAT} version {version} carries no parked frames, and this one does"
                ))
            }
            (VERSION | HANDED | PARKED, _, _, true) => {
                return Err(format!(
                    "{FORMAT} version {version} carries no tape, and this one does"
                ))
            }
            (HANDED, false, _, _) => {
                return Err(format!(
                    "{FORMAT} version {HANDED} carries supervision or dispatch_steps, and this one carries neither"
                ))
            }
            (PARKED | TAPED, _, false, _) => {
                return Err(format!(
                    "{FORMAT} version {version} carries a parked process, and this one carries none"
                ))
            }
            (TAPED, _, _, false) => {
                return Err(format!(
                    "{FORMAT} version {TAPED} carries the tape of the process it parks, and this one carries none"
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
            parked,
            tape,
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
            parked: None,
            tape: None,
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
        assert!(Image::parse(&three).is_err_and(|e| e.contains("this one carries none")));
        let four = text.replacen("\"version\":2", "\"version\":4", 1);
        assert!(Image::parse(&four).is_err_and(|e| e.contains("this one carries none")));
        let five = text.replacen("\"version\":2", "\"version\":5", 1);
        assert!(Image::parse(&five).is_err_and(|e| e.contains("versions 1, 2, 3 and 4")));
    }

    fn parked() -> Continuation {
        use tatara_lisp_eval::vm::{Fingerprint, FnRef, ParkedFrame, ParkedValue};
        Continuation {
            vm: Parked {
                chunk: Fingerprint([7; 32]),
                stack: vec![
                    ParkedValue::Float((-0.1_f64).to_bits()),
                    ParkedValue::Closure {
                        func: 1,
                        captures: vec![0],
                    },
                    ParkedValue::Native("receive".to_string()),
                ],
                frames: vec![ParkedFrame {
                    func: FnRef::Top,
                    ip: 4,
                    locals_base: 0,
                    stack_base: 1,
                    captures: Vec::new(),
                    local_cells: vec![(0, 0)],
                    handlers: Vec::new(),
                }],
                cells: vec![ParkedValue::Str("ünï".to_string())],
            },
            functions: vec![("h".to_string(), 0)],
            wait_ms: Some(400),
        }
    }

    #[test]
    fn a_parked_process_is_version_three_and_every_misfit_is_refused_by_name() {
        let mut plain = image("x");
        plain.parked = Some(parked());
        let text = plain.text();
        assert!(text.contains("\"version\":3"), "{text}");
        let back = Image::parse(&text).expect("parses");
        let c = back.parked.clone().expect("carried");
        assert_eq!(c.vm, parked().vm);
        assert_eq!(c.functions, vec![("h".to_string(), 0)]);
        assert_eq!(c.wait_ms, Some(400));
        assert_eq!(back.text(), text);
        let mut handed = plain.clone();
        handed.supervision = Some(Supervision {
            max_restarts: 2,
            restarts: 1,
            initial: Value::Nil,
        });
        let both = handed.text();
        assert!(both.contains("\"version\":3"), "{both}");
        assert_eq!(
            Image::parse(&both)
                .expect("parses")
                .supervision
                .map(|s| s.restarts),
            Some(1)
        );
        let mut forever = plain.clone();
        forever.parked = Some(Continuation {
            wait_ms: None,
            ..parked()
        });
        assert!(!forever.text().contains("wait_ms"));
        for (from, to, refusal) in [
            ("\"version\":3", "\"version\":1", "carries no parked frames"),
            ("\"version\":3", "\"version\":2", "carries no parked frames"),
            ("\"parked\":", "\"lost\":", "this one carries none"),
            ("[\"h\",0]", "[\"h\"]", "is not [name, index]"),
            ("\"wait_ms\":400", "\"wait_ms\":-1", "is not a count"),
            ("\"chunk\":[", "\"chunk\":[\"x\",", "is not a parked VM"),
        ] {
            let misfit = text.replacen(from, to, 1);
            assert_ne!(misfit, text, "{from}");
            assert!(
                Image::parse(&misfit).is_err_and(|e| e.contains(refusal)),
                "{from} -> {to}: {:?}",
                Image::parse(&misfit).err()
            );
        }
    }

    #[test]
    fn a_server_image_keeps_the_bytes_it_had_before_plain_processes_moved() {
        let mut held = image("x");
        held.supervision = Some(Supervision {
            max_restarts: 3,
            restarts: 1,
            initial: Value::Str("start".into()),
        });
        held.dispatch_steps = Some(2000);
        assert_eq!(
            [id_of(&image("x").text()), id_of(&held.text())],
            [
                "7d088eeaaa698fa76573fa7b49e9b205483c2cee2dd8254878b30b7b2e75028b".to_string(),
                "5e193f0ea002337e722069705cb1300950a183c6ae532c40f8c5a432e284ea68".to_string()
            ]
        );
    }

    #[test]
    fn a_parked_image_without_a_tape_keeps_the_bytes_it_had_before_tapes_moved() {
        let mut plain = image("x");
        plain.parked = Some(parked());
        let mut handed = plain.clone();
        handed.supervision = Some(Supervision {
            max_restarts: 2,
            restarts: 1,
            initial: Value::Nil,
        });
        assert_eq!(
            [id_of(&plain.text()), id_of(&handed.text())],
            [
                "a28420d56bc459a782ae3d6aa0af9b554d39bdb310e8ece73c4d230c1d8a36b5".to_string(),
                "b0746c35d338e523bb54dfd6e3b2bf955508d5d797007c21b8b963cf924deab2".to_string()
            ]
        );
    }

    #[test]
    fn a_parked_process_with_its_tape_is_version_four_and_every_misfit_is_refused_by_name() {
        let tape = vec![
            TapeEntry {
                call: "receive".to_string(),
                outcome: Ok(Value::Float(f64::NAN)),
                fatal: None,
                at: None,
            },
            TapeEntry {
                call: "now_ms".to_string(),
                outcome: Err("no clock".to_string()),
                fatal: None,
                at: None,
            },
            TapeEntry {
                call: "is_file?".to_string(),
                outcome: Err("`is_file?` reaches the host (filesystem)".to_string()),
                fatal: Some("capability-breach".to_string()),
                at: Some(tatara_lisp::Span::new(3, 9)),
            },
        ];
        let mut plain = image("x");
        plain.parked = Some(parked());
        plain.tape = Some(tape.clone());
        let text = plain.text();
        assert!(text.contains("\"version\":4"), "{text}");
        let back = Image::parse(&text).expect("parses");
        assert_eq!(
            crate::trace::tape_hash(&back.tape.clone().expect("carried")),
            crate::trace::tape_hash(&tape)
        );
        assert!(back.parked.is_some());
        assert_eq!(back.text(), text);
        let mut empty = plain.clone();
        empty.tape = Some(Vec::new());
        let none_yet = empty.text();
        assert!(
            none_yet.contains("\"version\":4") && none_yet.contains("\"tape\":[]"),
            "a process that took nothing yet carries an empty tape, not none: {none_yet}"
        );
        for (from, to, refusal) in [
            (
                "\"version\":4",
                "\"version\":3",
                "version 3 carries no tape",
            ),
            ("\"version\":4", "\"version\":1", "carries no parked frames"),
            (
                "\"tape\":",
                "\"lost\":",
                "carries the tape of the process it parks",
            ),
            (
                "\"parked\":",
                "\"gone\":",
                "version 4 carries a parked process",
            ),
            (
                "\"call\":\"now_ms\"",
                "\"cell\":\"now_ms\"",
                "not a blue-trace tape entry",
            ),
        ] {
            let misfit = text.replacen(from, to, 1);
            assert_ne!(misfit, text, "{from}");
            assert!(
                Image::parse(&misfit).is_err_and(|e| e.contains(refusal)),
                "{from} -> {to}: {:?}",
                Image::parse(&misfit).err()
            );
        }
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
