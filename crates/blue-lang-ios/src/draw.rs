use std::sync::Arc;

use blue_lang_host::{MapKey, Value};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Colour {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Draw {
    Clear(Colour),
    Rect {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        colour: Colour,
    },
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Frame {
    pub draws: Vec<Draw>,
    pub refused: Vec<String>,
}

impl Frame {
    #[must_use]
    pub fn clear_colour(&self) -> Colour {
        self.draws
            .iter()
            .rev()
            .find_map(|d| match d {
                Draw::Clear(c) => Some(*c),
                Draw::Rect { .. } => None,
            })
            .unwrap_or(Colour {
                r: 0.0,
                g: 0.0,
                b: 0.0,
                a: 1.0,
            })
    }

    pub fn visible_rects(&self) -> impl Iterator<Item = (f32, f32, f32, f32, Colour)> + '_ {
        let start = self
            .draws
            .iter()
            .rposition(|d| matches!(d, Draw::Clear(_)))
            .map_or(0, |i| i + 1);
        self.draws[start..].iter().filter_map(|d| match *d {
            Draw::Rect { x, y, w, h, colour } => Some((x, y, w, h, colour)),
            Draw::Clear(_) => None,
        })
    }
}

pub const FLOATS_PER_VERTEX: usize = 8;

#[must_use]
pub fn vertices(frame: &Frame, width: f32, height: f32) -> Vec<f32> {
    let mut out = Vec::new();
    if width <= 0.0 || height <= 0.0 {
        return out;
    }
    let nx = |x: f32| x / width * 2.0 - 1.0;
    let ny = |y: f32| 1.0 - y / height * 2.0;
    for (x, y, w, h, c) in frame.visible_rects() {
        let (l, r, t, b) = (nx(x), nx(x + w), ny(y), ny(y + h));
        for (px, py) in [(l, t), (r, t), (l, b), (l, b), (r, t), (r, b)] {
            out.extend_from_slice(&[px, py, 0.0, 0.0, c.r, c.g, c.b, c.a]);
        }
    }
    out
}

#[must_use]
pub fn decode(commands: &Value) -> Frame {
    let mut frame = Frame::default();
    let Value::List(items) = commands else {
        frame
            .refused
            .push(format!("draw is {commands}, not a list"));
        return frame;
    };
    for (i, item) in items.iter().enumerate() {
        match command(item) {
            Ok(d) => frame.draws.push(d),
            Err(why) => frame.refused.push(format!("draw[{i}]: {why}")),
        }
    }
    frame
}

fn command(item: &Value) -> Result<Draw, String> {
    let Value::Map(m) = item else {
        return Err(format!("{item} is not a map"));
    };
    let field = |name: &str| {
        m.get(&MapKey::Keyword(Arc::from(name)))
            .ok_or_else(|| format!("{item} has no {name}"))
    };
    match field("op")? {
        Value::Keyword(op) if &**op == "clear" => Ok(Draw::Clear(colour(field("colour")?)?)),
        Value::Keyword(op) if &**op == "rect" => Ok(Draw::Rect {
            x: number(field("x")?)?,
            y: number(field("y")?)?,
            w: number(field("w")?)?,
            h: number(field("h")?)?,
            colour: colour(field("colour")?)?,
        }),
        other => Err(format!("op {other} is not :clear or :rect")),
    }
}

fn number(v: &Value) -> Result<f32, String> {
    match v {
        Value::Int(n) => Ok(*n as f32),
        Value::Float(f) => Ok(*f as f32),
        other => Err(format!("{other} is not a number")),
    }
}

fn colour(v: &Value) -> Result<Colour, String> {
    let Value::List(parts) = v else {
        return Err(format!("colour {v} is not a list"));
    };
    let n: Vec<f32> = parts.iter().map(number).collect::<Result<_, _>>()?;
    if n.iter().any(|c| !(0.0..=1.0).contains(c)) {
        return Err(format!("colour {v} has a part outside 0..1"));
    }
    match n[..] {
        [r, g, b] => Ok(Colour { r, g, b, a: 1.0 }),
        [r, g, b, a] => Ok(Colour { r, g, b, a }),
        _ => Err(format!("colour {v} needs 3 or 4 parts")),
    }
}
