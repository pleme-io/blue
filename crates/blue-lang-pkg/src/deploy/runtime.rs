use serde::{Deserialize, Serialize};
use tatara_lisp_eval::Value;

use super::{port_of, Spec, SpecError};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Effect {
    Network,
    Filesystem,
    Clock,
    Entropy,
    Environment,
    Process,
}

impl Effect {
    pub const ALL: [Effect; 6] = [
        Effect::Network,
        Effect::Filesystem,
        Effect::Clock,
        Effect::Entropy,
        Effect::Environment,
        Effect::Process,
    ];

    pub const DEFAULT: [Effect; 4] = [
        Effect::Network,
        Effect::Clock,
        Effect::Entropy,
        Effect::Environment,
    ];

    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Effect::Network => "network",
            Effect::Filesystem => "filesystem",
            Effect::Clock => "clock",
            Effect::Entropy => "entropy",
            Effect::Environment => "environment",
            Effect::Process => "process",
        }
    }

    #[must_use]
    pub fn wasi(self) -> Option<&'static str> {
        match self {
            Effect::Network => {
                Some("wasi:sockets and wasi:http (bind on listen, connect to egress)")
            }
            Effect::Filesystem => {
                Some("wasi:filesystem preopens (reads read-only, writes writable)")
            }
            Effect::Clock => Some("wasi:clocks"),
            Effect::Entropy => Some("wasi:random"),
            Effect::Environment => Some("wasi:cli/environment"),
            Effect::Process => None,
        }
    }

    fn of(v: &Value) -> Result<Self, SpecError> {
        let word = match v {
            Value::Keyword(k) | Value::Str(k) | Value::Symbol(k) => k.to_string(),
            other => {
                return Err(SpecError::Type {
                    field: "access.effects",
                    expected: "an effect keyword",
                    got: other.type_name(),
                })
            }
        };
        Effect::ALL
            .into_iter()
            .find(|e| e.name() == word)
            .ok_or(SpecError::AccessEffect { got: word })
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Access {
    pub effects: Vec<Effect>,
    pub egress: Vec<String>,
    pub reads: Vec<String>,
    pub writes: Vec<String>,
    pub listen: Vec<u16>,
    pub exec: Vec<String>,
}

pub const ACCESS_FIELDS: &[&str] = &["effects", "egress", "reads", "writes", "listen", "exec"];

impl Default for Access {
    fn default() -> Self {
        Access {
            effects: Effect::DEFAULT.to_vec(),
            egress: Vec::new(),
            reads: Vec::new(),
            writes: Vec::new(),
            listen: Vec::new(),
            exec: Vec::new(),
        }
    }
}

impl Access {
    #[must_use]
    pub fn default_for(port: u16) -> Self {
        Access {
            effects: Effect::DEFAULT.to_vec(),
            egress: Vec::new(),
            reads: Vec::new(),
            writes: Vec::new(),
            listen: vec![port],
            exec: Vec::new(),
        }
    }

    #[must_use]
    pub fn allows(&self, e: Effect) -> bool {
        self.effects.contains(&e)
    }
}

fn is_peer(s: &str) -> bool {
    match s.rsplit_once(':') {
        Some((host, port)) => {
            !host.is_empty()
                && !host.contains(char::is_whitespace)
                && port.parse::<u16>().is_ok_and(|p| p > 0)
        }
        None => false,
    }
}

fn absolute(field: &'static str, p: String) -> Result<String, SpecError> {
    let ok = p.starts_with('/')
        && std::path::Path::new(&p)
            .components()
            .all(|c| !matches!(c, std::path::Component::ParentDir));
    if ok {
        Ok(p)
    } else {
        Err(SpecError::AccessPath { field, got: p })
    }
}

pub fn access_of(v: Option<&Value>, port: u16) -> Result<Access, SpecError> {
    let Some(v) = v else {
        return Ok(Access::default_for(port));
    };
    let s = Spec::of(v, ACCESS_FIELDS)?;
    let effects = match s.get("effects") {
        None => Effect::DEFAULT.to_vec(),
        Some(_) => {
            let mut es = s
                .list("effects")?
                .into_iter()
                .map(Effect::of)
                .collect::<Result<Vec<_>, _>>()?;
            es.sort();
            es.dedup();
            es
        }
    };
    let egress = s.texts("egress")?;
    if let Some(bad) = egress.iter().find(|e| !is_peer(e)) {
        return Err(SpecError::AccessPeer { got: bad.clone() });
    }
    let reads = s
        .texts("reads")?
        .into_iter()
        .map(|p| absolute("access.reads", p))
        .collect::<Result<Vec<_>, _>>()?;
    let writes = s
        .texts("writes")?
        .into_iter()
        .map(|p| absolute("access.writes", p))
        .collect::<Result<Vec<_>, _>>()?;
    let listen = match s.get("listen") {
        None => vec![port],
        Some(_) => s
            .list("listen")?
            .into_iter()
            .map(|p| port_of("access.listen", p))
            .collect::<Result<Vec<_>, _>>()?,
    };
    let exec = s.texts("exec")?;
    let access = Access {
        effects,
        egress,
        reads,
        writes,
        listen,
        exec,
    };
    if !access.writes.is_empty() && !access.allows(Effect::Filesystem) {
        return Err(SpecError::WritesWithoutFilesystem);
    }
    if !access.allows(Effect::Network) {
        return Err(SpecError::ServiceWithoutNetwork);
    }
    Ok(access)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WasiGap {
    Process,
    HostProgram,
    Device,
}

impl WasiGap {
    pub const ALL: [WasiGap; 3] = [WasiGap::Process, WasiGap::HostProgram, WasiGap::Device];

    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            WasiGap::Process => "process",
            WasiGap::HostProgram => "host_program",
            WasiGap::Device => "device",
        }
    }

    #[must_use]
    pub fn why(self) -> &'static str {
        match self {
            WasiGap::Process => "WASI preview 2 has no process spawn or exec",
            WasiGap::HostProgram => {
                "the program is a native host binary, not a blue program the engine component runs"
            }
            WasiGap::Device => "WASI preview 2 reaches no device, GPU or kernel ABI",
        }
    }

    fn of(v: &Value) -> Result<Self, SpecError> {
        let word = match v {
            Value::Keyword(k) | Value::Str(k) | Value::Symbol(k) => k.to_string(),
            other => {
                return Err(SpecError::Type {
                    field: "because",
                    expected: "a WASI gap keyword",
                    got: other.type_name(),
                })
            }
        };
        WasiGap::ALL
            .into_iter()
            .find(|g| g.name() == word)
            .ok_or(SpecError::UnknownGap { got: word })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Runtime {
    Wasm,
    Native { because: WasiGap },
}

impl Default for Runtime {
    fn default() -> Self {
        Runtime::Wasm
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Need {
    pub gap: WasiGap,
    pub cause: String,
}

#[must_use]
pub fn needs(access: &Access, host: Option<&str>) -> Vec<Need> {
    let mut out = Vec::new();
    if !access.exec.is_empty() {
        out.push(Need {
            gap: WasiGap::Process,
            cause: ["its access declares exec ", &access.exec.join(", ")].concat(),
        });
    } else if access.allows(Effect::Process) {
        out.push(Need {
            gap: WasiGap::Process,
            cause: String::from("its access declares the :process effect"),
        });
    }
    if let Some(h) = host {
        out.push(Need {
            gap: WasiGap::HostProgram,
            cause: ["it runs the host program ", h].concat(),
        });
    }
    out
}

fn kind_of(v: &Value) -> Result<&'static str, SpecError> {
    let word = match v {
        Value::Keyword(k) | Value::Str(k) | Value::Symbol(k) => k.to_string(),
        other => {
            return Err(SpecError::Type {
                field: "runtime",
                expected: ":wasm or :native",
                got: other.type_name(),
            })
        }
    };
    match word.as_str() {
        "wasm" => Ok("wasm"),
        "native" => Ok("native"),
        _ => Err(SpecError::UnknownRuntime { got: word }),
    }
}

pub fn runtime_of(
    runtime: Option<&Value>,
    because: Option<&Value>,
    access: &Access,
    host: Option<&str>,
) -> Result<Runtime, SpecError> {
    let kind = runtime.map(kind_of).transpose()?.unwrap_or("wasm");
    let because = because.map(WasiGap::of).transpose()?;
    let needed = needs(access, host);
    match (kind, because) {
        ("wasm", Some(gap)) => Err(SpecError::BecauseWithoutNative { gap: gap.name() }),
        ("wasm", None) => match needed.first() {
            None => Ok(Runtime::Wasm),
            Some(n) => Err(SpecError::WasmGap {
                cause: n.cause.clone(),
                why: n.gap.why(),
                gap: n.gap.name(),
            }),
        },
        (_, None) => Err(SpecError::NativeWithoutGap),
        (_, Some(gap)) => {
            if gap == WasiGap::Device || needed.iter().any(|n| n.gap == gap) {
                Ok(Runtime::Native { because: gap })
            } else {
                Err(SpecError::GapNotNeeded { gap: gap.name() })
            }
        }
    }
}
