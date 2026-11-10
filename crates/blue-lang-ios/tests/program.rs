use blue_lang_ios::draw::{Colour, Draw, FLOATS_PER_VERTEX};
use blue_lang_ios::program::{App, Event, Fault, Input, Phase};

const EXAMPLE: &str = include_str!("../example/app.b");

fn input() -> Input {
    Input {
        t: 0.0,
        width: 400.0,
        height: 800.0,
    }
}

#[test]
fn the_example_clears_and_draws_the_rectangle_it_chose() {
    let mut app = App::load(EXAMPLE).expect("the example loads");
    let frame = app.frame(input()).expect("a frame");
    assert!(frame.refused.is_empty(), "{:?}", frame.refused);
    assert_eq!(
        frame.draws,
        [
            Draw::Clear(Colour {
                r: 0.1,
                g: 0.2,
                b: 0.4,
                a: 1.0
            }),
            Draw::Rect {
                x: 100.0,
                y: 200.0,
                w: 200.0,
                h: 200.0,
                colour: Colour {
                    r: 1.0,
                    g: 0.5,
                    b: 0.0,
                    a: 1.0
                }
            }
        ]
    );
}

#[test]
fn an_event_threads_the_state_into_the_next_frame() {
    let mut app = App::load(EXAMPLE).expect("the example loads");
    app.event(Event::Touch {
        phase: Phase::Ended,
        x: 1.0,
        y: 1.0,
    })
    .expect("event");
    assert_eq!(app.state().to_string(), "{:taps 1}");
}

#[test]
fn a_program_without_frame_is_refused_by_name() {
    let err = App::load("def init()\n  1\nend\n\ndef event(s, e)\n  s\nend\n")
        .err()
        .expect("refused");
    assert!(matches!(err, Fault::Missing("frame")), "{err}");
}

#[test]
fn a_bad_draw_command_is_refused_alone_and_its_siblings_draw() {
    let src = include_str!("fixtures/refused.b");
    let mut app = App::load(src).expect("loads");
    let frame = app.frame(input()).expect("a frame");
    assert_eq!(frame.draws.len(), 1);
    assert_eq!(frame.refused.len(), 2, "{:?}", frame.refused);
    assert!(frame.refused[0].contains("circle"));
    assert!(frame.refused[1].contains("outside 0..1"));
}

#[test]
fn a_later_clear_hides_the_rectangles_before_it() {
    let src = include_str!("fixtures/later_clear.b");
    let mut app = App::load(src).expect("loads");
    let frame = app.frame(input()).expect("a frame");
    assert_eq!(frame.clear_colour().b, 1.0);
    let rects: Vec<_> = frame.visible_rects().collect();
    assert_eq!(rects.len(), 1);
    assert_eq!(rects[0].2, 20.0);
}

#[test]
fn a_rectangle_becomes_two_triangles_in_clip_space() {
    let mut app = App::load(EXAMPLE).expect("the example loads");
    let frame = app.frame(input()).expect("a frame");
    let v = blue_lang_ios::draw::vertices(&frame, 400.0, 800.0);
    assert_eq!(v.len(), 6 * FLOATS_PER_VERTEX);
    assert_eq!(&v[..2], &[-0.5, 0.5]);
    assert_eq!(
        &v[5 * FLOATS_PER_VERTEX..5 * FLOATS_PER_VERTEX + 2],
        &[0.5, 0.0]
    );
    assert_eq!(&v[4..8], &[1.0, 0.5, 0.0, 1.0]);
}
