use std::path::PathBuf;
use std::process::{Command, Output};
use std::time::{Duration, Instant};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_MEMO")
        .env_remove("BLUE_WITNESS");
    c
}

fn dir(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("blue-virtual-clock-{name}"));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).expect("scratch dir");
    p
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

const TIMED: &str = r#"test "a ten minute sleep observes ten minutes"
  t0 = node_time
  sleep_for(600_000)
  assert node_time - t0 == 600_000
end

test "a thirty second timeout raises timeout at thirty seconds"
  t0 = node_time
  kind = begin
    timeout(30000, () -> receive([:never]))
  rescue :timeout as e
    e.kind
  end
  assert kind == :timeout
  assert node_time - t0 == 30000
end

test "timers fire in the order of their deadlines"
  after(300, :late)
  after(100, :early)
  assert [receive(), receive()] == %i[early late]
end

test "the clock in a test is virtual"
  assert context[:clock] == :virtual
end
"#;

#[test]
fn blue_test_runs_timed_tests_on_the_virtual_clock_in_well_under_a_second_of_waiting() {
    let d = dir("test");
    let f = d.join("timed_test.b");
    std::fs::write(&f, TIMED).expect("write");
    let started = Instant::now();
    let o = blue()
        .args(["test", f.to_str().unwrap()])
        .output()
        .expect("spawn blue");
    let wall = started.elapsed();
    assert!(o.status.success(), "{}", text(&o));
    assert!(text(&o).contains("4 passed"), "{}", text(&o));
    assert!(wall < Duration::from_secs(20), "took {wall:?}");
}

#[test]
fn blue_run_keeps_the_wall_clock() {
    let d = dir("run");
    let f = d.join("wall.b");
    std::fs::write(
        &f,
        "sleep_for(80)\nprintln([context[:clock], node_time >= 80])\n",
    )
    .expect("write");
    let started = Instant::now();
    let o = blue()
        .args(["run", f.to_str().unwrap()])
        .output()
        .expect("spawn blue");
    assert!(o.status.success(), "{}", text(&o));
    assert!(started.elapsed() >= Duration::from_millis(80));
    assert!(String::from_utf8_lossy(&o.stdout).starts_with("(:real #t)\n"));
}
