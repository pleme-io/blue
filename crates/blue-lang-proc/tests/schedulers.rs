mod support;

use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use tatara_lisp_eval::{Arity, Value};

use blue_lang_proc::{ClockKind, NodeConfig};
use support::{configure, show};

const WORKERS: &str = "\
def burn(i, acc, n)
  if i == n
    acc
  else
    burn(i + 1, (acc + i * i) % 1000003, n)
  end
end
def work(root, k)
  send(root, [k, burn(0, k, 400000)])
end
";

fn gathered(schedulers: usize) -> (String, Duration) {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.schedulers = schedulers;
    let (mut root, _node) = configure(config);
    let t = Instant::now();
    let out = show(
        &mut root,
        &format!(
            "{WORKERS}me = self()\nfor_each = map((k) -> spawn(work, [me, k]), [1, 2, 3, 4])\nmap((k) -> receive([k, :_]), [1, 2, 3, 4])"
        ),
    );
    (out, t.elapsed())
}

#[test]
fn processes_give_the_same_answers_on_one_scheduler_and_on_four() {
    let (one, _) = gathered(1);
    let (four, _) = gathered(4);
    assert_eq!(
        one, four,
        "A-parity: the answers do not depend on how many schedulers ran them"
    );
    assert!(one.contains("(1 "), "{one}");
}

#[test]
fn four_processes_on_four_schedulers_meet_at_a_barrier_only_running_at_once_can_pass() {
    let met: Arc<(Mutex<usize>, Condvar)> = Arc::new((Mutex::new(0), Condvar::new()));
    let child = {
        let met = met.clone();
        Arc::new(move || {
            let mut i = blue_lang_runtime::interpreter_hostless();
            let met = met.clone();
            i.register_fn(
                "meet",
                Arity::Exact(0),
                move |_: &[Value], _: &mut (), _| {
                    let (count, arrived) = &*met;
                    let mut n = count.lock().expect("barrier");
                    *n += 1;
                    arrived.notify_all();
                    let (n, waited) = arrived
                        .wait_timeout_while(n, Duration::from_secs(60), |n| *n < 4)
                        .expect("barrier");
                    Ok(Value::Bool(!waited.timed_out() && *n >= 4))
                },
            );
            i
        })
    };
    let mut config = NodeConfig::new(child);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.schedulers = 4;
    let (mut root, _node) = configure(config);
    let out = show(
        &mut root,
        "def wait(root, k)\n  send(root, [k, meet()])\nend\nme = self()\nmap((k) -> spawn(wait, [me, k]), [1, 2, 3, 4])\nmap((k) -> receive([k, :_]), [1, 2, 3, 4])",
    );
    assert_eq!(
        out, "((1 #t) (2 #t) (3 #t) (4 #t))",
        "each process waits at the barrier until all four arrive, which only four slices running at once can do"
    );
}
