//! Processes from the evaluation session: they persist between requests, and
//! a process a session spawns is held to the session's frame.

use blue_lang_runtime::session::{Config, Session};
use blue_lang_runtime::uses::NoLoader;

fn eval(s: &mut Session, code: &str) -> String {
    match s.eval(code, None, None).result {
        Ok(v) => v,
        Err(stop) => format!("stop: {stop:?}"),
    }
}

#[test]
fn a_process_spawned_in_one_request_answers_the_next() {
    let mut s = Session::new(Config::new(Box::new(NoLoader)));
    eval(
        &mut s,
        "def echo(parent)\n  send(parent, [:echo, receive()])\n  echo(parent)\nend\n",
    );
    eval(&mut s, "e = spawn(echo, [self])");
    eval(&mut s, "send(e, 1)");
    assert_eq!(eval(&mut s, "receive()"), "[:echo, 1]");
    eval(&mut s, "send(e, 2)");
    assert_eq!(eval(&mut s, "receive()"), "[:echo, 2]");
}

/// Needs the host layer to have something to refuse; `cargo test --workspace`
/// turns it on through the CLI.
#[cfg(feature = "sys")]
#[test]
fn a_child_is_held_to_the_session_frame() {
    let mut s = Session::new(Config::new(Box::new(NoLoader)));
    let out = eval(
        &mut s,
        "spawn_link(fn() read_file(\"/etc/hosts\") end)\nreceive()",
    );
    assert!(
        out.contains("linked process") && out.contains("does not grant"),
        "a hostless session's child must not read the host: {out}"
    );
}
