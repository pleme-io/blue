use std::collections::VecDeque;
use std::sync::{Arc, Mutex, PoisonError};

use blue_lang_senses::audio::{self as device, Clip, Format};
use blue_lang_senses::Refusal;
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind;
use crate::net::record;
use crate::provide::Key;

type Span = tatara_lisp::Span;

pub const VIRTUAL: Format = Format {
    rate: 48_000,
    channels: 2,
};
pub const SINK_SAMPLES: usize = 1 << 22;

#[derive(Default)]
pub struct Sink {
    clips: Mutex<VecDeque<Clip>>,
}

impl Sink {
    fn keep(&self, clip: Clip) {
        let mut clips = self.clips.lock().unwrap_or_else(PoisonError::into_inner);
        clips.push_back(clip);
        let mut held: usize = clips.iter().map(|c| c.samples.len()).sum();
        while held > SINK_SAMPLES {
            match clips.pop_front() {
                Some(old) => held -= old.samples.len(),
                None => break,
            }
        }
    }

    #[must_use]
    pub fn played(&self) -> Vec<Clip> {
        self.clips
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .iter()
            .cloned()
            .collect()
    }

    fn take(&self, format: Format, frames: usize, span: Span) -> Result<Vec<f64>, EvalError> {
        let want = frames * usize::from(format.channels);
        let mut out = Vec::with_capacity(want);
        let mut clips = self.clips.lock().unwrap_or_else(PoisonError::into_inner);
        while out.len() < want {
            let Some(front) = clips.front_mut() else {
                break;
            };
            if front.format != format {
                return Err(bad_option(
                    "capture_audio",
                    format!(
                        "the monitor holds {} Hz {}-channel audio, not {} Hz {}-channel",
                        front.format.rate, front.format.channels, format.rate, format.channels
                    ),
                    span,
                ));
            }
            let n = (want - out.len()).min(front.samples.len());
            out.extend(front.samples.drain(..n));
            if front.samples.is_empty() {
                clips.pop_front();
            }
        }
        out.resize(want, 0.0);
        Ok(out)
    }
}

#[derive(Clone)]
enum Out {
    Host,
    Sink(Arc<Sink>),
}

#[derive(Clone)]
enum In {
    Host,
    Seeded(Arc<Mutex<blake3::OutputReader>>),
    Monitor(Option<Arc<Sink>>),
}

fn bad_option(word: &'static str, message: String, span: Span) -> EvalError {
    raise_kind("bad_option", format!("{word}: {message}"), span)
}

fn refused(word: &'static str, r: &Refusal, span: Span) -> EvalError {
    raise_kind(r.kind(), format!("{word}: {}", r.message()), span)
}

fn field<'a>(v: &'a Value, name: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(&MapKey::Keyword(Arc::from(name))),
        _ => None,
    }
}

fn int_field(v: &Value, name: &str, word: &'static str, span: Span) -> Result<i64, EvalError> {
    match field(v, name) {
        Some(Value::Int(n)) => Ok(*n),
        Some(other) => Err(bad_option(
            word,
            format!("{name}: is an integer, got {}", other.type_name()),
            span,
        )),
        None => Err(bad_option(
            word,
            format!("a format is a map with rate: and channels:, and {name}: is missing"),
            span,
        )),
    }
}

fn format_of(v: &Value, word: &'static str, span: Span) -> Result<Format, EvalError> {
    if !matches!(v, Value::Map(_)) {
        return Err(bad_option(
            word,
            format!(
                "a format is a map with rate: and channels:, got {}",
                v.type_name()
            ),
            span,
        ));
    }
    let rate = int_field(v, "rate", word, span)?;
    let channels = int_field(v, "channels", word, span)?;
    Format::new(rate, channels).map_err(|e| bad_option(word, e, span))
}

fn clip_of(v: &Value, span: Span) -> Result<Clip, EvalError> {
    const W: &str = "play_audio";
    let format = format_of(v, W, span)?;
    let samples = match field(v, "samples") {
        Some(Value::List(items)) => items
            .iter()
            .enumerate()
            .map(|(i, s)| match s {
                Value::Float(f) => Ok(*f),
                Value::Int(n) => Ok(*n as f64),
                other => Err(bad_option(
                    W,
                    format!("sample {i} is a number, got {}", other.type_name()),
                    span,
                )),
            })
            .collect::<Result<Vec<f64>, EvalError>>()?,
        Some(Value::Nil) => Vec::new(),
        Some(other) => {
            return Err(bad_option(
                W,
                format!("samples: is a list of numbers, got {}", other.type_name()),
                span,
            ))
        }
        None => {
            return Err(bad_option(
                W,
                "a clip is a map with rate:, channels: and samples:, and samples: is missing"
                    .into(),
                span,
            ))
        }
    };
    Clip::new(format, samples).map_err(|e| bad_option(W, e, span))
}

fn format_value(f: Format) -> Value {
    record(vec![
        ("rate", Value::Int(i64::from(f.rate))),
        ("channels", Value::Int(i64::from(f.channels))),
    ])
}

fn clip_value(format: Format, samples: Vec<f64>) -> Value {
    record(vec![
        ("rate", Value::Int(i64::from(format.rate))),
        ("channels", Value::Int(i64::from(format.channels))),
        (
            "samples",
            Value::list(samples.into_iter().map(Value::Float)),
        ),
    ])
}

fn noise(stream: &Mutex<blake3::OutputReader>, n: usize) -> Vec<f64> {
    let mut bytes = vec![0u8; n * 2];
    stream
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .fill(&mut bytes);
    bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|b| f64::from(i16::from_le_bytes(*b)) / 32768.0)
        .collect()
}

#[must_use]
pub fn seeded_stream(seed: &str) -> blake3::OutputReader {
    blake3::Hasher::new_derive_key("blue seeded-noise 2026-10-31")
        .update(seed.as_bytes())
        .finalize_xof()
}

fn install_out<H: 'static>(interp: &mut Interpreter<H>, key: Key, out: &Out) {
    let o = out.clone();
    interp.register_fn(
        key("play_audio"),
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let clip = clip_of(&a[0], span)?;
            match &o {
                Out::Host => device::play(&clip).map_err(|r| refused("play_audio", &r, span))?,
                Out::Sink(sink) => sink.keep(clip),
            }
            Ok(Value::Nil)
        },
    );
    let o = out.clone();
    interp.register_fn(
        key("audio_out_format"),
        Arity::Exact(0),
        move |_: &[Value], _: &mut H, _| {
            Ok(match &o {
                Out::Host => device::device_format(false)
                    .ok()
                    .flatten()
                    .map_or(Value::Nil, format_value),
                Out::Sink(_) => format_value(VIRTUAL),
            })
        },
    );
}

fn install_in<H: 'static>(interp: &mut Interpreter<H>, key: Key, input: &In) {
    let i = input.clone();
    interp.register_fn(
        key("capture_audio"),
        Arity::Exact(2),
        move |a: &[Value], _: &mut H, span| {
            const W: &str = "capture_audio";
            let frames = match &a[0] {
                Value::Int(n) => device::frames(*n).map_err(|e| bad_option(W, e, span))?,
                other => {
                    return Err(bad_option(
                        W,
                        format!("frames is an integer, got {}", other.type_name()),
                        span,
                    ))
                }
            };
            let format = format_of(&a[1], W, span)?;
            let samples = match &i {
                In::Host => {
                    device::capture(format, frames)
                        .map_err(|r| refused(W, &r, span))?
                        .samples
                }
                In::Seeded(stream) => noise(stream, frames * usize::from(format.channels)),
                In::Monitor(Some(sink)) => sink.take(format, frames, span)?,
                In::Monitor(None) => {
                    return Err(raise_kind(
                        "not_found",
                        "capture_audio: the monitor reads what the run plays into its recording sink, and audio_out is not virtualized with recording_sink".into(),
                        span,
                    ))
                }
            };
            Ok(clip_value(format, samples))
        },
    );
    let i = input.clone();
    interp.register_fn(
        key("audio_in_format"),
        Arity::Exact(0),
        move |_: &[Value], _: &mut H, _| {
            Ok(match &i {
                In::Host => device::device_format(true)
                    .ok()
                    .flatten()
                    .map_or(Value::Nil, format_value),
                In::Seeded(_) | In::Monitor(_) => format_value(VIRTUAL),
            })
        },
    );
}

pub fn install_audio<H: 'static>(interp: &mut Interpreter<H>) {
    install_out(interp, String::from, &Out::Host);
    install_in(interp, String::from, &In::Host);
}

pub fn provide_recording_sink<H: 'static>(interp: &mut Interpreter<H>, key: Key) -> Arc<Sink> {
    let sink = Arc::new(Sink::default());
    install_out(interp, key, &Out::Sink(Arc::clone(&sink)));
    sink
}

pub fn provide_seeded_noise<H: 'static>(interp: &mut Interpreter<H>, key: Key, seed: &str) {
    install_in(
        interp,
        key,
        &In::Seeded(Arc::new(Mutex::new(seeded_stream(seed)))),
    );
}

pub fn provide_monitor<H: 'static>(interp: &mut Interpreter<H>, key: Key, sink: Option<Arc<Sink>>) {
    install_in(interp, key, &In::Monitor(sink));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(interp: &mut Interpreter<()>, src: &str) -> Result<Value, EvalError> {
        let forms = tatara_lisp::read_spanned(src).expect("reads");
        interp.eval_program(&forms, &mut ())
    }

    fn ok(interp: &mut Interpreter<()>, src: &str) -> String {
        eval(interp, src)
            .unwrap_or_else(|e| panic!("{src}: {e}"))
            .to_string()
    }

    fn kind(interp: &mut Interpreter<()>, src: &str) -> String {
        match eval(interp, src) {
            Err(EvalError::User {
                value: Value::Error(e),
                ..
            }) => e.tag.to_string(),
            other => panic!("{src}: {other:?}"),
        }
    }

    fn virtual_pair() -> (Interpreter<()>, Arc<Sink>) {
        let mut interp = crate::interpreter_hostless();
        let sink = provide_recording_sink(&mut interp, String::from);
        provide_monitor(&mut interp, String::from, Some(Arc::clone(&sink)));
        (interp, sink)
    }

    const CLIP: &str =
        "(play_audio (hash-map :rate 8000 :channels 2 :samples (list 0.5 -0.25 1 0 -1.0 0.125)))";

    #[test]
    fn the_recording_sink_keeps_every_clip_played_and_the_monitor_reads_it_back_then_silence() {
        let (mut i, sink) = virtual_pair();
        assert_eq!(ok(&mut i, CLIP), "()");
        let played = sink.played();
        assert_eq!(played.len(), 1);
        assert_eq!(
            played[0].format,
            Format {
                rate: 8000,
                channels: 2
            }
        );
        assert_eq!(played[0].samples, vec![0.5, -0.25, 1.0, 0.0, -1.0, 0.125]);
        assert_eq!(
            ok(
                &mut i,
                "(get (capture_audio 2 (hash-map :rate 8000 :channels 2)) :samples)"
            ),
            "(0.5 -0.25 1 0)"
        );
        assert_eq!(
            ok(
                &mut i,
                "(get (capture_audio 2 (hash-map :rate 8000 :channels 2)) :samples)"
            ),
            "(-1 0.125 0 0)",
            "the monitor reads the rest, then the silence of an output with nothing playing"
        );
        assert_eq!(ok(&mut i, "(get (audio_out_format) :rate)"), "48000");
    }

    #[test]
    fn a_clip_that_is_not_whole_frames_of_samples_within_one_is_refused_and_nothing_is_kept() {
        let (mut i, sink) = virtual_pair();
        for bad in [
            "(play_audio (hash-map :rate 8000 :channels 2 :samples (list 0.5)))",
            "(play_audio (hash-map :rate 8000 :channels 1 :samples (list 1.5)))",
            "(play_audio (hash-map :rate 0 :channels 1 :samples (list)))",
            "(play_audio (hash-map :rate 8000 :channels 1 :samples (list \"x\")))",
            "(play_audio (hash-map :rate 8000 :channels 1))",
            "(play_audio 7)",
        ] {
            assert_eq!(kind(&mut i, bad), "bad_option", "{bad}");
        }
        assert!(sink.played().is_empty());
        assert_eq!(
            kind(
                &mut i,
                "(capture_audio -1 (hash-map :rate 8000 :channels 1))"
            ),
            "bad_option"
        );
        ok(&mut i, CLIP);
        assert_eq!(
            kind(
                &mut i,
                "(capture_audio 1 (hash-map :rate 16000 :channels 2))"
            ),
            "bad_option",
            "the monitor holds another format"
        );
    }

    #[test]
    fn the_seeded_source_answers_the_stream_its_seed_keys_and_another_seed_another() {
        let samples = |v: Value| -> Vec<f64> {
            match field(&v, "samples") {
                Some(Value::List(items)) => items
                    .iter()
                    .map(|s| match s {
                        Value::Float(f) => *f,
                        other => panic!("{other:?}"),
                    })
                    .collect(),
                other => panic!("{other:?}"),
            }
        };
        let capture = |seed: &str| {
            let mut i = crate::interpreter_hostless();
            provide_seeded_noise(&mut i, String::from, seed);
            let src = "(capture_audio 3 (hash-map :rate 16000 :channels 1))";
            let first = samples(eval(&mut i, src).expect("captures"));
            let next = samples(eval(&mut i, src).expect("captures"));
            (first, next)
        };
        let mut stream = blake3::Hasher::new_derive_key("blue seeded-noise 2026-10-31")
            .update(b"s")
            .finalize_xof();
        let mut bytes = [0u8; 6];
        stream.fill(&mut bytes);
        let want: Vec<f64> = bytes
            .as_chunks::<2>()
            .0
            .iter()
            .map(|b| f64::from(i16::from_le_bytes(*b)) / 32768.0)
            .collect();
        let (first, next) = capture("s");
        assert_eq!(first, want);
        assert_ne!(first, next, "the stream continues");
        assert_eq!(capture("s"), (first.clone(), next));
        assert_ne!(capture("t").0, first);
    }

    #[test]
    fn a_monitor_with_no_recording_sink_is_not_found() {
        let mut i = crate::interpreter_hostless();
        provide_monitor(&mut i, String::from, None);
        assert_eq!(
            kind(
                &mut i,
                "(capture_audio 1 (hash-map :rate 8000 :channels 1))"
            ),
            "not_found"
        );
    }
}
