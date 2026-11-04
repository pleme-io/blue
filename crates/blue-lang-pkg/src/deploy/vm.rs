use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use tatara_lisp_eval::Value;

use super::{check_name, int_of, project_path, text_of, Spec, SpecError};

pub const VM_CHECK_FIELDS: &[&str] = &[
    "program",
    "inputs",
    "expect",
    "control",
    "params",
    "tools",
    "env",
    "memory_mb",
    "cores",
    "seconds",
    "kernels",
];

pub const VM_CONTROL_FIELDS: &[&str] = &["program", "expect"];

pub const VM_KERNEL_FIELDS: &[&str] = &["package", "release", "config", "env"];

pub const DEFAULT_VM_MEMORY_MB: u32 = 2048;
pub const DEFAULT_VM_CORES: u32 = 2;
pub const DEFAULT_VM_SECONDS: u32 = 1800;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VmControl {
    pub program: String,
    pub expect: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VmKernel {
    pub package: String,
    pub release: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub config: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VmCheck {
    pub program: String,
    pub inputs: Vec<String>,
    pub expect: Vec<String>,
    pub control: VmControl,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub params: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, String>,
    pub memory_mb: u32,
    pub cores: u32,
    pub seconds: u32,
    pub kernels: BTreeMap<String, VmKernel>,
}

fn is_env_name(s: &str) -> bool {
    !s.is_empty()
        && !s.starts_with(|c: char| c.is_ascii_digit())
        && s.chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
}

fn env_of(s: &Spec<'_>) -> Result<BTreeMap<String, String>, SpecError> {
    s.map("env")?
        .into_iter()
        .map(|(key, v)| {
            if !is_env_name(&key) {
                return Err(SpecError::EnvName { got: key });
            }
            Ok((key, text_of("env", v)?))
        })
        .collect()
}

fn lines_of(s: &Spec<'_>, field: &'static str) -> Result<Vec<String>, SpecError> {
    let lines = s.texts(field)?;
    if lines.is_empty() || lines.iter().any(String::is_empty) {
        return Err(SpecError::Empty { field });
    }
    Ok(lines)
}

fn bounded_of(s: &Spec<'_>, field: &'static str, default: u32) -> Result<u32, SpecError> {
    match s.get(field) {
        None => Ok(default),
        Some(v) => {
            let n = int_of(field, v)?;
            u32::try_from(n)
                .ok()
                .filter(|n| *n > 0)
                .ok_or(SpecError::VmBound { field, got: n })
        }
    }
}

fn control_of(v: &Value) -> Result<VmControl, SpecError> {
    let s = Spec::of(v, VM_CONTROL_FIELDS)?;
    Ok(VmControl {
        program: project_path(
            "control.program",
            text_of("program", s.required("program")?)?,
        )?,
        expect: lines_of(&s, "expect")?,
    })
}

fn kernel_of(label: &str, v: &Value) -> Result<VmKernel, SpecError> {
    check_name(label)?;
    let s = Spec::of(v, VM_KERNEL_FIELDS)?;
    let package = text_of("package", s.required("package")?)?;
    let release = text_of("release", s.required("release")?)?;
    if release.is_empty() {
        return Err(SpecError::Empty { field: "release" });
    }
    let config = s.texts("config")?;
    if let Some(bad) = config.iter().find(|c| !is_env_name(c)) {
        return Err(SpecError::VmConfig { got: bad.clone() });
    }
    Ok(VmKernel {
        package,
        release,
        config,
        env: env_of(&s)?,
    })
}

pub fn vm_check_of(name: &str, spec: &Value) -> Result<VmCheck, SpecError> {
    check_name(name)?;
    let s = Spec::of(spec, VM_CHECK_FIELDS)?;
    let program = project_path("program", text_of("program", s.required("program")?)?)?;
    let kernels = s
        .map("kernels")?
        .into_iter()
        .map(|(label, v)| Ok((label.clone(), kernel_of(&label, v)?)))
        .collect::<Result<BTreeMap<_, _>, SpecError>>()?;
    if kernels.is_empty() {
        return Err(SpecError::Empty { field: "kernels" });
    }
    Ok(VmCheck {
        program,
        inputs: s.paths("inputs")?,
        expect: lines_of(&s, "expect")?,
        control: control_of(s.required("control")?)?,
        params: s.texts("params")?,
        tools: s.texts("tools")?,
        env: env_of(&s)?,
        memory_mb: bounded_of(&s, "memory_mb", DEFAULT_VM_MEMORY_MB)?,
        cores: bounded_of(&s, "cores", DEFAULT_VM_CORES)?,
        seconds: bounded_of(&s, "seconds", DEFAULT_VM_SECONDS)?,
        kernels,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bluefile::{read_bluefile, BluefileError};
    use crate::deploy::Refusal;

    fn read(body: &str) -> Result<crate::bluefile::Project, Vec<Refusal>> {
        let src = ["package(\"p\", \"0.3.0\")\n", body].concat();
        match read_bluefile(&src) {
            Ok(b) => Ok(b.project),
            Err(BluefileError::Refused { refusals }) => Err(refusals),
            Err(other) => panic!("{body}: {other}"),
        }
    }

    const CONTROL: &str = "control: {program: \"c.b\", expect: [\"1 failed\"]}";
    const PROGRAM: &str = "program: \"run.b\", expect: [\"green\"]";

    fn spec(kernels: &str, extra: &str) -> String {
        format!("vm_check(\"k\", {{{PROGRAM}, {CONTROL}, kernels: {{{kernels}}}{extra}}})\n")
    }

    #[test]
    fn a_vm_check_records_its_kernels_and_takes_every_default() {
        let p = read(&spec(
            "floor: {package: \"linuxPackages_6_6\", release: \"6.6.\"}",
            "",
        ))
        .unwrap();
        let v = &p.vm_checks["k"];
        assert_eq!(v.program, "run.b");
        assert_eq!(v.memory_mb, DEFAULT_VM_MEMORY_MB);
        assert_eq!(v.cores, DEFAULT_VM_CORES);
        assert_eq!(v.seconds, DEFAULT_VM_SECONDS);
        assert_eq!(v.kernels["floor"].release, "6.6.");
        assert!(v.kernels["floor"].config.is_empty());
        let back: VmCheck = serde_json::from_str(&serde_json::to_string(v).unwrap()).unwrap();
        assert_eq!(&back, v);
    }

    #[test]
    fn a_kernel_may_state_config_and_an_environment_of_its_own() {
        let p = read(&spec(
            "f: {package: \"p\", release: \"6.\", config: [\"FPROBE\"], env: {WANT: \"attached\"}}",
            ", params: [\"lsm=bpf\"], tools: [\"iproute2\", \"nix/veristat.nix\"], inputs: [\"kernel\"], env: {A: \"1\"}, memory_mb: 512, cores: 1, seconds: 60",
        ))
        .unwrap();
        let v = &p.vm_checks["k"];
        assert_eq!(v.kernels["f"].config, ["FPROBE"]);
        assert_eq!(v.kernels["f"].env["WANT"], "attached");
        assert_eq!(v.params, ["lsm=bpf"]);
        assert_eq!(v.tools, ["iproute2", "nix/veristat.nix"]);
        assert_eq!(v.inputs, ["kernel"]);
        assert_eq!(v.env["A"], "1");
        assert_eq!((v.memory_mb, v.cores, v.seconds), (512, 1, 60));
    }

    #[test]
    fn every_broken_rule_is_refused_by_name() {
        let k = "a: {package: \"p\", release: \"6.\"}";
        let cases = [
            ("vm_check(\"k\", {})\n".to_string(), "`program` is required"),
            (
                format!("vm_check(\"k\", {{{PROGRAM}, {CONTROL}}})\n"),
                "`kernels`",
            ),
            (spec("", ""), "`kernels`"),
            (spec("Bad: {package: \"p\", release: \"6.\"}", ""), "not a name"),
            (spec("a: {package: \"p\"}", ""), "`release` is required"),
            (spec("a: {release: \"6.\"}", ""), "`package` is required"),
            (spec("a: {package: \"p\", release: \"\"}", ""), "`release`"),
            (
                spec("a: {package: \"p\", release: \"6.\", config: [\"nope\"]}", ""),
                "kernel config",
            ),
            (
                spec("a: {package: \"p\", release: \"6.\", env: {bad: \"1\"}}", ""),
                "environment variable",
            ),
            (spec(k, ", memory_mb: 0"), "`memory_mb`"),
            (spec(k, ", seconds: -1"), "`seconds`"),
            (spec(k, ", inputs: [\"/etc\"]"), "relative path"),
            (spec(k, ", kernel: 1"), "is not a field here"),
            (
                format!("vm_check(\"k\", {{program: \"r.b\", expect: [\"g\"], kernels: {{{k}}}}})\n"),
                "`control` is required",
            ),
            (
                format!("vm_check(\"k\", {{program: \"r.b\", {CONTROL}, kernels: {{{k}}}}})\n"),
                "`expect`",
            ),
            (
                format!("vm_check(\"k\", {{{PROGRAM}, control: {{program: \"c.b\"}}, kernels: {{{k}}}}})\n"),
                "`expect`",
            ),
        ];
        for (body, needle) in cases {
            let errs: Vec<String> = read(&body)
                .expect_err(&body)
                .into_iter()
                .map(|r| r.to_string())
                .collect();
            assert!(errs.iter().any(|e| e.contains(needle)), "{body}: {errs:?}");
        }
    }

    #[test]
    fn a_broken_vm_check_leaves_its_siblings_standing() {
        let errs = read(&format!(
            "vm_check(\"bad\", {{}})\n{}",
            spec("a: {package: \"p\", release: \"6.\"}", "")
        ))
        .expect_err("one is refused");
        assert_eq!(errs.len(), 1);
    }
}
