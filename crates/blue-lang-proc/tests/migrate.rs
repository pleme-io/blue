//! `defmigrate`: new code into running processes, without losing a message.

mod support;

use support::{node, show};

const COUNTERS: &str = "\
def counter(msg, n)
  if msg == :inc
    n + 1
  else
    send(nth(1, msg), [:v1, n])
    n
  end
end
def counter_v2(msg, n)
  if msg == :inc
    n + 10
  else
    send(nth(1, msg), [:v2, n])
    n
  end
end
me = self()
";

#[test]
fn a_message_queued_during_the_swap_is_kept_and_handled_by_the_new_code() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        &format!(
            "{COUNTERS}\
             s = spawn_server(counter, 0)\n\
             send(s, :inc)\nsend(s, :inc)\n\
             send(s, [:get, me])\nbefore = receive()\n\
             send(s, :inc)\n\
             swapped = defmigrate(counter, counter_v2, fn(n) n * 100 end)\n\
             send(s, [:get, me])\n\
             [before, swapped, receive()]"
        ),
    );
    // 2 under v1; the queued :inc waits out the swap, so it meets the new
    // code and the migrated state: 2 * 100 + 10.
    assert_eq!(out, "((:v1 2) ((1 :ok)) (:v2 210))");
}

#[test]
fn a_migration_that_raises_leaves_the_old_code_and_state_running() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        &format!(
            "{COUNTERS}\
             s = spawn_server(counter, 5)\n\
             r = defmigrate(s, counter_v2, fn(n) throw(error(:refused, \"no migration today\")) end)\n\
             send(s, :inc)\nsend(s, [:get, me])\n\
             [r, receive()]"
        ),
    );
    assert!(
        out.contains("(1 (:error") && out.contains("no migration today"),
        "{out}"
    );
    assert!(
        out.ends_with("(:v1 6))"),
        "old code, old state, the message handled: {out}"
    );
}

#[test]
fn migrating_a_definition_reaches_every_process_running_it_and_no_other() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        &format!(
            "{COUNTERS}\
             def other(msg, n)\n  send(nth(1, msg), [:other, n])\n  n\nend\n\
             a = spawn_server(counter, 1)\nb = spawn_server(counter, 2)\nc = spawn_server(other, 3)\n\
             r = defmigrate(counter, counter_v2)\n\
             map(fn(p) send(p, [:get, me]) end, [a, b, c])\n\
             [r, receive([:_, 1]), receive([:_, 2]), receive([:_, 3])]"
        ),
    );
    assert_eq!(out, "(((1 :ok) (2 :ok)) (:v2 1) (:v2 2) (:other 3))");
}

#[test]
fn a_plain_process_picks_up_new_code_at_its_next_call_by_name() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "def serve(parent, n)\n  receive()\n  send(parent, [:old, n])\n  serve(parent, n + 1)\nend\n\
         def serve_v2(parent, n)\n  receive()\n  send(parent, [:new, n])\n  serve_v2(parent, n + 1)\nend\n\
         me = self()\np = spawn(serve, [me, 0])\n\
         send(p, :tick)\nfirst = receive()\n\
         r = defmigrate(serve, serve_v2)\n\
         send(p, :tick)\nsend(p, :tick)\n\
         [first, r, receive(), receive()]",
    );
    // The process was parked inside the old body; it finishes that call in
    // the old code and every later call by name runs the new one.
    assert_eq!(out, "((:old 0) ((1 :ok)) (:old 1) (:new 2))");
}

#[test]
fn a_plain_process_refuses_a_state_transform() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "def loop(n)\n  receive()\n  loop(n)\nend\np = spawn(loop, [0])\n\
         defmigrate(p, loop, fn(s) s end)",
    );
    assert!(out.contains("spawn_server to migrate state"), "{out}");
}

#[test]
fn a_restart_after_a_migration_runs_the_new_code_from_the_migrated_initial_state() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        &format!(
            "{COUNTERS}\
             def crashy(msg, n)\n  if msg == :die\n    throw(error(:asked, \"x\"))\n  end\n  counter_v2(msg, n)\nend\n\
             sup = supervisor(:one_for_one, [[:server, counter, 1]], 3)\n\
             s = nth(0, children(sup))\n\
             r = defmigrate(s, crashy, fn(n) n + 1000 end)\n\
             send(s, :inc)\n\
             send(s, :die)\n\
             receive(:none, 50)\n\
             send(s, [:get, me])\n\
             [r, receive()]"
        ),
    );
    // The :inc that ran before the crash is gone with that incarnation; the
    // restart starts from the migrated initial state under the new code.
    assert_eq!(out, "(((2 :ok)) (:v2 1001))");
}
