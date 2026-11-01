use std::sync::{Arc, Mutex, PoisonError};

use blue_lang_senses::canvas::{self, Canvas};
use blue_lang_senses::display::Screen;
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind;
use crate::provide::Key;

type Span = tatara_lisp::Span;

#[derive(Clone, Copy)]
enum Surface {
    Host,
    Framebuffer,
}

struct Open {
    canvas: Canvas,
    screen: Option<Screen>,
}

struct Handle(Mutex<Option<Open>>);

fn bad_option(word: &'static str, message: String, span: Span) -> EvalError {
    raise_kind("bad_option", format!("{word}: {message}"), span)
}

fn int(v: &Value, what: &str, word: &'static str, span: Span) -> Result<i64, EvalError> {
    match v {
        Value::Int(n) => Ok(*n),
        other => Err(bad_option(
            word,
            format!("{what} is an integer, got {}", other.type_name()),
            span,
        )),
    }
}

fn color(v: &Value, word: &'static str, span: Span) -> Result<u32, EvalError> {
    match v {
        Value::Str(s) => canvas::color(s).map_err(|e| bad_option(word, e, span)),
        other => Err(bad_option(
            word,
            format!(
                "a color is a string like \"#ff8800\", got {}",
                other.type_name()
            ),
            span,
        )),
    }
}

fn field<'a>(v: &'a Value, name: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(&MapKey::Keyword(Arc::from(name))),
        _ => None,
    }
}

fn handle(v: &Value, word: &'static str, span: Span) -> Result<Arc<Handle>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(h) = Arc::downcast::<Handle>(any.clone()) {
            return Ok(h);
        }
    }
    Err(bad_option(
        word,
        format!("expected a canvas from canvas_open, got {}", v.type_name()),
        span,
    ))
}

fn with_open<T>(
    v: &Value,
    word: &'static str,
    span: Span,
    f: impl FnOnce(&mut Open) -> Result<T, EvalError>,
) -> Result<T, EvalError> {
    let h = handle(v, word, span)?;
    let mut guard = h.0.lock().unwrap_or_else(PoisonError::into_inner);
    let open = guard
        .as_mut()
        .ok_or_else(|| raise_kind("closed", format!("{word}: this canvas is closed"), span))?;
    f(open)
}

fn open_canvas(surface: Surface, opts: &Value, span: Span) -> Result<Value, EvalError> {
    const W: &str = "canvas_open";
    if !matches!(opts, Value::Map(_)) {
        return Err(bad_option(
            W,
            format!(
                "opts is a map with width: and height:, got {}",
                opts.type_name()
            ),
            span,
        ));
    }
    let side = |name: &str| match field(opts, name) {
        Some(v) => int(v, name, W, span),
        None => Err(bad_option(W, format!("opts needs {name}:"), span)),
    };
    let canvas =
        Canvas::new(side("width")?, side("height")?).map_err(|e| bad_option(W, e, span))?;
    let title = match field(opts, "title") {
        None => "blue".to_string(),
        Some(Value::Str(s)) => s.to_string(),
        Some(other) => {
            return Err(bad_option(
                W,
                format!("title: is a string, got {}", other.type_name()),
                span,
            ))
        }
    };
    let screen = match surface {
        Surface::Host => Some(
            Screen::open(&canvas, &title)
                .map_err(|r| raise_kind(r.kind(), format!("{W}: {}", r.message()), span))?,
        ),
        Surface::Framebuffer => None,
    };
    Ok(Value::Foreign(Arc::new(Handle(Mutex::new(Some(Open {
        canvas,
        screen,
    }))))))
}

fn install<H: 'static>(interp: &mut Interpreter<H>, key: Key, surface: Surface) {
    interp.register_fn(
        key("canvas_open"),
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| open_canvas(surface, &a[0], span),
    );
    interp.register_fn(
        key("canvas_clear"),
        Arity::Exact(2),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "canvas_clear";
            let rgb = color(&a[1], W, span)?;
            with_open(&a[0], W, span, |o| {
                o.canvas.clear(rgb);
                Ok(Value::Nil)
            })
        },
    );
    interp.register_fn(
        key("canvas_fill_rect"),
        Arity::Exact(6),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "canvas_fill_rect";
            let x = int(&a[1], "x", W, span)?;
            let y = int(&a[2], "y", W, span)?;
            let w = int(&a[3], "width", W, span)?;
            let h = int(&a[4], "height", W, span)?;
            let rgb = color(&a[5], W, span)?;
            with_open(&a[0], W, span, |o| {
                o.canvas.fill_rect(x, y, w, h, rgb);
                Ok(Value::Nil)
            })
        },
    );
    interp.register_fn(
        key("canvas_text"),
        Arity::Exact(5),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "canvas_text";
            let x = int(&a[1], "x", W, span)?;
            let y = int(&a[2], "y", W, span)?;
            let text = match &a[3] {
                Value::Str(s) => s.clone(),
                other => {
                    return Err(bad_option(
                        W,
                        format!("text is a string, got {}", other.type_name()),
                        span,
                    ))
                }
            };
            let rgb = color(&a[4], W, span)?;
            with_open(&a[0], W, span, |o| {
                o.canvas.text(x, y, &text, rgb);
                Ok(Value::Nil)
            })
        },
    );
    interp.register_fn(
        key("canvas_present"),
        Arity::Exact(1),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "canvas_present";
            with_open(&a[0], W, span, |o| {
                o.canvas.present();
                if let Some(screen) = o.screen.as_mut() {
                    screen
                        .present(&o.canvas)
                        .map_err(|r| raise_kind(r.kind(), format!("{W}: {}", r.message()), span))?;
                }
                Ok(Value::Nil)
            })
        },
    );
    interp.register_fn(
        key("canvas_pixel"),
        Arity::Exact(3),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "canvas_pixel";
            let x = int(&a[1], "x", W, span)?;
            let y = int(&a[2], "y", W, span)?;
            with_open(&a[0], W, span, |o| {
                Ok(o.canvas
                    .pixel(x, y)
                    .map_or(Value::Nil, |p| Value::Str(Arc::from(canvas::hex(p)))))
            })
        },
    );
    interp.register_fn(
        key("canvas_close"),
        Arity::Exact(1),
        |a: &[Value], _: &mut H, span| {
            let h = handle(&a[0], "canvas_close", span)?;
            let open = h.0.lock().unwrap_or_else(PoisonError::into_inner).take();
            if let Some(screen) = open.and_then(|o| o.screen) {
                let _ = screen.close();
            }
            Ok(Value::Nil)
        },
    );
}

pub fn install_display<H: 'static>(interp: &mut Interpreter<H>) {
    install(interp, String::from, Surface::Host);
}

pub fn provide_framebuffer<H: 'static>(interp: &mut Interpreter<H>, key: Key) {
    install(interp, key, Surface::Framebuffer);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn framebuffer() -> Interpreter<()> {
        let mut interp = crate::interpreter_hostless();
        provide_framebuffer(&mut interp, String::from);
        interp
    }

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

    #[test]
    fn the_framebuffer_shows_what_was_drawn_once_it_is_presented() {
        let mut i = framebuffer();
        ok(
            &mut i,
            "(define c (canvas_open (hash-map :width 16 :height 8 :title \"t\")))",
        );
        ok(&mut i, "(canvas_clear c \"#102030\")");
        ok(&mut i, "(canvas_fill_rect c 1 1 2 2 \"#f00\")");
        ok(&mut i, "(canvas_text c 8 0 \"A\" \"#ffffff\")");
        assert_eq!(ok(&mut i, "(canvas_pixel c 1 1)"), "\"#000000\"");
        ok(&mut i, "(canvas_present c)");
        assert_eq!(ok(&mut i, "(canvas_pixel c 0 0)"), "\"#102030\"");
        assert_eq!(ok(&mut i, "(canvas_pixel c 2 2)"), "\"#ff0000\"");
        assert_eq!(ok(&mut i, "(canvas_pixel c 3 3)"), "\"#102030\"");
        assert_eq!(ok(&mut i, "(canvas_pixel c 10 0)"), "\"#ffffff\"");
        assert_eq!(ok(&mut i, "(canvas_pixel c 16 0)"), "()");
        assert_eq!(ok(&mut i, "(canvas_close c)"), "()");
        assert_eq!(
            ok(&mut i, "(canvas_close c)"),
            "()",
            "closing twice is done"
        );
        assert_eq!(kind(&mut i, "(canvas_pixel c 0 0)"), "closed");
    }

    #[test]
    fn a_bad_size_color_or_handle_is_refused() {
        let mut i = framebuffer();
        for bad in [
            "(canvas_open (hash-map :width 0 :height 8))",
            "(canvas_open (hash-map :width 8))",
            "(canvas_open 8)",
            "(canvas_open (hash-map :width 8 :height 8 :title 3))",
            "(canvas_clear 1 \"#000\")",
        ] {
            assert_eq!(kind(&mut i, bad), "bad_option", "{bad}");
        }
        ok(
            &mut i,
            "(define c (canvas_open (hash-map :width 2 :height 2)))",
        );
        assert_eq!(kind(&mut i, "(canvas_clear c \"red\")"), "bad_option");
        assert_eq!(
            kind(&mut i, "(canvas_fill_rect c 0 0 1 1.5 \"#000\")"),
            "bad_option"
        );
    }
}
