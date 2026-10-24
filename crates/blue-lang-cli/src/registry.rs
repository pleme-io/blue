use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

use blue_lang_pkg::load_path::LoadPath;
use blue_lang_pkg::lock::{Lock, LOCK_FILE};
use blue_lang_pkg::registry::{Answer, FlakeHub, RegistryError, Touroku};

pub const NETRC_VAR: &str = "BLUE_FLAKEHUB_NETRC";
pub const DETERMINATE_NETRC: &str = "/nix/var/determinate/netrc";
pub const SUI_ORIGIN_VAR: &str = "SUI_CACHE_URL";

#[derive(clap::Subcommand)]
pub enum RegistryCmd {
    #[command(
        about = "Print one backend's workflow, or with --write rewrite every standing backend's committed output"
    )]
    Render {
        backend: Option<String>,
        #[arg(long, default_value = LOCK_FILE)]
        lock: PathBuf,
        #[arg(long)]
        write: bool,
    },
    #[command(
        about = "The sui state of every pin: warm on the origin SUI_CACHE_URL names, cold, or absent; never fails"
    )]
    Status {
        #[arg(long, default_value = LOCK_FILE)]
        lock: PathBuf,
    },
}

#[derive(Debug, thiserror::Error)]
pub enum RegistryCliError {
    #[error("{path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path} is not a lock: {source}")]
    Json {
        path: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("{0}")]
    Registry(#[from] RegistryError),
    #[error("{}", .refusals.join("; "))]
    Refused { refusals: Vec<String> },
    #[error("the Bluefile declares no registry entry that stands")]
    None,
    #[error("the Bluefile declares several registries ({}); name one, or pass --write", .known.join(", "))]
    PickOne { known: Vec<String> },
}

pub struct CurlFlakeHub {
    netrc: Option<PathBuf>,
}

impl CurlFlakeHub {
    #[must_use]
    pub fn from_env() -> Self {
        let named = std::env::var_os(NETRC_VAR).map(PathBuf::from);
        let netrc = named.or_else(|| {
            let d = PathBuf::from(DETERMINATE_NETRC);
            d.is_file().then_some(d)
        });
        Self { netrc }
    }
}

fn answer_of(stdout: &str) -> Answer {
    let (body, status) = stdout.rsplit_once('\n').unwrap_or(("", stdout));
    Answer {
        status: status.trim().parse().unwrap_or(0),
        body: body.to_string(),
    }
}

impl FlakeHub for CurlFlakeHub {
    fn get(&self, url: &str) -> Answer {
        let mut cmd = Command::new("curl");
        cmd.args([
            "--silent",
            "--location",
            "--max-time",
            "30",
            "--header",
            "Accept: application/json",
            "--write-out",
            "\n%{http_code}",
        ]);
        if let Some(netrc) = &self.netrc {
            cmd.arg("--netrc-file").arg(netrc);
        }
        cmd.arg(url);
        match cmd.output() {
            Ok(out) => answer_of(&String::from_utf8_lossy(&out.stdout)),
            Err(_) => Answer {
                status: 0,
                body: String::new(),
            },
        }
    }

    fn credential(&self) -> Option<String> {
        self.netrc.as_ref().map(|p| p.display().to_string())
    }
}

fn read_lock(path: &Path) -> Result<Lock, RegistryCliError> {
    let text = std::fs::read_to_string(path).map_err(|source| RegistryCliError::Io {
        path: path.display().to_string(),
        source,
    })?;
    serde_json::from_str(&text).map_err(|source| RegistryCliError::Json {
        path: path.display().to_string(),
        source,
    })
}

fn root_of(lock: &Path) -> &Path {
    lock.parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."))
}

fn touroku_for(lock: &Path) -> Result<Touroku, RegistryCliError> {
    let loader = LoadPath::for_dir(root_of(lock));
    Ok(Touroku::load(&loader)?)
}

pub fn run(cmd: RegistryCmd) -> Result<ExitCode, RegistryCliError> {
    match cmd {
        RegistryCmd::Render {
            backend,
            lock,
            write,
        } => render(backend.as_deref(), &lock, write),
        RegistryCmd::Status { lock } => status(&lock),
    }
}

fn render(backend: Option<&str>, lock: &Path, write: bool) -> Result<ExitCode, RegistryCliError> {
    let manifest = read_lock(lock)?.manifest;
    let mut t = touroku_for(lock)?;
    let (standing, refusals) = t.backends(&manifest)?;
    for r in &refusals {
        eprintln!("❌ {r}");
    }
    let names: Vec<String> = match backend {
        Some(b) => vec![b.to_string()],
        None if standing.is_empty() => return Err(RegistryCliError::None),
        None => standing,
    };
    if !write && names.len() > 1 {
        return Err(RegistryCliError::PickOne { known: names });
    }
    for name in &names {
        let rendered = t
            .render(&manifest, name)?
            .map_err(|rs| RegistryCliError::Refused {
                refusals: rs.iter().map(ToString::to_string).collect(),
            })?;
        if write {
            let path = root_of(lock).join(&rendered.output);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(|source| RegistryCliError::Io {
                    path: parent.display().to_string(),
                    source,
                })?;
            }
            std::fs::write(&path, &rendered.text).map_err(|source| RegistryCliError::Io {
                path: path.display().to_string(),
                source,
            })?;
            eprintln!("blue: wrote {}", path.display());
        } else {
            print!("{}", rendered.text);
        }
    }
    Ok(ExitCode::SUCCESS)
}

fn probe(origin: &str, store_path: &str) -> i32 {
    Command::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command",
            "path-info",
            "--store",
            origin,
            store_path,
        ])
        .output()
        .ok()
        .and_then(|o| o.status.code())
        .unwrap_or(-1)
}

fn status(lock: &Path) -> Result<ExitCode, RegistryCliError> {
    let lock_value = read_lock(lock)?;
    let mut t = touroku_for(lock)?;
    let origin = std::env::var(SUI_ORIGIN_VAR).ok().filter(|o| !o.is_empty());
    for (name, pin) in &lock_value.sources {
        let (state, why) = match (&origin, &pin.store_path) {
            (Some(o), Some(path)) => t.sui_verdict(Some(o), probe(o, path))?,
            (Some(_), None) => (
                "absent".to_string(),
                "the pin has no storePath; relock with this blue".to_string(),
            ),
            (None, _) => t.sui_verdict(None, 0)?,
        };
        let mark = if state == "warm" { "✅" } else { "➖" };
        println!("{mark} {name} {} {state}: {why}", pin.rev);
    }
    for (name, why) in &lock_value.refused {
        println!("❌ {name} refused: {why}");
    }
    Ok(ExitCode::SUCCESS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_curl_answer_is_read_by_its_last_line() {
        assert_eq!(
            answer_of("{\"a\":1}\n200"),
            Answer {
                status: 200,
                body: "{\"a\":1}".to_string()
            }
        );
        assert_eq!(answer_of("").status, 0);
        assert_eq!(answer_of("x\nnot-a-code").status, 0);
    }
}
