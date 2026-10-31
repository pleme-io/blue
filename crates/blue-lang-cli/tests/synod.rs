use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::Value as Json;

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
    let dir = std::env::temp_dir().join(format!("blue-synod-{name}-{}", std::process::id()));
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

fn run_json(file: &Path, allow: &[&str]) -> Json {
    let mut c = blue();
    c.args(["run", "--quiet"]);
    for a in allow {
        c.args(["--allow", a]);
    }
    let o = c.arg(file).output().expect("blue run");
    assert!(o.status.success(), "blue run: {}{}", out(&o), err(&o));
    serde_json::from_str(out(&o).trim()).unwrap_or_else(|e| panic!("{e}: {}", out(&o)))
}

fn lock_of(dir: &Path) -> Json {
    serde_json::from_str(&std::fs::read_to_string(dir.join("Bluefile.lock")).expect("lock"))
        .expect("lock json")
}

fn unhex(text: &str) -> Vec<u8> {
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).expect("hex"))
        .collect()
}

fn verifies(key_hex: &str, message: &[u8], sig_hex: &str) -> bool {
    let key: [u8; 32] = unhex(key_hex).try_into().expect("32-byte key");
    let sig: [u8; 64] = unhex(sig_hex).try_into().expect("64-byte signature");
    blue_lang_runtime::crypto::ed25519_verify(&key, message, &sig).expect("well-formed")
}

const BREACHING: &str = "use(\"fuuin\", [:generate])\n\ndef main()\n  g = generate(:threshold, {min: 2, max: 3}) rescue \"swallowed\"\n  write_stdout(to_s(g))\n  write_stdout(\"after\")\nend\n";

const NAMED: &str =
    "def main()\n  g = threshold_deal(2, 3) rescue \"swallowed\"\n  write_stdout(to_s(g))\nend\n";

#[test]
fn a_threshold_word_outside_a_hold_without_mpc_threshold_is_a_fatal_breach_no_rescue_sees() {
    let dir = scratch("breach");
    let file = dir.join("breach.b");
    put(&file, BREACHING);
    for allow in [vec!["none"], vec!["entropy", "network"]] {
        let mut c = blue();
        c.args(["run", "--quiet"]);
        for a in &allow {
            c.args(["--allow", a]);
        }
        let o = c.arg(&file).output().expect("blue run");
        assert_eq!(
            o.status.code(),
            Some(77),
            "{allow:?}: {}{}",
            out(&o),
            err(&o)
        );
        assert!(
            err(&o).contains("`threshold_deal` reaches the host (mpc-threshold)"),
            "{allow:?}: {}",
            err(&o)
        );
        assert!(
            !out(&o).contains("swallowed") && !out(&o).contains("after"),
            "{allow:?}: {}",
            out(&o)
        );
    }
    let mut c = blue();
    let o = c
        .args(["run", "--quiet", "--allow", "mpc_threshold"])
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}", err(&o));
    assert!(out(&o).ends_with("after") && out(&o).contains("shares:"));

    let named = dir.join("named.b");
    put(&named, NAMED);
    let o = blue()
        .args(["run", "--quiet", "--allow", "none"])
        .arg(&named)
        .output()
        .expect("blue run");
    assert_eq!(o.status.code(), Some(1), "{}{}", out(&o), err(&o));
    assert!(
        err(&o).contains(
            "`threshold_deal` reaches the host (mpc-threshold), which this run does not allow"
        ),
        "a word the file names itself is refused before anything runs: {}",
        err(&o)
    );
    assert!(out(&o).is_empty(), "{}", out(&o));
    let _ = std::fs::remove_dir_all(dir);
}

const SIGNING: &str = r#"use("fuuin", %i[combine generate offer sign])
use("kyohi", [:raised])
use("retsu", %i[first last])
use("shomei", [:verify?])

def signed(g, picks, data)
  offers = map((p) -> offer(g.shares[p - 1], data), picks)
  commitments = map((o) -> o.commitment, offers)
  parts = map(
    fn(i)
      sign(
        data,
        g.shares[picks[i] - 1],
        {nonces: offers[i].nonces, commitments:}
      )
    end,
    range(length(picks))
  )
  combine(parts, {group: g.group, data:, commitments:})
end

def alone(g, data)
  s = first(g.shares)
  o = offer(s, data)
  t = offer(last(g.shares), data)
  both = [o.commitment, t.commitment]
  part = sign(data, s, {nonces: o.nonces, commitments: both})
  [
    raised(
      fn()
        sign(
          data,
          s,
          {nonces: offer(s, data).nonces, commitments: [o.commitment]}
        )
      end
    ),
    raised(() -> combine([part], {group: g.group, data:, commitments: both}))
  ]
end

def main()
  g = generate(:threshold, {min: 2, max: 3})
  sigs = map(
    (picks) -> signed(g, picks, "release v1"),
    [[1, 2], [1, 3], [2, 3]]
  )
  write_stdout(
    json_stringify(
      {
        key: g.key,
        group: g.group,
        sigs:,
        verified: map((s) -> verify?("release v1", s, g.key), sigs),
        other: map((s) -> verify?("release v2", s, g.key), sigs),
        alone: alone(g, "release v1"),
        shares: map((s) -> threshold_share_export(s), g.shares)
      }
    )
  )
end
"#;

#[test]
fn a_two_of_three_group_signs_with_any_two_shares_and_one_share_alone_cannot() {
    let dir = scratch("signing");
    let file = dir.join("signing.b");
    put(&file, SIGNING);
    let j = run_json(&file, &["mpc_threshold"]);
    let key = j["key"].as_str().expect("key");
    assert_eq!(j["verified"], serde_json::json!([true, true, true]), "{j}");
    assert_eq!(j["other"], serde_json::json!([false, false, false]), "{j}");
    assert_eq!(j["alone"], serde_json::json!(["refused", "refused"]), "{j}");
    let sigs: Vec<&str> = j["sigs"]
        .as_array()
        .expect("sigs")
        .iter()
        .map(|s| s.as_str().expect("sig"))
        .collect();
    assert_eq!(sigs.len(), 3);
    for sig in &sigs {
        assert!(verifies(key, b"release v1", sig), "{sig}");
        assert!(!verifies(key, b"release v2", sig), "{sig}");
    }
    assert_ne!(sigs[0], sigs[1], "fresh nonces sign each time differently");

    let group =
        tameshi::threshold::GroupKey::from_bytes(&unhex(j["group"].as_str().expect("group")))
            .expect("tameshi reads blue's group");
    assert_eq!(hex(&group.verifying_key()), key);
    assert_eq!(
        (group.params().min_signers(), group.params().max_signers()),
        (2, 3)
    );
    for (i, share) in j["shares"].as_array().expect("shares").iter().enumerate() {
        let share = tameshi::threshold::KeyShare::from_bytes(&unhex(share.as_str().expect("hex")))
            .expect("tameshi reads blue's share");
        assert_eq!(usize::from(share.participant().get()), i + 1);
        assert_eq!(hex(&share.group_key()), key);
    }
    let _ = std::fs::remove_dir_all(dir);
}

fn hex(bytes: &[u8]) -> String {
    blue_lang_runtime::crypto::encode_hex(bytes)
}

#[test]
fn shares_tameshi_deals_sign_in_blue_under_tameshi_s_group_key() {
    let params = tameshi::threshold::ThresholdParams::new(2, 3).expect("2-of-3");
    let (shares, group) = tameshi::threshold::keygen::trusted_dealer(params).expect("dealt");
    let hexes: Vec<String> = shares
        .iter()
        .map(|s| hex(&s.to_bytes().expect("share bytes")))
        .collect();
    let program = format!(
        r#"use("fuuin", %i[combine offer sign])

def main()
  a = threshold_share_import("{a}")
  c = threshold_share_import("{c}")
  oa = offer(a, "fragment root")
  oc = offer(c, "fragment root")
  commitments = [oa.commitment, oc.commitment]
  parts = [
    sign("fragment root", a, {{nonces: oa.nonces, commitments:}}),
    sign("fragment root", c, {{nonces: oc.nonces, commitments:}})
  ]
  write_stdout(json_stringify({{key: a.key, sig: combine(parts, {{group: "{g}", data: "fragment root", commitments:}})}}))
end
"#,
        a = hexes[0],
        c = hexes[2],
        g = hex(&group.to_bytes().expect("group bytes")),
    );
    let dir = scratch("tameshi");
    let file = dir.join("tameshi.b");
    put(&file, &program);
    let j = run_json(&file, &["mpc_threshold"]);
    let key = hex(&group.verifying_key());
    assert_eq!(j["key"], key.as_str());
    assert!(verifies(
        &key,
        b"fragment root",
        j["sig"].as_str().expect("sig")
    ));
    let _ = std::fs::remove_dir_all(dir);
}

const DKG: &str = r#"use("fuuin", %i[combine offer sign])
use("retsu", [:flat_map])

def main()
  starts = map((p) -> threshold_dkg_start(p, 2, 3), [1, 2, 3])
  broadcasts = map((s) -> s.broadcast, starts)
  exchanged = map((s) -> threshold_dkg_exchange(s.secret, broadcasts), starts)
  sends = flat_map(exchanged, (e) -> e.sends)
  done = map(
    (e) -> threshold_dkg_finish(e.secret, broadcasts, sends),
    exchanged
  )
  a = done[0].share
  c = done[2].share
  oa = offer(a, "m")
  oc = offer(c, "m")
  commitments = [oa.commitment, oc.commitment]
  parts = [
    sign("m", a, {nonces: oa.nonces, commitments:}),
    sign("m", c, {nonces: oc.nonces, commitments:})
  ]
  sig = combine(parts, {group: done[1].group, data: "m", commitments:})
  write_stdout(
    json_stringify(
      {
        keys: map((d) -> d.key, done),
        groups: map((d) -> d.group, done),
        sends: length(sends),
        sig:,
        again: threshold_dkg_exchange(starts[0].secret, broadcasts) rescue
          "spent"
      }
    )
  )
end
"#;

#[test]
fn three_participants_generate_a_group_by_dkg_that_any_two_sign_for() {
    let dir = scratch("dkg");
    let file = dir.join("dkg.b");
    put(&file, DKG);
    let j = run_json(&file, &["mpc_threshold"]);
    let keys = j["keys"].as_array().expect("keys");
    assert_eq!(keys.len(), 3);
    assert!(keys.iter().all(|k| k == &keys[0]), "one group key: {j}");
    let groups = j["groups"].as_array().expect("groups");
    assert!(groups.iter().all(|g| g == &groups[0]), "one group: {j}");
    assert_eq!(j["sends"], 6, "each of three sends to the other two");
    assert_eq!(j["again"], "spent", "a round one secret exchanges once");
    let key = keys[0].as_str().expect("key");
    assert!(verifies(key, b"m", j["sig"].as_str().expect("sig")));
    let _ = std::fs::remove_dir_all(dir);
}

const SEEDED: &str = "package(\"synod-seeded\", \"0.1.0\")\nallow([])\nvirtualize(:mpc_threshold, {using: :seeded, seed: \"synod\"})\n";

const SEEDED_PROGRAM: &str = r#"use("fuuin", %i[combine generate offer sign])

def main()
  g = generate(:threshold, {min: 2, max: 3})
  a = g.shares[0]
  b = g.shares[1]
  oa = offer(a, "m")
  ob = offer(b, "m")
  commitments = [oa.commitment, ob.commitment]
  parts = [
    sign("m", a, {nonces: oa.nonces, commitments:}),
    sign("m", b, {nonces: ob.nonces, commitments:})
  ]
  write_stdout(
    json_stringify(
      {
        key: g.key,
        sig: combine(parts, {group: g.group, data: "m", commitments:})
      }
    )
  )
end
"#;

#[test]
fn the_seeded_provider_signs_the_same_signature_twice_with_no_host_entropy() {
    let dir = project("seeded", SEEDED, &[("sign.b", SEEDED_PROGRAM)]);
    let lock = lock_of(&dir);
    assert_eq!(
        lock["capabilities"]["provided"]["mpc-threshold"],
        serde_json::json!({"provider": "seeded", "seed": "synod"}),
        "{lock}"
    );
    assert_eq!(
        lock["capabilities"]["ceiling"],
        serde_json::json!([]),
        "{lock}"
    );
    let first = run_json(&dir.join("sign.b"), &[]);
    let second = run_json(&dir.join("sign.b"), &[]);
    assert_eq!(first, second, "one seed, one key and one signature");
    let key = first["key"].as_str().expect("key");
    assert!(verifies(key, b"m", first["sig"].as_str().expect("sig")));

    let other = project(
        "seeded-other",
        &SEEDED.replace("seed: \"synod\"", "seed: \"another\""),
        &[("sign.b", SEEDED_PROGRAM)],
    );
    let third = run_json(&other.join("sign.b"), &[]);
    assert_ne!(
        third["key"], first["key"],
        "another seed deals another group"
    );
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(other);
}

const HELD: &str = "package(\"synod-held\", \"0.1.0\")\nallow(%i[mpc_threshold])\n";

#[test]
fn the_lock_records_the_mpc_threshold_bundle_and_refuses_it_past_a_ceiling() {
    let dir = project("held", HELD, &[("sign.b", SEEDED_PROGRAM)]);
    let lock = lock_of(&dir);
    let caps = &lock["capabilities"];
    assert_eq!(
        caps["ceiling"],
        serde_json::json!(["mpc-threshold"]),
        "{lock}"
    );
    assert_eq!(
        caps["floor"],
        serde_json::json!(["mpc-threshold"]),
        "{lock}"
    );
    assert_eq!(
        caps["packages"]["fuuin"],
        serde_json::json!(["mpc-threshold"]),
        "{lock}"
    );
    let j = run_json(&dir.join("sign.b"), &[]);
    assert!(verifies(
        j["key"].as_str().expect("key"),
        b"m",
        j["sig"].as_str().expect("sig")
    ));

    let refused = scratch("refused");
    put(
        &refused.join("Bluefile"),
        "package(\"synod-refused\", \"0.1.0\")\nallow(%i[entropy network])\n",
    );
    put(&refused.join("sign.b"), SEEDED_PROGRAM);
    let o = blue()
        .arg("lock")
        .arg(&refused)
        .output()
        .expect("blue lock");
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains(
            "[synod-refused] -> [fuuin::generate: needs 'mpc-threshold'] violates ceiling ["
        ),
        "{}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(refused);
}
