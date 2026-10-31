use std::net::UdpSocket;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::Duration;

use serde_json::Value as Json;

const KENSA_FIXTURE: &str = "aeba24d3e400593ba655d7b104a5edec5433cb919527111ffab8acab4620d21e";
const SCHEMA: &str = "kensa-immunity.v1";

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_CRASH_JOURNAL")
        .env(
            "BLUE_PATH",
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bidamas"),
        );
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-wire-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn put(path: &Path, text: &str) {
    std::fs::write(path, text).expect("write fixture");
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn project(name: &str, bluefile: &str, files: &[(&str, &str)]) -> PathBuf {
    let dir = scratch(name);
    put(&dir.join("Bluefile"), bluefile);
    for (file, text) in files {
        put(&dir.join(file), text);
    }
    let o = blue().arg("lock").arg(&dir).output().expect("blue lock");
    assert!(o.status.success(), "blue lock {name}: {}", err(&o));
    dir
}

fn run(dir: &Path, file: &str) -> Json {
    let o = blue()
        .args(["run", "--quiet"])
        .arg(dir.join(file))
        .output()
        .expect("blue run");
    assert!(
        o.status.success(),
        "blue run {file}: {}{}",
        out(&o),
        err(&o)
    );
    serde_json::from_str(out(&o).trim()).unwrap_or_else(|e| panic!("{e}: {}", out(&o)))
}

const PACED: &str = "package(\"wire-paced\", \"0.1.0\")\nallow(%i[comm_flash comm_scavenger])\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 0, step_ms: 0})\nvirtualize(:filesystem, {using: :null_sink, for: %w[kodou]})\nvirtualize(:entropy, {using: :seeded_prng, seed: \"wire\", for: %w[shomei]})\n";

const FLASH: &str = r#"use("kodou", %i[address emit link])
use("retsu", %i[first last push])

def payload(i)
  join(map((_k) -> "x", range(i * 397 % 1280)), "")
end

def main()
  a = link("127.0.0.1:0", {channels: [:flash]})
  b = link("127.0.0.1:0", {channels: [:flash]})
  peer = address(b)
  sends = reduce(
    fn(acc, i)
      l = emit(first(acc), peer, payload(i))
      got = flash_next(b.wire, 2000)
      [l, push(last(acc), [l.sent.at_ms, l.sent.bytes, got.bytes])]
    end,
    [a, []],
    range(40)
  )
  big = join(map((_k) -> "x", range(1280)), "")
  bucket = begin
    emit(a, peer, big)
    "sent"
  rescue _
    "refused"
  end
  host = begin
    flash_put(a.wire, peer, big)
    "sent"
  rescue _
    "refused"
  end
  write_stdout(
    json_stringify(
      {
        sends: last(sends),
        bucket:,
        host:,
        sent: flash_stats(a.wire).sent,
        received: flash_stats(b.wire).received,
        refused: flash_stats(a.wire).refused
      }
    )
  )
end
"#;

const TIDE: &str = r#"use("ibuki", %i[floor_window queuing])
use("kodou", %i[address link pump queue take])
use("retsu", %i[push])

def stocked(l, peer, chunk)
  short = blue::max(0, 24 - tide_stats(l.wire).queued)
  reduce((acc, _i) -> queue(acc, peer, chunk), l, range(short))
end

def drained(l, refill)
  reduce(
    fn(acc, _i)
      if acc.idle
        acc
      else
        t = take(acc.link, 50)
        moved = if refill
          pump(t.link)
        else
          t.link
        end
        {link: moved, idle: t.idle}
      end
    end,
    {link: l, idle: false},
    range(400)
  ).link
end

def round(acc, d, peer, chunk)
  a = pump(stocked(acc.a, peer, chunk))
  sleep_ms(d)
  b = drained(acc.b, false)
  moved = drained(a, true)
  {
    a: moved,
    b:,
    rows: push(acc.rows, [d, moved.tide.cwnd, queuing(moved.tide)])
  }
end

def main()
  a = link("127.0.0.1:0", {channels: [:tide]})
  b = link("127.0.0.1:0", {channels: [:tide]})
  chunk = join(map((_k) -> "x", range(1000)), "")
  plan = [5, 5, 5, 5, 5, 6, 6, 6, 7, 7, 7, 5, 5, 5, 5]
  done = reduce(
    (acc, d) -> round(acc, d, address(b), chunk),
    {a:, b:, rows: []},
    plan
  )
  write_stdout(json_stringify({floor: floor_window(a.tide), rows: done.rows}))
end
"#;

fn rows(j: &Json, key: &str) -> Vec<Vec<i64>> {
    j[key]
        .as_array()
        .unwrap_or_else(|| panic!("no {key}: {j}"))
        .iter()
        .map(|r| {
            r.as_array()
                .expect("row")
                .iter()
                .map(|v| v.as_i64().expect("int"))
                .collect()
        })
        .collect()
}

#[test]
fn flash_never_exceeds_its_rate_or_its_mtu_and_repeats_under_a_stepped_clock() {
    let dir = project("flash", PACED, &[("flash.b", FLASH)]);
    let j = run(&dir, "flash.b");
    let sends = rows(&j, "sends");
    assert_eq!(sends.len(), 40, "{j}");
    for s in &sends {
        assert!(s[1] <= 1280, "a datagram past the MTU: {s:?}");
        assert_eq!(s[1], s[2], "the frame arrives whole: {s:?}");
    }
    for i in 0..sends.len() {
        for k in i..sends.len() {
            let bytes: i64 = sends[i..=k].iter().map(|s| s[1]).sum();
            let allowed = 16_384_000 + 16_384 * (sends[k][0] - sends[i][0]);
            assert!(
                bytes * 1000 <= allowed,
                "sends {i}..={k} spent {bytes} bytes in {} ms",
                sends[k][0] - sends[i][0]
            );
        }
    }
    let total: i64 = sends.iter().map(|s| s[1]).sum();
    assert!(total > 16_384, "the run spends past one burst: {total}");
    assert!(
        sends.last().expect("a send")[0] > 0,
        "past the burst the stepped clock had to advance: {sends:?}"
    );
    assert_eq!(j["bucket"], "refused", "{j}");
    assert_eq!(j["host"], "refused", "{j}");
    assert_eq!(j["sent"], 40, "a refused frame is not sent: {j}");
    assert_eq!(j["received"], 40, "{j}");
    assert_eq!(
        j["refused"], 0,
        "kodou's pacing never meets the host's rate refusal: {j}"
    );
    assert_eq!(run(&dir, "flash.b"), j, "a stepped clock repeats the run");
    let _ = std::fs::remove_dir_all(dir);
}

const RATED: &str = "package(\"wire-rated\", \"0.1.0\")\nallow(%i[comm_flash])\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 0, step_ms: 0})\n";

const AGREED: &str = "package(\"wire-agreed\", \"0.1.0\")\nallow(%i[comm_flash])\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 0, step_ms: 0})\nvirtualize(:entropy, {using: :seeded_prng, seed: \"wire\", for: %w[shomei]})\n";

fn bursting(port: u16) -> String {
    format!(
        r#"def attempt(w, peer, big)
  flash_put(w, peer, big)
  "sent"
rescue :rate_limited as e
  "refused #{{to_s(e.data.wait_ms)}}"
end

def main()
  w = flash_open("127.0.0.1:0")
  peer = "127.0.0.1:{port}"
  big = join(map((_i) -> "x", range(1279)), "")
  burst = map((_i) -> attempt(w, peer, big), range(13))
  sleep_ms(15)
  early = attempt(w, peer, big)
  sleep_ms(1)
  late = attempt(w, peer, big)
  write_stdout(
    json_stringify(
      {{
        burst:,
        early:,
        late:,
        sent: flash_stats(w).sent,
        refused: flash_stats(w).refused,
        rate: flash_stats(w).rate
      }}
    )
  )
end
"#
    )
}

#[test]
fn a_direct_flash_put_burst_past_the_rate_is_refused_by_the_host_and_the_refusal_is_catchable() {
    let (l, port) = listener();
    let dir = project("rated", RATED, &[("burst.b", &bursting(port))]);
    let j = run(&dir, "burst.b");
    let burst: Vec<&str> = j["burst"]
        .as_array()
        .unwrap_or_else(|| panic!("{j}"))
        .iter()
        .map(|v| v.as_str().expect("text"))
        .collect();
    assert_eq!(&burst[..12], &["sent"; 12], "{j}");
    assert_eq!(
        burst[12], "refused 16",
        "the thirteenth full frame waits 16 ms: {j}"
    );
    assert_eq!(j["early"], "refused 1", "{j}");
    assert_eq!(
        j["late"], "sent",
        "the frame's stepped clock refills the host's bucket: {j}"
    );
    assert_eq!(
        (j["sent"].as_i64(), j["refused"].as_i64()),
        (Some(13), Some(2)),
        "{j}"
    );
    assert_eq!(j["rate"], 16_384, "{j}");
    assert_eq!(
        heard(&l).len(),
        13,
        "a refused frame never reaches the socket"
    );

    let config = dir.join("blue.yaml");
    put(&config, "flash_bytes_per_second: 2560\n");
    let o = blue()
        .env("BLUE_CONFIG", &config)
        .args(["run", "--quiet"])
        .arg(dir.join("burst.b"))
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    let bounded: Json = serde_json::from_str(out(&o).trim()).expect("json");
    assert_eq!(
        bounded["rate"], 2560,
        "the bound is BlueConfig's: {bounded}"
    );
    assert_eq!(bounded["burst"][1], "sent", "{bounded}");
    assert_eq!(bounded["burst"][2], "refused 500", "{bounded}");
    assert_eq!(bounded["sent"], 2, "{bounded}");
    let _ = std::fs::remove_dir_all(dir);
}

fn agreeing(schedule: &[(u64, u64)]) -> String {
    let rows: Vec<String> = schedule
        .iter()
        .map(|(bytes, advance)| format!("[{bytes}, {advance}]"))
        .collect();
    format!(
        r##"use("ibuki", %i[flash flash_send])
use("retsu", [:push])

def step(acc, s)
  sleep_ms(nth(1, s))
  bytes = nth(0, s)
  r = flash_send(acc.bucket, bytes, now_ms)
  host = begin
    flash_put(acc.wire, "127.0.0.1:9", join(map((_i) -> "x", range(bytes - 1)), ""))
    "sent"
  rescue :rate_limited as e
    "wait #{{e.data.wait_ms}}"
  end
  model = if r.verdict == :sent
    "sent"
  elsif r.verdict == :wait
    "wait #{{r.wait_ms}}"
  else
    "refused"
  end
  {{**acc, bucket: r.bucket, rows: push(acc.rows, "#{{model}}|#{{host}}")}}
end

def main()
  start = {{wire: flash_open("127.0.0.1:0"), bucket: flash({{}}), rows: []}}
  done = reduce(step, start, [{rows}])
  write_stdout(json_stringify(done.rows))
end
"##,
        rows = rows.join(", ")
    )
}

#[test]
fn kodou_s_bucket_and_the_host_s_rate_agree_on_every_send_of_the_same_schedule() {
    let mut seed: u64 = 0x1b0c;
    let mut draw = |n: u64| {
        seed = seed
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (seed >> 33) % n
    };
    let schedule: Vec<(u64, u64)> = (0..160).map(|_| (1 + draw(1280), draw(30))).collect();
    let dir = project("agree", AGREED, &[("agree.b", &agreeing(&schedule))]);
    let j = run(&dir, "agree.b");
    let rows = j.as_array().unwrap_or_else(|| panic!("{j}"));
    assert_eq!(rows.len(), schedule.len());
    let mut waits = 0;
    for (i, row) in rows.iter().enumerate() {
        let (model, host) = row
            .as_str()
            .and_then(|r| r.split_once('|'))
            .unwrap_or_else(|| panic!("row {i}: {row}"));
        assert_eq!(model, host, "send {i} of {:?}", schedule[i]);
        if model.starts_with("wait ") {
            waits += 1;
        }
    }
    assert!(
        waits > 10 && waits < rows.len() - 10,
        "both verdicts occur: {waits} waits"
    );
    let _ = std::fs::remove_dir_all(dir);
}

const LOOPED: &str = "package(\"wire-looped\", \"0.1.0\")\nallow([])\nvirtualize(:comm_flash, {using: :loopback})\nvirtualize(:comm_scavenger, {using: :loopback})\n";

fn looping(held: u16, closed: u16) -> String {
    format!(
        r#"def main()
  a = tide_open(flash_open("127.0.0.1:{held}"))
  b = tide_open(flash_open("127.0.0.1:0"))
  to = flash_stats(b).address
  flash_put(a, to, "alert")
  tide_send(a, to, "bulk", 7)
  tide_put(a, to, "queued")
  tide_release(a, 100, 9)
  flash_put(a, "127.0.0.1:{closed}", "nobody")
  f = flash_next(b, 0)
  t1 = tide_next(b, 0)
  t2 = tide_next(b, 0)
  write_stdout(
    json_stringify(
      {{
        at: flash_stats(a).address,
        from: f.from,
        flash: f.payload,
        tide: [t1.payload, t1.sent_ms, t2.payload, t2.sent_ms],
        idle: flash_next(b, 60000).nil?
      }}
    )
  )
end
"#
    )
}

#[test]
fn a_program_under_loopback_and_allow_none_sends_and_receives_in_process_and_touches_no_socket() {
    let (held, held_port) = listener();
    let (closed, closed_port) = listener();
    let dir = project(
        "looped",
        LOOPED,
        &[("loop.b", &looping(held_port, closed_port))],
    );
    let started = std::time::Instant::now();
    let j = run(&dir, "loop.b");
    let at = format!("127.0.0.1:{held_port}");
    assert_eq!(
        j,
        serde_json::json!({
            "at": at,
            "from": at,
            "flash": "alert",
            "tide": ["bulk", 7, "queued", 9],
            "idle": true,
        }),
        "the link bound the address a real socket holds, which only an in-process link can"
    );
    assert!(
        started.elapsed() < Duration::from_secs(30),
        "an empty loopback inbox answers at once"
    );
    assert!(heard(&held).is_empty(), "the held port heard nothing");
    assert!(
        heard(&closed).is_empty(),
        "a frame to an address no link binds goes nowhere"
    );

    let bare = scratch("looped-bare");
    put(&bare.join("loop.b"), &looping(held_port, closed_port));
    let o = blue()
        .args(["run", "--quiet", "--allow", "none"])
        .arg(bare.join("loop.b"))
        .output()
        .expect("blue run");
    assert!(
        !o.status.success() && err(&o).contains("`flash_open` reaches the host (comm-flash)"),
        "without the provider the same program is refused: {}",
        err(&o)
    );
    assert!(heard(&held).is_empty() && heard(&closed).is_empty());
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(bare);
}

const REPLAYED: &str = "package(\"wire-replayed\", \"0.1.0\")\nallow([])\nvirtualize(:comm_flash, {using: :loopback})\nvirtualize(:comm_scavenger, {using: :loopback})\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 0, step_ms: 0})\nvirtualize(:filesystem, {using: :null_sink, for: %w[kodou]})\nvirtualize(:entropy, {using: :seeded_prng, seed: \"wire\", for: %w[shomei]})\n";

#[test]
fn the_paced_flash_program_replays_over_the_loopback_with_the_schedule_it_had_over_udp() {
    let udp = project("replay-udp", PACED, &[("flash.b", FLASH)]);
    let looped = project("replay-loop", REPLAYED, &[("flash.b", FLASH)]);
    let over_udp = run(&udp, "flash.b");
    let over_loopback = run(&looped, "flash.b");
    assert_eq!(
        over_loopback, over_udp,
        "the same program, the same schedule, no socket"
    );
    assert_eq!(over_loopback["refused"], 0, "{over_loopback}");
    let _ = std::fs::remove_dir_all(udp);
    let _ = std::fs::remove_dir_all(looped);
}

#[test]
fn tide_collapses_to_its_floor_two_ms_over_its_base_delay_and_recovers() {
    let dir = project("tide", PACED, &[("tide.b", TIDE)]);
    let j = run(&dir, "tide.b");
    let floor = j["floor"].as_i64().expect("floor");
    assert_eq!(floor, 2560);
    let rows = rows(&j, "rows");
    assert_eq!(rows.len(), 15, "{j}");
    let (base, rest) = rows.split_at(5);
    let (one_over, rest) = rest.split_at(3);
    let (two_over, recovered) = rest.split_at(3);
    assert!(
        base.windows(2).all(|w| w[1][1] > w[0][1]),
        "under the target the window grows: {base:?}"
    );
    assert!(base.iter().all(|r| r[2] == 0), "{base:?}");
    assert!(
        one_over.iter().all(|r| r[1] > floor),
        "one millisecond over the base does not collapse: {one_over:?}"
    );
    assert!(
        two_over.iter().all(|r| r[1] == floor && r[2] == 2),
        "two milliseconds over the base collapses to the floor: {two_over:?}"
    );
    assert!(
        recovered.iter().all(|r| r[1] > floor && r[2] == 0),
        "back at the base the window leaves the floor: {recovered:?}"
    );
    assert!(
        recovered.windows(2).all(|w| w[1][1] > w[0][1]),
        "and keeps growing: {recovered:?}"
    );
    let _ = std::fs::remove_dir_all(dir);
}

fn listener() -> (UdpSocket, u16) {
    let l = UdpSocket::bind("127.0.0.1:0").expect("listener");
    l.set_read_timeout(Some(Duration::from_millis(400)))
        .expect("timeout");
    let port = l.local_addr().expect("addr").port();
    (l, port)
}

fn heard(l: &UdpSocket) -> Vec<Vec<u8>> {
    let mut got = Vec::new();
    let mut buf = [0u8; 2048];
    while let Ok((n, _)) = l.recv_from(&mut buf) {
        got.push(buf[..n].to_vec());
    }
    got
}

fn breaching(port: u16) -> String {
    format!(
        "use(\"kodou\", %i[emit link pump queue])\n\ndef main()\n  peer = \"127.0.0.1:{port}\"\n  l = link(\"127.0.0.1:0\", {{channels: [:tide]}})\n  sent = pump(queue(l, peer, \"control\"))\n  alerting = link(sent.wire, {{channels: [:flash]}})\n  emit(alerting, peer, \"alert\") rescue write_stdout(\"swallowed\")\n  write_stdout(\"after\")\nend\n"
    )
}

fn run_allowing(dir: &Path, port: u16, allow: &[&str]) -> Output {
    let file = dir.join("breach.b");
    put(&file, &breaching(port));
    let mut c = blue();
    c.args(["run", "--quiet"]);
    for a in allow {
        c.args(["--allow", a]);
    }
    c.arg(&file).output().expect("blue run")
}

#[test]
fn a_frame_without_comm_flash_breaches_with_77_and_sends_nothing() {
    let dir = scratch("breach");

    let (l, port) = listener();
    let o = run_allowing(&dir, port, &["comm_scavenger", "clock", "comm_flash"]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "after");
    let both = heard(&l);
    assert_eq!(
        both.iter().map(|d| d[0]).collect::<Vec<_>>(),
        vec![0x01, 0x02],
        "with both channels granted the listener hears Tide, then Flash"
    );

    let (l, port) = listener();
    let o = run_allowing(&dir, port, &["comm_scavenger", "clock"]);
    assert_eq!(o.status.code(), Some(77), "{}{}", out(&o), err(&o));
    assert!(
        err(&o).contains("`flash_open` reaches the host (comm-flash)"),
        "{}",
        err(&o)
    );
    assert!(!out(&o).contains("swallowed") && !out(&o).contains("after"));
    let got = heard(&l);
    assert_eq!(got.len(), 1, "only the Tide control frame: {got:?}");
    assert_eq!(got[0][0], 0x01);
    assert_eq!(&got[0][9..], b"dcontrol");

    let (l, port) = listener();
    let o = run_allowing(&dir, port, &["none"]);
    assert_eq!(o.status.code(), Some(77), "{}{}", out(&o), err(&o));
    assert!(err(&o).contains("(comm-scavenger)"), "{}", err(&o));
    assert!(heard(&l).is_empty(), "a pure frame sends nothing");

    let locked = scratch("breach-lock");
    put(
        &locked.join("Bluefile"),
        "package(\"wire-breach\", \"0.1.0\")\nallow(%i[comm_scavenger clock])\nvirtualize(:filesystem, {using: :null_sink, for: %w[kodou]})\nvirtualize(:entropy, {using: :seeded_prng, seed: \"w\", for: %w[shomei]})\n",
    );
    put(&locked.join("breach.b"), &breaching(9));
    let o = blue().arg("lock").arg(&locked).output().expect("blue lock");
    assert!(!o.status.success());
    assert!(
        err(&o).contains(
            "[wire-breach] -> [kodou::link: needs 'comm-flash'] violates ceiling [clock, comm-scavenger]"
        ),
        "{}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(locked);
}

fn sorted(v: Json) -> Json {
    match v {
        Json::Array(xs) => Json::Array(xs.into_iter().map(sorted).collect()),
        Json::Object(m) => {
            let mut entries: Vec<(String, Json)> =
                m.into_iter().map(|(k, v)| (k, sorted(v))).collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            Json::Object(entries.into_iter().collect())
        }
        other => other,
    }
}

fn canonical(text: &str) -> String {
    serde_json::to_string(&sorted(serde_json::from_str(text).expect("json"))).expect("text")
}

fn b3(bytes: &[u8]) -> String {
    format!("b3:{}", blue_lang_runtime::crypto::blake3_hex(bytes))
}

fn digest(entries: &Json) -> String {
    let body = serde_json::to_string(&sorted(entries.clone())).expect("entries");
    let mut bytes = Vec::new();
    for field in [SCHEMA.as_bytes(), body.as_bytes()] {
        bytes.extend_from_slice(&u32::try_from(field.len()).expect("len").to_be_bytes());
        bytes.extend_from_slice(field);
    }
    b3(&bytes)
}

const BREACHING: &str = "use(\"shisutemu\", [:read_or])\n\ndef reader(parent)\n  path = receive()\n  send(parent, read_or(path, \"\") rescue \"swallowed\")\nend\n\ndef main()\n  pid = spawn(reader, [self])\n  monitor(pid)\n  send(pid, \"/etc/hosts\")\n  write_stdout(to_s(receive(:_, 5000)))\nend\n";

fn fresh_crash(dir: &Path) -> PathBuf {
    let file = dir.join("reader.b");
    put(&file, BREACHING);
    let traces = dir.join("traces");
    let o = blue()
        .env("BLUE_TRACE_DIR", &traces)
        .args(["run", "--quiet", "--allow", "none"])
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}", err(&o));
    let crash = std::fs::read_dir(&traces)
        .expect("traces")
        .map(|e| e.expect("entry").path())
        .find(|p| p.extension().is_some_and(|e| e == "bluecrash"))
        .expect("a .bluecrash");
    std::fs::remove_file(&file).expect("the program goes");
    crash
}

const GOSSIPED: &str = "package(\"wire-gossip\", \"0.1.0\")\nallow(%i[comm_flash comm_scavenger filesystem clock])\nvirtualize(:entropy, {using: :seeded_prng, seed: \"wire\", for: %w[shomei]})\n";

fn gossip(crashes: &[&Path], immunity: &Path) -> String {
    let reads: Vec<String> = crashes
        .iter()
        .map(|c| format!("read_file(\"{}\")", c.display()))
        .collect();
    format!(
        "use(\"kodou\", %i[address link node publish step])\nuse(\"retsu\", %i[first last])\n\ndef main()\n  la = link(\"127.0.0.1:0\", {{}})\n  lb = link(\"127.0.0.1:0\", {{}})\n  a = reduce((n, text) -> publish(n, address(lb), text), node(la, \"{a}\"), [{reads}])\n  done = reduce(\n    (acc, _i) -> [step(first(acc), 50, 16), step(last(acc), 50, 16)],\n    [a, node(lb, \"{b}\")],\n    range(8)\n  )\n  b = last(done)\n  write_stdout(json_stringify({{known: b.known, refused: b.refused, wanted: length(map_entries(b.wanted))}}))\nend\n",
        a = immunity.with_extension("a.json").display(),
        b = immunity.display(),
        reads = reads.join(", ")
    )
}

fn kensa() -> Option<PathBuf> {
    std::env::var_os("KENSA_BIN")
        .map(PathBuf::from)
        .filter(|p| p.is_file())
}

#[test]
fn a_gossiped_crash_proof_arrives_verifies_and_yields_the_immunity_entry_kensa_refuses_on() {
    let dir = scratch("gossip");
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wire")
        .join(format!("{KENSA_FIXTURE}.bluecrash"));
    let fresh = fresh_crash(&dir);
    let immunity = dir.join("kensa-immunity.json");
    let project_dir = project(
        "gossip-node",
        GOSSIPED,
        &[("first.b", &gossip(&[&fixture], &immunity))],
    );

    let j = run(&project_dir, "first.b");
    let fixture_hash = format!("b3:{KENSA_FIXTURE}");
    assert_eq!(j["known"], serde_json::json!([fixture_hash]), "{j}");
    assert_eq!(j["refused"], serde_json::json!([]), "{j}");
    assert_eq!(j["wanted"], 0, "{j}");
    let first = std::fs::read_to_string(&immunity).expect("the immunity file");

    put(
        &project_dir.join("second.b"),
        &gossip(&[&fresh, &fixture], &immunity),
    );
    let j = run(&project_dir, "second.b");
    let fresh_text = std::fs::read_to_string(&fresh).expect("crash");
    let fresh_hash = b3(canonical(&fresh_text).as_bytes());
    assert_eq!(
        j["known"].as_array().map(Vec::len),
        Some(2),
        "the fixture already known, the fresh crash learned: {j}"
    );
    assert!(j["known"]
        .as_array()
        .unwrap()
        .contains(&Json::from(fresh_hash.clone())));

    let text = std::fs::read_to_string(&immunity).expect("the immunity file");
    assert_eq!(text, canonical(&text), "the file is canonical JSON");
    let file: Json = serde_json::from_str(&text).expect("json");
    assert_eq!(file["schema"], SCHEMA);
    assert_eq!(file["digest"], Json::from(digest(&file["entries"])));
    let entries = file["entries"].as_array().expect("entries");
    let hashes: Vec<&str> = entries
        .iter()
        .map(|e| e["crash_hash"].as_str().expect("hash"))
        .collect();
    let mut want = vec![fixture_hash.as_str(), fresh_hash.as_str()];
    want.sort_unstable();
    assert_eq!(hashes, want, "sorted by crash hash, each once");
    let fixture_text = std::fs::read_to_string(&fixture).expect("fixture");
    assert_eq!(b3(canonical(&fixture_text).as_bytes()), fixture_hash);
    let fresh_doc: Json = serde_json::from_str(&fresh_text).expect("crash json");
    let fresh_entry = entries
        .iter()
        .find(|e| e["crash_hash"] == Json::from(fresh_hash.clone()))
        .expect("the fresh entry");
    assert_eq!(
        fresh_entry,
        &serde_json::json!({
            "capability": "filesystem",
            "class": "LatticeCeilingBreach",
            "crash_hash": fresh_hash,
            "def_hash": fresh_doc["def_hash"],
            "definition": "%root/reader",
            "host": "is_file?",
        })
    );

    if let Some(kensa) = kensa() {
        let theirs = dir.join("kensa-own.json");
        let o = Command::new(&kensa)
            .args(["immunize", "--bluecrash"])
            .arg(&fixture)
            .arg("--immunity")
            .arg(&theirs)
            .env_remove("KENSA_IMMUNITY")
            .output()
            .expect("kensa immunize");
        assert!(o.status.success(), "{}", err(&o));
        assert_eq!(
            std::fs::read_to_string(&theirs).expect("kensa's file"),
            first,
            "the gossiped file is byte for byte the file kensa immunize writes"
        );
        let lock = dir.join("deployment.lock");
        put(
            &lock,
            r#"{"capabilities":{"ceiling":["filesystem"],"floor":["filesystem"],"packages":{"app":["filesystem"]}}}"#,
        );
        let defs = dir.join("defs.json");
        put(
            &defs,
            &serde_json::json!([{"key": "%root/reader", "hash": fresh_doc["def_hash"]}])
                .to_string(),
        );
        let ledger = dir.join("ledger.json");
        put(&ledger, "");
        let closure = dir.join("closure");
        put(&closure, "");
        let o = Command::new(&kensa)
            .arg("admit")
            .arg("--lock")
            .arg(&lock)
            .arg("--ledger")
            .arg(&ledger)
            .args(["--profile", "low", "--json"])
            .arg("--closure")
            .arg(&closure)
            .arg("--immunity")
            .arg(&immunity)
            .arg("--defs")
            .arg(&defs)
            .output()
            .expect("kensa admit");
        let verdict: Json = serde_json::from_str(out(&o).trim())
            .unwrap_or_else(|e| panic!("{e}: {}{}", out(&o), err(&o)));
        assert_eq!(verdict["admitted"], false);
        for control in ["NIST_SP_800_53R5_IR_4", "NIST_SP_800_53R5_IR_5"] {
            let row = verdict["controls"]
                .as_array()
                .expect("controls")
                .iter()
                .find(|r| r["control"] == control)
                .unwrap_or_else(|| panic!("no {control}: {verdict}"));
            assert!(
                row["refusals"]
                    .as_array()
                    .expect("refusals")
                    .contains(&serde_json::json!({
                        "kind": "immune_crash",
                        "crash_hash": fresh_hash,
                        "def_hash": fresh_doc["def_hash"],
                        "capability": "filesystem",
                    })),
                "{control}: {row}"
            );
        }
    }
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(project_dir);
}
