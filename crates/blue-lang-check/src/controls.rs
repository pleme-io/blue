//! The compliance controls a test declares: one table from a control keyword
//! to the control id an OSCAL catalog and tameshi name it by.
//!
//! `test "…", {satisfies: [:nist_ac_6]}` declares NIST SP 800-53 Rev. 5 AC-6,
//! which a tameshi receipt writes `NIST_SP_800_53R5_AC_6`. A keyword is
//! `<catalog>_<family>_<number>`, with `_<enhancement>` for a control
//! enhancement (`:nist_ac_6_1` is AC-6(1), `NIST_SP_800_53R5_AC_6_1`).
//!
//! [`oscal_id`] is the one mapping: the check stage refuses a keyword it does
//! not map (B0069), `blue test --facts` writes what it answers, and any other
//! door that names a control (a Bluefile word) calls it rather than spelling
//! the id itself.

/// One control catalog a keyword may name.
#[derive(Clone, Copy, Debug)]
pub struct Catalog {
    /// The keyword's first word: `nist`.
    pub prefix: &'static str,
    /// The id's first part: `NIST_SP_800_53R5`.
    pub id: &'static str,
    /// The catalog as a person names it.
    pub title: &'static str,
    /// Its control families, lowercase, as the keyword writes them.
    pub families: &'static [&'static str],
}

/// Every catalog a test may declare a control of.
pub const CATALOGS: &[Catalog] = &[Catalog {
    prefix: "nist",
    id: "NIST_SP_800_53R5",
    title: "NIST SP 800-53 Rev. 5",
    families: &[
        "ac", "at", "au", "ca", "cm", "cp", "ia", "ir", "ma", "mp", "pe", "pl", "pm", "ps", "pt",
        "ra", "sa", "sc", "si", "sr",
    ],
}];

fn number(word: &str) -> bool {
    (1..=3).contains(&word.len())
        && word.bytes().all(|b| b.is_ascii_digit())
        && !word.starts_with('0')
}

/// The control id `control` names: `:nist_ac_6` and `nist_ac_6` are
/// `NIST_SP_800_53R5_AC_6`.
///
/// # Errors
///
/// Naming what is wrong and the shape that is right: an unknown catalog
/// (with the ones there are), an unknown family (with its catalog's), or a
/// number that is not one.
pub fn oscal_id(control: &str) -> Result<String, String> {
    let word = control.strip_prefix(':').unwrap_or(control);
    let shape = "a control is `:<catalog>_<family>_<number>`, such as `:nist_ac_6`";
    let parts: Vec<&str> = word.split('_').collect();
    let Some(catalog) = CATALOGS.iter().find(|c| c.prefix == parts[0]) else {
        let known: Vec<&str> = CATALOGS.iter().map(|c| c.prefix).collect();
        return Err(format!(
            "`:{word}` names no catalog blue knows ({}); {shape}",
            known.join(", ")
        ));
    };
    let (family, rest) = match &parts[1..] {
        [family, rest @ ..] => (*family, rest),
        [] => return Err(format!("`:{word}` names no control; {shape}")),
    };
    if !catalog.families.contains(&family) {
        return Err(format!(
            "`{family}` is not a {} family ({}); {shape}",
            catalog.title,
            catalog.families.join(", ")
        ));
    }
    if rest.is_empty() || rest.len() > 2 || !rest.iter().all(|n| number(n)) {
        return Err(format!(
            "`:{word}` needs a control number, and at most an enhancement after it: \
             `:{}_{family}_6`, `:{}_{family}_6_1`",
            catalog.prefix, catalog.prefix
        ));
    }
    let mut id = format!("{}_{}", catalog.id, family.to_ascii_uppercase());
    for n in rest {
        id.push('_');
        id.push_str(n);
    }
    Ok(id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_nist_keyword_maps_to_its_tameshi_control_id() {
        assert_eq!(
            oscal_id(":nist_ac_6").as_deref(),
            Ok("NIST_SP_800_53R5_AC_6")
        );
        assert_eq!(
            oscal_id("nist_cm_7").as_deref(),
            Ok("NIST_SP_800_53R5_CM_7")
        );
        assert_eq!(
            oscal_id("nist_ac_6_1").as_deref(),
            Ok("NIST_SP_800_53R5_AC_6_1")
        );
    }

    #[test]
    fn every_mapped_id_is_a_tameshi_control_id() {
        for catalog in CATALOGS {
            for family in catalog.families {
                let id = oscal_id(&format!("{}_{family}_12_3", catalog.prefix)).expect("maps");
                assert!(id.starts_with(|c: char| c.is_ascii_uppercase()), "{id}");
                assert!(
                    id.bytes()
                        .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_'),
                    "{id}"
                );
            }
        }
    }

    #[test]
    fn a_keyword_outside_the_table_is_refused_naming_what_is_known() {
        for (bad, says) in [
            ("iso_a_5", "nist"),
            ("nist_zz_1", "ac, at"),
            ("nist_ac", "control number"),
            ("nist_ac_06", "control number"),
            ("nist_ac_6_1_2", "control number"),
            ("nist", "names no control"),
            ("", "names no catalog"),
        ] {
            let err = oscal_id(bad).expect_err(bad);
            assert!(err.contains(says), "{bad}: {err}");
        }
    }
}
