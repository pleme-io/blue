mod support;

use std::sync::Arc;
use std::time::{Duration, Instant};

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
fn processes_give_the_same_answers_on_one_scheduler_and_on_four_and_four_run_at_once() {
    let (one, alone) = gathered(1);
    let (four, together) = gathered(4);
    assert_eq!(
        one, four,
        "A-parity: the answers do not depend on how many schedulers ran them"
    );
    assert!(one.contains("(1 "), "{one}");
    let cores = std::thread::available_parallelism().map_or(1, usize::from);
    if cores >= 4 {
        assert!(
            together.as_secs_f64() < alone.as_secs_f64() * 0.7,
            "four processes on four schedulers run at once: {together:?} against {alone:?} on one"
        );
    }
}
