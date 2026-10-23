use serde::{Deserialize, Serialize};
use tatara_lisp_eval::Value;

use super::{check_name, project_path, Spec, SpecError};

pub const FRONTEND_FIELDS: &[&str] = &["views", "tokens", "schema", "pwa"];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Frontend {
    pub views: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tokens: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub pwa: bool,
}

pub fn frontend_of(name: &str, spec: &Value) -> Result<Frontend, SpecError> {
    check_name(name)?;
    let s = Spec::of(spec, FRONTEND_FIELDS)?;
    s.required("views")?;
    let views = s.paths("views")?;
    if views.is_empty() {
        return Err(SpecError::Empty { field: "views" });
    }
    let path = |field: &'static str| -> Result<Option<String>, SpecError> {
        s.text(field)?.map(|p| project_path(field, p)).transpose()
    };
    Ok(Frontend {
        views,
        tokens: path("tokens")?,
        schema: path("schema")?,
        pwa: s.flag("pwa")?,
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

    fn refused(body: &str) -> Vec<String> {
        read(body)
            .expect_err(body)
            .into_iter()
            .map(|r| r.to_string())
            .collect()
    }

    #[test]
    fn a_full_frontend_is_recorded_field_by_field() {
        let p = read(
            "frontend(\"console\", {views: [\"views\", \"pages/home.b\"], tokens: \"tokens.b\", \
             schema: \"schema.graphql\", pwa: true})\n",
        )
        .unwrap();
        assert_eq!(
            p.frontends["console"],
            Frontend {
                views: vec!["views".to_string(), "pages/home.b".to_string()],
                tokens: Some("tokens.b".to_string()),
                schema: Some("schema.graphql".to_string()),
                pwa: true,
            }
        );
    }

    #[test]
    fn a_minimal_frontend_leaves_the_optional_keys_out_of_the_lock() {
        let p = read("frontend(\"site\", {views: [\"views\"]})\n").unwrap();
        let f = &p.frontends["site"];
        assert!(f.tokens.is_none() && f.schema.is_none() && !f.pwa);
        let json = serde_json::to_string(f).unwrap();
        assert_eq!(json, "{\"views\":[\"views\"]}");
        let back: Frontend = serde_json::from_str(&json).unwrap();
        assert_eq!(&back, f);
    }

    #[test]
    fn a_project_without_a_frontend_writes_no_frontends_key() {
        let p = read("").unwrap();
        assert!(p.frontends.is_empty());
        assert!(!serde_json::to_string(&p).unwrap().contains("frontends"));
    }

    #[test]
    fn each_bad_shape_is_refused_naming_its_rule() {
        let cases = [
            ("\"console\", \"views\"", "must be a map"),
            ("\"console\", {}", "`views` is required"),
            ("\"console\", {views: []}", "`views` is empty"),
            ("\"console\", {views: \"views\"}", "`views` must be a list"),
            ("\"console\", {views: [1]}", "`views` must be a string"),
            (
                "\"console\", {views: [\"/abs\"]}",
                "`views` must be a relative path",
            ),
            (
                "\"console\", {views: [\"v\"], tokens: \"../t.b\"}",
                "`tokens` must be a relative path",
            ),
            (
                "\"console\", {views: [\"v\"], schema: 3}",
                "`schema` must be a string",
            ),
            (
                "\"console\", {views: [\"v\"], pwa: \"yes\"}",
                "`pwa` must be true or false",
            ),
            (
                "\"console\", {views: [\"v\"], route: \"/\"}",
                "`route` is not a field here",
            ),
            ("\"Console\", {views: [\"v\"]}", "is not a name"),
        ];
        for (args, expect) in cases {
            let got = refused(&format!("frontend({args})\n"));
            assert!(
                got.len() == 1 && got[0].contains(expect) && got[0].starts_with("`frontend("),
                "{args}: wanted `{expect}`, got {got:?}"
            );
        }
    }

    #[test]
    fn every_refused_entry_is_reported_in_one_pass() {
        let got =
            refused("frontend(\"a\", {views: []})\nfrontend(\"b\", {views: [\"v\"], pwa: 1})\n");
        assert_eq!(got.len(), 2, "{got:?}");
        assert!(
            got[0].contains("\"a\"") && got[1].contains("\"b\""),
            "{got:?}"
        );
    }

    #[test]
    fn a_name_declared_twice_is_malformed() {
        let src = "package(\"p\", \"0.3.0\")\nfrontend(\"a\", {views: [\"v\"]})\nfrontend(\"a\", {views: [\"w\"]})\n";
        let err = read_bluefile(src).unwrap_err().to_string();
        assert!(err.contains("`frontend` declares `a` twice"), "{err}");
    }

    #[test]
    fn the_word_takes_exactly_a_name_and_a_spec() {
        let src = "package(\"p\", \"0.3.0\")\nfrontend(\"a\")\n";
        let err = read_bluefile(src).unwrap_err().to_string();
        assert!(
            err.contains("`frontend` is called as `frontend(name, spec)`"),
            "{err}"
        );
    }
}
