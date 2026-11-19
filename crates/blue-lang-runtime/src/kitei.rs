//! The rule registry the runtime decides by. Each shipped rule of the default
//! cascade is a row of [`RULES`]: its id, the facts a definition must hold for
//! it to fire (a Horn clause) and the switch that turns it off. The table is
//! rendered from the `kitei` bidama by `gen/kitei.b`, so the decision is
//! blue's and this module only reads it.

mod tables;

pub use tables::RULES;

fn row(id: &str) -> Option<&'static (&'static str, &'static [&'static str], &'static str)> {
    RULES.iter().find(|(r, _, _)| *r == id)
}

/// The facts the shipped rule `id` needs, or `None` when no shipped rule has
/// that id.
#[must_use]
pub fn needs(id: &str) -> Option<&'static [&'static str]> {
    row(id).map(|(_, n, _)| *n)
}

/// The variable and value that turn the rule `id` off, or `None` for a rule
/// with no switch or no row.
#[must_use]
pub fn switch(id: &str) -> Option<(&'static str, &'static str)> {
    row(id).and_then(|(_, _, s)| s.split_once('='))
}

/// Whether the rule's switch holds its off value in `read`, the environment
/// a caller reads (the process environment for [`switched_off`]).
#[must_use]
pub fn switched_off_in(id: &str, read: &dyn Fn(&str) -> Option<String>) -> bool {
    switch(id).is_some_and(|(var, off)| read(var).is_some_and(|v| v == off))
}

/// Whether the rule `id` is switched off in this process's environment.
#[must_use]
pub fn switched_off(id: &str) -> bool {
    switched_off_in(id, &|var| std::env::var(var).ok())
}

/// The facts the rule `id` needs that `held` lacks; empty when it would fire.
/// A rule with no row lacks everything, so it never fires.
#[must_use]
pub fn missing(id: &str, held: &[&str]) -> Vec<&'static str> {
    match needs(id) {
        Some(n) => n.iter().copied().filter(|f| !held.contains(f)).collect(),
        None => vec!["a shipped rule"],
    }
}

/// Whether the rule `id` fires on a definition whose facts are `held`: it is
/// shipped, not switched off, and every fact it needs is held.
#[must_use]
pub fn fires(id: &str, held: &[&str]) -> bool {
    needs(id).is_some() && !switched_off(id) && missing(id, held).is_empty()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_rendered_table_is_the_registry_shipped_rules() {
        let ids: Vec<&str> = RULES.iter().map(|(id, _, _)| *id).collect();
        assert_eq!(
            ids,
            [
                "R1", "R2", "R3", "R4", "R5", "R7", "R8", "R9", "R10", "R12", "R13", "R14", "R15",
                "R16", "R17", "R18"
            ]
        );
        assert_eq!(needs("R2"), Some(&["pure", "self_overlapping"][..]));
        assert_eq!(switch("R4"), Some(("BLUE_FOLD", "off")));
        assert_eq!(switch("R9"), None);
        assert_eq!(needs("R11"), None);
    }

    #[test]
    fn a_rule_fires_on_its_whole_body_and_names_what_it_lacks() {
        assert!(missing("R2", &["pure", "self_overlapping", "typed"]).is_empty());
        assert_eq!(missing("R2", &["self_overlapping"]), ["pure"]);
        assert_eq!(missing("R6", &["proven_types"]), ["a shipped rule"]);
        assert!(!fires("R6", &["proven_types"]));
    }

    #[test]
    fn a_switch_turns_its_rule_off_only_at_its_off_value() {
        let env =
            |want: &'static str| move |var: &str| (var == "BLUE_INDEX").then(|| want.to_string());
        assert!(switched_off_in("R10", &env("off")));
        assert!(!switched_off_in("R10", &env("on")));
        assert!(!switched_off_in("R4", &env("off")));
        assert!(!switched_off_in("R9", &env("off")));
    }
}
