#[macro_use]
mod moduledoc;

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::{json, Value as Json};

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
    let dir = std::env::temp_dir().join(format!("blue-senses-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().expect("a parent")).expect("fixture dir");
    std::fs::write(path, text).expect("write fixture");
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn lock(dir: &Path) -> Output {
    blue().arg("lock").arg(dir).output().expect("blue lock")
}

fn locked(dir: &Path) {
    let o = lock(dir);
    assert!(
        o.status.success(),
        "blue lock {}: {}",
        dir.display(),
        err(&o)
    );
}

fn lock_of(dir: &Path) -> Json {
    serde_json::from_str(&std::fs::read_to_string(dir.join("Bluefile.lock")).expect("lock"))
        .expect("lock json")
}

fn absent_devices(c: &mut Command, dir: &Path) {
    c.env("BLUE_AUDIO_LIBRARY", dir.join("no-such-audio-library"))
        .env("BLUE_CANVAS_SOCKET", dir.join("no-such-canvas.sock"));
}

fn run(file: &Path, allow: &[&str]) -> Output {
    let mut c = blue();
    absent_devices(&mut c, file.parent().expect("a parent"));
    c.args(["run", "--quiet"]);
    for a in allow {
        c.args(["--allow", a]);
    }
    c.arg(file).output().expect("blue run")
}

const WORDS: &[(&str, &str, &str)] = &[
    (
        "speak",
        "play_audio({rate: 8000, channels: 1, samples: [0.0]})",
        "audio-out",
    ),
    ("speaker_format", "audio_out_format", "audio-out"),
    (
        "listen",
        "capture_audio(1, {rate: 8000, channels: 1})",
        "audio-in",
    ),
    ("mic_format", "audio_in_format", "audio-in"),
    (
        "open_canvas",
        "canvas_open({width: 4, height: 4})",
        "display",
    ),
    ("clear_canvas", "canvas_clear(nil, \"#000000\")", "display"),
    (
        "fill_canvas",
        "canvas_fill_rect(nil, 0, 0, 1, 1, \"#000000\")",
        "display",
    ),
    (
        "write_canvas",
        "canvas_text(nil, 0, 0, \"a\", \"#000000\")",
        "display",
    ),
    ("show_canvas", "canvas_present(nil)", "display"),
    ("read_canvas", "canvas_pixel(nil, 0, 0)", "display"),
    ("close_canvas", "canvas_close(nil)", "display"),
];

fn word_of(call: &str) -> &str {
    call.split('(').next().expect("a word")
}

#[test]
fn every_sense_word_under_a_hold_without_its_bundle_is_a_fatal_breach_no_rescue_sees() {
    let dir = scratch("held");
    put(
        &dir.join("Bluefile"),
        "package(\"sensesapp\", \"0.1.0\")\npackages(\"bidamas\")\n",
    );
    put(
        &dir.join("bidamas/kankaku/Bluefile"),
        "package(\"kankaku\", \"0.1.0\")\n",
    );
    let defs: Vec<String> = WORDS
        .iter()
        .map(|(name, call, _)| format!("def {name}()\n  {call}\nend\n"))
        .collect();
    put(&dir.join("bidamas/kankaku/kankaku.b"), &defs.join("\n"));
    locked(&dir.join("bidamas/kankaku"));
    locked(&dir);

    for (name, call, label) in WORDS {
        let word = word_of(call);
        let file = dir.join(format!("{name}.b"));
        put(
            &file,
            &format!("use(\"kankaku\", [:{name}])\n\ndef main()\n  {name}() rescue write_stdout(\"swallowed\")\n  write_stdout(\"after\")\nend\n"),
        );
        let others: Vec<&str> = ["audio_out", "audio_in", "display"]
            .into_iter()
            .filter(|o| o.replace('_', "-") != *label)
            .collect();
        for allow in [vec!["none"], others] {
            let o = run(&file, &allow);
            assert_eq!(
                o.status.code(),
                Some(77),
                "{word} under {allow:?}: {}{}",
                out(&o),
                err(&o)
            );
            assert!(
                err(&o).contains(&format!("`{word}` reaches the host ({label})")),
                "{word} under {allow:?}: {}",
                err(&o)
            );
            assert!(
                !out(&o).contains("swallowed") && !out(&o).contains("after"),
                "{word} under {allow:?}: {}",
                out(&o)
            );
        }

        let named = dir.join(format!("named_{name}.b"));
        put(
            &named,
            &format!("def main()\n  {call} rescue write_stdout(\"swallowed\")\nend\n"),
        );
        let o = run(&named, &["none"]);
        assert_eq!(o.status.code(), Some(1), "{word}: {}{}", out(&o), err(&o));
        assert!(
            err(&o).contains(&format!(
                "`{word}` reaches the host ({label}), which this run does not allow"
            )),
            "a word the file names itself is refused before anything runs: {}",
            err(&o)
        );
        assert!(!out(&o).contains("swallowed"), "{word}: {}", out(&o));
    }
    let _ = std::fs::remove_dir_all(dir);
}

const ROUND_TRIP: &str = moduledoc!(
    "virtualapp plays two clips, hears them back, draws a frame, and writes it all as JSON.",
    "json_stringify([1, 2]) #=> \"[1,2]\"",
    "def main()
  play_audio({rate: 8000, channels: 2, samples: [0.5, -0.25, 1, 0]})
  play_audio({rate: 8000, channels: 2, samples: [-1.0, 0.125]})
  heard = capture_audio(4, {rate: 8000, channels: 2})
  c = canvas_open({width: 16, height: 8, title: \"probe\"})
  canvas_clear(c, \"#102030\")
  canvas_fill_rect(c, 1, 1, 2, 2, \"#f00\")
  canvas_text(c, 8, 0, \"A\", \"#ffffff\")
  before = canvas_pixel(c, 2, 2)
  canvas_present(c)
  shown = [
    canvas_pixel(c, 0, 0),
    canvas_pixel(c, 2, 2),
    canvas_pixel(c, 3, 3),
    canvas_pixel(c, 10, 0),
    canvas_pixel(c, 16, 0)
  ]
  canvas_close(c)
  write_stdout(
    json_stringify(
      {
        heard: heard.samples,
        before:,
        shown:,
        out: audio_out_format,
        in: audio_in_format
      }
    )
  )
end
"
);

#[test]
fn the_virtual_senses_play_into_a_sink_a_monitor_reads_back_and_a_framebuffer_shows_what_was_drawn()
{
    let dir = scratch("virtual");
    put(
        &dir.join("Bluefile"),
        "package(\"virtualapp\", \"0.1.0\")\nallow([])\nvirtualize(:audio_out, {using: :recording_sink})\nvirtualize(:audio_in, {using: :monitor})\nvirtualize(:display, {using: :framebuffer})\n",
    );
    put(&dir.join("main.b"), ROUND_TRIP);
    locked(&dir);
    let caps = &lock_of(&dir)["capabilities"];
    assert_eq!(caps["ceiling"], json!([]), "{caps}");
    assert_eq!(
        caps["provided"],
        json!({
            "audio-out": {"provider": "recording-sink"},
            "audio-in": {"provider": "monitor"},
            "display": {"provider": "framebuffer"},
        }),
        "{caps}"
    );
    for _ in 0..2 {
        let o = run(&dir.join("main.b"), &[]);
        assert!(o.status.success(), "{}{}", out(&o), err(&o));
        let got: Json = serde_json::from_str(&out(&o)).expect("one JSON object");
        assert_eq!(
            got["heard"],
            json!([0.5, -0.25, 1.0, 0.0, -1.0, 0.125, 0.0, 0.0]),
            "the two clips played, read back in order, then silence: {got}"
        );
        assert_eq!(got["before"], json!("#000000"), "{got}");
        assert_eq!(
            got["shown"],
            json!(["#102030", "#ff0000", "#102030", "#ffffff", null]),
            "{got}"
        );
        assert_eq!(got["out"], json!({"rate": 48000, "channels": 2}), "{got}");
        assert_eq!(got["in"], json!({"rate": 48000, "channels": 2}), "{got}");
    }

    let seeded = scratch("seeded");
    put(
        &seeded.join("Bluefile"),
        "package(\"seededapp\", \"0.1.0\")\nallow([])\nvirtualize(:audio_in, {using: :seeded_noise, seed: \"hum\"})\n",
    );
    put(
        &seeded.join("main.b"),
        moduledoc!(
            "seededapp writes three frames it hears from seeded noise, as JSON.",
            "json_stringify([1, 2]) #=> \"[1,2]\"",
            "def main()\n  write_stdout(\n    json_stringify(capture_audio(3, {rate: 16000, channels: 2}).samples)\n  )\nend\n"
        ),
    );
    locked(&seeded);
    let first = run(&seeded.join("main.b"), &[]);
    assert!(first.status.success(), "{}{}", out(&first), err(&first));
    let samples: Vec<f64> = serde_json::from_str(&out(&first)).expect("a JSON list");
    assert_eq!(samples.len(), 6);
    assert!(
        samples.iter().all(|s| (-1.0..1.0).contains(s)),
        "{samples:?}"
    );
    assert!(
        samples.iter().all(|s| (s * 32768.0).fract() == 0.0),
        "each sample is a 16-bit step: {samples:?}"
    );
    assert_eq!(
        out(&run(&seeded.join("main.b"), &[])),
        out(&first),
        "the same seed captures the same samples in every run"
    );
    put(
        &seeded.join("Bluefile"),
        "package(\"seededapp\", \"0.1.0\")\nallow([])\nvirtualize(:audio_in, {using: :seeded_noise, seed: \"buzz\"})\n",
    );
    locked(&seeded);
    assert_ne!(out(&run(&seeded.join("main.b"), &[])), out(&first));
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(seeded);
}

#[test]
fn a_host_with_no_audio_system_and_no_canvas_server_answers_each_word_with_a_named_refusal() {
    let dir = scratch("absent");
    let file = dir.join("absent.b");
    put(
        &file,
        "def kind(f)\n  f()\n  \"ran\"\nrescue e\n  to_s(e.kind)\nend\n\ndef main()\n  kinds = [\n    kind(() -> play_audio({rate: 8000, channels: 1, samples: [0.0]})),\n    kind(() -> play_audio({rate: 8000, channels: 1, samples: []})),\n    kind(() -> capture_audio(1, {rate: 8000, channels: 1})),\n    kind(() -> canvas_open({width: 4, height: 4}))\n  ]\n  write_stdout(json_stringify([kinds, audio_out_format, audio_in_format]))\nend\n",
    );
    let o = run(&file, &["audio_out", "audio_in", "display"]);
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    let got: Json = serde_json::from_str(&out(&o)).expect("one JSON list");
    assert_eq!(
        got,
        json!([
            ["unsupported", "unsupported", "unsupported", "not_found"],
            null,
            null
        ]),
        "{}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn the_lock_records_each_sense_and_refuses_it_under_a_ceiling_without_it() {
    let program = "def main()\n  play_audio({rate: 8000, channels: 1, samples: []})\n  capture_audio(0, {rate: 8000, channels: 1})\n  canvas_close(canvas_open({width: 1, height: 1}))\nend\n";
    let project = |name: &str, allow: &str| {
        let dir = scratch(name);
        put(
            &dir.join("Bluefile"),
            &format!("package(\"lockapp\", \"0.1.0\")\nallow(%i[{allow}])\n"),
        );
        put(&dir.join("senses.b"), program);
        dir
    };

    let held = project("lock-held", "audio_out audio_in display");
    locked(&held);
    let caps = &lock_of(&held)["capabilities"];
    assert_eq!(
        caps["ceiling"],
        json!(["audio-out", "audio-in", "display"]),
        "{caps}"
    );
    assert_eq!(
        caps["floor"],
        json!(["audio-out", "audio-in", "display"]),
        "{caps}"
    );
    assert_eq!(
        caps["definitions"]["lockapp::main"],
        json!(["audio-out", "audio-in", "display"]),
        "{caps}"
    );
    let o = blue()
        .args(["bluefile", "--confirm"])
        .arg(held.join("Bluefile"))
        .output()
        .expect("blue bluefile --confirm");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));

    let refused = project("lock-refused", "clock");
    let o = lock(&refused);
    assert!(!o.status.success(), "{}", out(&o));
    for label in ["audio-out", "audio-in", "display"] {
        assert!(
            err(&o).contains(&format!(
                "[lockapp::main: needs '{label}'] violates ceiling [clock]"
            )),
            "{label}: {}",
            err(&o)
        );
    }
    assert!(!refused.join("Bluefile.lock").exists());

    let partial = project("lock-partial", "audio_out audio_in");
    let o = lock(&partial);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains("[lockapp::main: needs 'display'] violates ceiling [audio-out, audio-in]"),
        "{}",
        err(&o)
    );
    for d in [held, refused, partial] {
        let _ = std::fs::remove_dir_all(d);
    }
}
