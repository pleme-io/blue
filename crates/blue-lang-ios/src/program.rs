use std::sync::Arc;

use blue_lang_host::{Entry, MapKey, NoLoader, Program, Value};
use tatara_lisp_eval::Map;

use crate::draw::{self, Frame};

#[derive(Debug, thiserror::Error)]
pub enum Fault {
    #[error(transparent)]
    Blue(#[from] blue_lang_host::Error),
    #[error("the program does not define {0}")]
    Missing(&'static str),
    #[error("frame returned {0}, not a map with state and draw")]
    Shape(String),
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Input {
    pub t: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Began,
    Moved,
    Ended,
    Cancelled,
}

impl Phase {
    fn keyword(self) -> &'static str {
        match self {
            Self::Began => "began",
            Self::Moved => "moved",
            Self::Ended => "ended",
            Self::Cancelled => "cancelled",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Event {
    Touch { phase: Phase, x: f64, y: f64 },
}

pub struct App {
    program: Program<()>,
    state: Value,
}

impl App {
    pub fn load(source: &str) -> Result<Self, Fault> {
        let mut program = Program::<()>::builder(Entry::anonymous(source))
            .loader(&NoLoader)
            .load(&mut ())?;
        for name in ["init", "frame", "event"] {
            if !program.defines(name) {
                return Err(Fault::Missing(name));
            }
        }
        let state: Value = program.call("init", (), &mut ())?;
        Ok(Self { program, state })
    }

    #[must_use]
    pub fn state(&self) -> &Value {
        &self.state
    }

    pub fn frame(&mut self, input: Input) -> Result<Frame, Fault> {
        let arg = map(&[
            ("t", Value::Float(input.t)),
            ("width", Value::Float(input.width)),
            ("height", Value::Float(input.height)),
        ]);
        let out: Value = self
            .program
            .call("frame", (self.state.clone(), arg), &mut ())?;
        let Value::Map(m) = &out else {
            return Err(Fault::Shape(format!("{out}")));
        };
        let (Some(state), Some(commands)) = (m.get(&key("state")), m.get(&key("draw"))) else {
            return Err(Fault::Shape(format!("{out}")));
        };
        self.state = state.clone();
        Ok(draw::decode(commands))
    }

    pub fn event(&mut self, event: Event) -> Result<(), Fault> {
        let arg = match event {
            Event::Touch { phase, x, y } => map(&[
                ("kind", Value::Keyword(Arc::from("touch"))),
                ("phase", Value::Keyword(Arc::from(phase.keyword()))),
                ("x", Value::Float(x)),
                ("y", Value::Float(y)),
            ]),
        };
        self.state = self
            .program
            .call("event", (self.state.clone(), arg), &mut ())?;
        Ok(())
    }
}

fn key(name: &str) -> MapKey {
    MapKey::Keyword(Arc::from(name))
}

fn map(entries: &[(&str, Value)]) -> Value {
    let mut m = Map::new();
    for (k, v) in entries {
        m.insert(key(k), v.clone());
    }
    Value::Map(Arc::new(m))
}
