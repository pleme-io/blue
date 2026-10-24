use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::PathBuf;

use blue_lang_pkg::bluefile::{read_bluefile, BluefileError};
use blue_lang_pkg::load_path::LoadPath;
use blue_lang_pkg::lock::{confirm, lock_with, Lock, ManifestRecord, Prefetch, Resolve};
use blue_lang_pkg::registry::{Answer, FlakeHub, Touroku};

const VERSION: &str = include_str!("fixtures/flakehub/version-flake-checker-0.1.json");
const ABSENT: &str = include_str!("fixtures/flakehub/absent-pleme-io-blue.json");
const PREFETCH: &str = include_str!("fixtures/flakehub/prefetch-flake-checker-0.1.20.json");
const GITHUB_PREFETCH: &str = r#"{"hash":"sha256-83hQT5WB0TIJVH71DYQAdCX4PYNKucSmJRvk5LkflzQ=","locked":{"lastModified":1790187679,"owner":"pleme-io","repo":"blue","rev":"03ae6ac5c7b38a8bb82cea5cc92c8ab237750d27","type":"github"},"original":{"owner":"pleme-io","repo":"blue","type":"github"},"storePath":"/nix/store/zrhpyzzbmqg622gk1xx9sj03lvmymbrp-source"}"#;
const REVISION: &str = "9ffd1b0af33ab1d18f1a1903d5f351af8ede16ea";
const CHECKER: &str = "flakehub:DeterminateSystems/flake-checker/0.1.*";

fn bidamas() -> LoadPath {
    LoadPath::new([PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bidamas")])
}

struct Recorded {
    answers: BTreeMap<String, Answer>,
    asked: RefCell<Vec<String>>,
    credential: Option<String>,
}

impl Recorded {
    fn new(answers: &[(&str, u16, &str)]) -> Self {
        Self {
            answers: answers
                .iter()
                .map(|(u, s, b)| {
                    (
                        (*u).to_string(),
                        Answer {
                            status: *s,
                            body: (*b).to_string(),
                        },
                    )
                })
                .collect(),
            asked: RefCell::new(Vec::new()),
            credential: None,
        }
    }
}

impl FlakeHub for Recorded {
    fn get(&self, url: &str) -> Answer {
        self.asked.borrow_mut().push(url.to_string());
        self.answers.get(url).cloned().unwrap_or(Answer {
            status: 0,
            body: String::new(),
        })
    }

    fn credential(&self) -> Option<String> {
        self.credential.clone()
    }
}

struct Canned(BTreeMap<String, String>);

impl Prefetch for Canned {
    fn prefetch(&self, url: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        self.0
            .get(url)
            .cloned()
            .ok_or_else(|| format!("no recorded prefetch for {url}").into())
    }
}

fn canned() -> Canned {
    Canned(BTreeMap::from([
        (
            "https://flakehub.com/f/DeterminateSystems/flake-checker/0.1.20.tar.gz".to_string(),
            PREFETCH.to_string(),
        ),
        (
            "github:pleme-io/blue".to_string(),
            GITHUB_PREFETCH.to_string(),
        ),
    ]))
}

const API: &str = "https://api.flakehub.com/version/DeterminateSystems/flake-checker/0.1.*";

fn bluefile(sources: &[(&str, &str)]) -> String {
    let mut s = String::from("package(\"p\", \"0.1.0\")\n");
    for (name, url) in sources {
        s.push_str(&format!("source(\"{name}\", \"{url}\", \"bidamas\")\n"));
    }
    s
}

fn locked(src: &str, flakehub: &dyn FlakeHub, previous: Option<&Lock>) -> (Lock, Vec<String>) {
    let loader = bidamas();
    lock_with(
        src,
        &BTreeMap::new(),
        &canned(),
        &Resolve {
            flakehub: Some(flakehub),
            loader: &loader,
            previous,
        },
    )
    .expect("lock")
}

#[test]
fn a_flakehub_range_locks_to_the_exact_revision_and_nar_hash() {
    let src = bluefile(&[("checker", CHECKER)]);
    let fh = Recorded::new(&[(API, 200, VERSION)]);
    let (lock, notes) = locked(&src, &fh, None);
    let pin = &lock.sources["checker"];
    assert_eq!(pin.url, CHECKER);
    assert_eq!(pin.rev, REVISION);
    assert_eq!(
        pin.nar_hash,
        "sha256-Oq+HZzB0mWhixLl8jGcBRWrlOETLhath75ndeJdcN1g="
    );
    assert_eq!(pin.version.as_deref(), Some("0.1.20"));
    assert!(pin
        .fetch
        .as_deref()
        .is_some_and(|f| f.starts_with("https://api.flakehub.com/f/pinned/")));
    assert!(notes.is_empty(), "{notes:?}");
    assert_eq!(fh.asked.borrow().as_slice(), [API]);
    let text = blue_lang_pkg::lock::render(&lock).unwrap();
    assert!(confirm(&src, &BTreeMap::new(), Some(&text))
        .unwrap()
        .is_fresh());
}

#[test]
fn an_absent_flake_refuses_its_entry_and_its_siblings_still_pin() {
    let src = bluefile(&[
        ("blue", "github:pleme-io/blue"),
        ("gone", "flakehub:pleme-io/blue/*"),
    ]);
    let fh = Recorded::new(&[(
        "https://api.flakehub.com/version/pleme-io/blue/*",
        404,
        ABSENT,
    )]);
    let (lock, notes) = locked(&src, &fh, None);
    assert!(lock.sources.contains_key("blue"));
    assert!(!lock.sources.contains_key("gone"));
    assert!(
        lock.refused["gone"].contains("(absent)"),
        "{:?}",
        lock.refused
    );
    assert_eq!(notes.len(), 1);
    let text = blue_lang_pkg::lock::render(&lock).unwrap();
    assert!(confirm(&src, &BTreeMap::new(), Some(&text))
        .unwrap()
        .is_fresh());
}

#[test]
fn an_outage_keeps_the_locked_pin() {
    let src = bluefile(&[("checker", CHECKER)]);
    let (first, _) = locked(&src, &Recorded::new(&[(API, 200, VERSION)]), None);
    let (again, notes) = locked(&src, &Recorded::new(&[]), Some(&first));
    assert_eq!(again.sources, first.sources);
    assert!(again.refused.is_empty());
    assert!(notes[0].contains("(unavailable)"), "{notes:?}");
    assert!(notes[0].contains(REVISION), "{notes:?}");
}

#[test]
fn a_revision_the_fetched_tree_does_not_match_is_refused() {
    let src = bluefile(&[("checker", CHECKER)]);
    let other = VERSION.replace(REVISION, &"a".repeat(40));
    let fh = Recorded::new(&[(API, 200, &other)]);
    let (lock, _) = locked(&src, &fh, None);
    assert!(
        lock.refused["checker"].contains("(disagrees)"),
        "{:?}",
        lock.refused
    );
}

#[test]
fn no_seam_refuses_the_entry_and_reads_no_network() {
    let src = bluefile(&[("checker", CHECKER)]);
    let loader = bidamas();
    let (lock, _) = lock_with(
        &src,
        &BTreeMap::new(),
        &canned(),
        &Resolve {
            flakehub: None,
            loader: &loader,
            previous: None,
        },
    )
    .unwrap();
    assert!(lock.refused["checker"].contains("(unavailable)"));
}

fn manifest(src: &str) -> ManifestRecord {
    ManifestRecord::of(&read_bluefile(src).expect("bluefile"))
}

#[test]
fn a_private_package_renders_private_and_a_visibility_field_is_refused() {
    let mut t = Touroku::load(&bidamas()).expect("touroku");
    let m = manifest(
        "package(\"kensa_x\", \"0.1.0\", :private)\nregistry(:flakehub, {plan: :paid, tag: :semver})\nregistry(:sui, {outputs: [\"default\"]})\n",
    );
    let r = t.render(&m, "flakehub").unwrap().expect("renders");
    assert!(r.text.contains("visibility: \"private\""), "{}", r.text);
    assert!(!r.text.contains("\"public\""));
    let (standing, refusals) = t.backends(&m).unwrap();
    assert_eq!(standing, ["flakehub", "sui"]);
    assert!(refusals.is_empty());

    let bad = manifest(
        "package(\"kensa_x\", \"0.1.0\", :private)\nregistry(:flakehub, {visibility: :public})\nregistry(:sui, {outputs: [\"default\"]})\n",
    );
    let (standing, refusals) = t.backends(&bad).unwrap();
    assert_eq!(standing, ["sui"]);
    assert_eq!(refusals.len(), 1);
    assert_eq!(refusals[0].kind, "invalid");
    assert!(t.render(&bad, "flakehub").unwrap().is_err());
}

#[test]
fn the_sui_rendering_names_no_origin_and_no_key() {
    let mut t = Touroku::load(&bidamas()).expect("touroku");
    let m =
        manifest("package(\"p\", \"0.1.0\", :public)\nregistry(:sui, {outputs: [\"default\"]})\n");
    let r = t.render(&m, "sui").unwrap().expect("renders");
    assert_eq!(r.output, ".github/workflows/registry-sui.yml");
    for word in ["rio", "5000", "sui-1", "signing"] {
        assert!(!r.text.contains(word), "{word} in {}", r.text);
    }
    assert_eq!(t.sui_verdict(None, 0).unwrap().0, "absent");
}

#[test]
fn the_bluefile_types_registry_and_visibility() {
    for (src, needle) in [
        ("package(\"p\", \"0.1.0\", :secret)\n", "visibility"),
        ("package(\"p\", \"0.1.0\")\nregistry(:sui, \"x\")\n", "spec"),
        (
            "package(\"p\", \"0.1.0\")\nregistry(:sui, {outputs: [\"a\"]})\nregistry(:sui, {outputs: [\"b\"]})\n",
            "sui",
        ),
    ] {
        match read_bluefile(src) {
            Err(BluefileError::Malformed(m)) => assert!(m.to_string().contains(needle), "{m}"),
            other => panic!("{src}: {other:?}"),
        }
    }
    let m = manifest("package(\"p\", \"0.1.0\", \"unlisted\")\nregistry(:flakehub, {})\n");
    let v = serde_json::to_value(&m).unwrap();
    assert_eq!(v["visibility"], "unlisted");
    assert_eq!(
        v["registries"]["flakehub"],
        serde_json::json!({"output": ".github/workflows/registry-flakehub.yml"})
    );
}
