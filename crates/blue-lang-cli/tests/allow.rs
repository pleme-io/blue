use std::path::{Path, PathBuf};
use std::process::{Command, Output};

mod support;

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG");
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-allow-{name}-{}", std::process::id()));
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

const READS: &str =
    "def main()\n  write_stdout(\"before\\n\")\n  write_stdout(read_file(first(argv)))\nend\n";

#[test]
fn without_allow_a_run_has_every_capability() {
    let dir = scratch("unrestricted");
    let file = dir.join("reads.b");
    put(&file, READS);
    put(&dir.join("data"), "data\n");
    let o = blue().arg(&file).arg(dir.join("data")).output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "before\ndata\n");
}

#[test]
fn allow_none_refuses_a_host_name_before_anything_runs() {
    let dir = scratch("none");
    let file = dir.join("reads.b");
    put(&file, READS);
    put(&dir.join("data"), "data\n");
    for args in [
        vec!["run", "--quiet", "--allow", "none"],
        vec!["--allow", "none"],
        vec!["--allow", "clock"],
    ] {
        let o = blue()
            .args(&args)
            .arg(&file)
            .arg(dir.join("data"))
            .output()
            .unwrap();
        assert!(!o.status.success(), "{args:?}: {}", out(&o));
        assert_eq!(out(&o), "", "{args:?}: nothing ran");
        assert!(
            err(&o).contains("`read_file` reaches the host (filesystem)")
                && err(&o).contains("--allow filesystem"),
            "{args:?}: {}",
            err(&o)
        );
    }
}

#[test]
fn allow_names_the_capability_the_run_may_use() {
    let dir = scratch("granted");
    let file = dir.join("reads.b");
    put(&file, READS);
    put(&dir.join("data"), "data\n");
    for grant in [
        &["--allow", "filesystem", "--allow", "environment"][..],
        &["--allow", "host"],
    ] {
        let o = blue()
            .args(grant)
            .arg(&file)
            .arg(dir.join("data"))
            .output()
            .unwrap();
        assert!(o.status.success(), "{grant:?}: {}", err(&o));
        assert_eq!(out(&o), "before\ndata\n");
    }
    let o = blue()
        .args(["--allow", "filesystem"])
        .arg(&file)
        .arg(dir.join("data"))
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(
        err(&o).contains("`argv` reaches the host (environment)"),
        "{}",
        err(&o)
    );
}

#[test]
fn an_unknown_capability_is_refused_by_name() {
    let dir = scratch("unknown");
    let file = dir.join("reads.b");
    put(&file, READS);
    let o = blue()
        .args(["--allow", "disk"])
        .arg(&file)
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(err(&o).contains("--allow disk"), "{}", err(&o));
}

#[test]
fn a_host_name_reached_through_a_bidama_is_refused_where_it_is_called() {
    let dir = scratch("bidama");
    let file = dir.join("via.b");
    put(
        &file,
        "use(\"shisutemu\", [:read_or])\n\ndef main()\n  write_stdout(\"before\\n\")\n  write_stdout(read_or(\"/etc/hosts\", \"\"))\nend\n",
    );
    let o = blue()
        .args(["--allow", "none"])
        .arg(&file)
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(77), "{}", out(&o));
    assert_eq!(out(&o), "before\n");
    assert!(
        err(&o).contains("capability breach: `is_file?` reaches the host (filesystem)"),
        "{}",
        err(&o)
    );
}

#[test]
fn no_rescue_swallows_a_breach() {
    let dir = scratch("rescue");
    for (name, body) in [
        (
            "inline",
            "  v = read_or(\"/etc/hosts\", \"\") rescue \"swallowed\"\n  write_stdout(v)\n",
        ),
        (
            "catch-all",
            "  v = begin\n    read_or(\"/etc/hosts\", \"\")\n  rescue _\n    \"swallowed\"\n  end\n  write_stdout(v)\n",
        ),
        (
            "ensure",
            "  v = begin\n    read_or(\"/etc/hosts\", \"\")\n  rescue e\n    \"swallowed #{e.message}\"\n  ensure\n    write_stdout(\"ensure ran\\n\")\n  end\n  write_stdout(v)\n",
        ),
    ] {
        let file = dir.join(format!("{name}.b"));
        put(
            &file,
            &format!(
                "use(\"shisutemu\", [:read_or])\n\ndef main()\n  write_stdout(\"before\\n\")\n{body}end\n"
            ),
        );
        let o = blue()
            .args(["--allow", "none"])
            .arg(&file)
            .output()
            .unwrap();
        assert_eq!(o.status.code(), Some(77), "{name}: {}{}", out(&o), err(&o));
        assert_eq!(out(&o), "before\n", "{name}: nothing after the breach ran");
        assert!(err(&o).contains("capability breach"), "{name}: {}", err(&o));
        let granted = blue()
            .args(["--allow", "filesystem"])
            .arg(&file)
            .output()
            .unwrap();
        assert!(granted.status.success(), "{name}: {}", err(&granted));
        assert!(!out(&granted).contains("swallowed"), "{name}: {}", out(&granted));
    }
}

#[test]
fn a_breach_in_a_spawned_process_ends_it_and_its_monitor_sees_why() {
    let dir = scratch("spawned");
    let file = dir.join("spawns.b");
    put(
        &file,
        "use(\"shisutemu\", [:read_or])\n\ndef reader(parent)\n  send(parent, read_or(\"/etc/hosts\", \"\") rescue \"swallowed\")\nend\n\ndef main()\n  pid = spawn(reader, [self])\n  monitor(pid)\n  write_stdout(to_s(receive(:_, 5000)))\nend\n",
    );
    let o = blue()
        .args(["--allow", "none"])
        .arg(&file)
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert!(out(&o).contains(":down"), "{}", out(&o));
    assert!(
        out(&o).contains(":fatal") && out(&o).contains("capability-breach"),
        "{}",
        out(&o)
    );
    assert!(!out(&o).contains("swallowed"), "{}", out(&o));
    let o = blue()
        .args(["--allow", "filesystem"])
        .arg(&file)
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert!(!out(&o).contains(":fatal"), "{}", out(&o));
}

#[cfg(unix)]
#[test]
fn a_shebang_states_the_capabilities_of_its_script() {
    use std::os::unix::fs::PermissionsExt;
    let dir = scratch("shebang");
    let script = dir.join("tool");
    put(
        &script,
        "#!/usr/bin/env -S blue --allow none\nwrite_stdout(\"#{read_file(\"/etc/hosts\")}\")\n",
    );
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
    let bin = Path::new(env!("CARGO_BIN_EXE_blue")).parent().unwrap();
    let path = std::env::join_paths(std::iter::once(bin.to_path_buf()).chain(
        std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()),
    ))
    .unwrap();
    let o = support::run_fresh_script(|| {
        let mut c = Command::new(&script);
        c.env("PATH", &path)
            .env_remove("BLUE_PATH")
            .env_remove("BLUE_CONFIG")
            .env_remove("BLUE_TIER");
        c
    });
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains("`read_file` reaches the host"),
        "{}",
        err(&o)
    );
}
