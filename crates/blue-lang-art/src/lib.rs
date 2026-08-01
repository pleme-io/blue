//! blue's mark, wordmark, and theme.
//!
//! # The mark is the blueshift ramp: `░▒▓█`
//!
//! blue's central ratified metaphor is **blueshift** — the wave that shifts with
//! the author across tatara-lisp and Rust as a program is written
//! (`theory/BLUE.md` §V.20). A spectral shift toward blue *is* a compression of
//! light toward one end of a band, and `░▒▓█` is exactly that: four cells of
//! increasing density resolving to solid.
//!
//! katsuji's docs warn that `░▒▓` "read as fuzz at cell size; reach for it
//! deliberately, not for 'texture'." This is the deliberate case — **the
//! gradient is the meaning, not decoration.** Read left to right it is the
//! language's whole thesis in four cells: loose, then denser, then locked.
//!
//! Every glyph is a [`Crisp`], so the mark cannot name a shape mado will not
//! draw. That is the same reason mado's own wordmark is typed rather than a
//! string literal — and the reason this composition lives here rather than in
//! katsuji, which owns *how a styled line becomes bytes* and explicitly not
//! layout.
//!
//! # The theme is `irodori`'s Nord, never a local copy
//!
//! Colours come from [`irodori`], the fleet's Nord palette. blue does not carry
//! its own hex values: the fleet rule is that an app's visual default *derives*
//! from the shared tokens so one edit propagates, and copying another app's
//! palette is named as the anti-pattern. What blue chooses is which Nord *roles*
//! to bind — see [`Theme`].

use irodori::{Color, NordPalette, NORD};
use katsuji::{Attr, Crisp, Ink, Line, Piece};

/// The mark, as the four glyphs it is made of.
///
/// A typed array rather than a string so the ramp cannot silently gain a fifth
/// cell or lose its order — the shape *is* the meaning, and `"░▒▓█"` as a
/// literal would let either happen unnoticed.
pub const RAMP: [Crisp; 4] = [
    Crisp::ShadeLight,
    Crisp::ShadeMedium,
    Crisp::ShadeDark,
    Crisp::Full,
];

/// The mark as text, for contexts with no styled-line renderer — a README, a
/// commit message, a browser tab.
#[must_use]
pub fn mark() -> String {
    RAMP.iter().map(|g| g.ch()).collect()
}

/// blue's Nord bindings.
///
/// ## Why `nord10` leads and `nord8` accents
///
/// Nord's Frost band (`nord7..nord10`) runs from teal to deep blue. The fleet's
/// established accent is `nord8` frost-cyan — katsuji names it for links, prompt
/// marks and scrollbars, and every fleet app inherits it.
///
/// blue keeps that accent, because diverging would make one app's cyan mean
/// something different from every other app's, and binds **`nord10`
/// (`#5E81AC`), the deep blue, as its own primary**. A language called blue
/// whose primary was a cyan would be a name that does not match its own output.
/// So: `nord10` is the identity, `nord8` stays the shared interaction colour.
/// The distinction is the point — identity and interaction are different roles.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Theme {
    /// blue's own colour — Nord `nord10`, the deep frost blue.
    pub primary: Color,
    /// The fleet's shared accent — Nord `nord8`, frost cyan. Not blue's to
    /// change.
    pub accent: Color,
    /// Nord `nord0`, Polar Night.
    pub background: Color,
    /// Nord `nord6`, Snow Storm.
    pub foreground: Color,
    /// Nord `nord3`, for de-emphasis.
    pub dim: Color,
}

/// The Nord indices blue binds. Named so a reader can check the choice against
/// the palette without counting positions.
const NORD_PRIMARY: usize = 10;
const NORD_ACCENT: usize = 8;
const NORD_BACKGROUND: usize = 0;
const NORD_FOREGROUND: usize = 6;
const NORD_DIM: usize = 3;

impl Theme {
    /// blue's theme, derived from a Nord palette.
    ///
    /// Takes the palette rather than reading the global so a consumer can pass a
    /// customised one and still get blue's *role bindings* — the thing blue
    /// owns — applied to it.
    #[must_use]
    pub fn from_palette(p: &NordPalette) -> Self {
        // `get` returns Option; a missing index would mean the palette is not
        // Nord. Falling back to the canonical NORD keeps this total without
        // inventing a colour.
        let at = |i: usize| p.get(i).or_else(|| NORD.get(i)).unwrap_or(Color::new(0, 0, 0));
        Self {
            primary: at(NORD_PRIMARY),
            accent: at(NORD_ACCENT),
            background: at(NORD_BACKGROUND),
            foreground: at(NORD_FOREGROUND),
            dim: at(NORD_DIM),
        }
    }

    /// blue's theme over the canonical fleet Nord.
    #[must_use]
    pub fn fleet() -> Self {
        Self::from_palette(&NORD)
    }
}

impl Default for Theme {
    fn default() -> Self {
        Self::fleet()
    }
}

/// The wordmark: the blueshift ramp, the name, and the running version.
///
/// `version` is passed in, never written here — a literal would be a second
/// place to update, and mado records that exact drift shipping a `0.1.0`
/// wordmark against a `0.1.98` binary.
#[must_use]
pub fn wordmark(version: &str) -> Vec<Line> {
    // `Ink::Blue` is katsuji's name for the frost blue under Nord — the ANSI
    // slot blue's `nord10` primary occupies in a Nord terminal. Using the ink
    // rather than a truecolor escape means the mark honours a user's palette
    // instead of overriding it.
    let ramp = |g: Crisp| Piece::glyph(g).ink(Ink::Blue);

    vec![
        // The ramp, then the name. One accent slot, gaps doing the spacing —
        // the restraint mado's banner establishes.
        Line::new()
            .piece(ramp(Crisp::ShadeLight))
            .piece(ramp(Crisp::ShadeMedium))
            .piece(ramp(Crisp::ShadeDark))
            .piece(ramp(Crisp::Full))
            .piece(Piece::text("  blue  ").ink(Ink::BrightWhite).attr(Attr::Bold))
            .piece(Piece::text(version).ink(Ink::BrightBlack)),
        // A single rule under it, in the crisp light set. Not `━` heavy and not
        // `╌` dashed: neither has renderer geometry.
        Line::new().piece(Piece::glyphs(Crisp::Horizontal, 20).ink(Ink::BrightBlack)),
        Line::new().piece(
            Piece::text("a Ruby/Elixir surface on tatara-lisp and Rust")
                .ink(Ink::BrightBlack),
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The mark is the ramp, in order, and nothing else.
    #[test]
    fn the_mark_is_the_blueshift_ramp() {
        assert_eq!(mark(), "░▒▓█");
    }

    /// **The ramp must increase.** A shift that does not monotonically compress
    /// is not a shift — and a reordered array would still render four glyphs, so
    /// only checking the order catches it.
    #[test]
    fn the_ramp_increases_in_density() {
        assert_eq!(
            RAMP,
            [
                Crisp::ShadeLight,
                Crisp::ShadeMedium,
                Crisp::ShadeDark,
                Crisp::Full
            ],
            "the ramp is the meaning; its order is not cosmetic"
        );
    }

    /// **Every glyph in the mark is crisp.** `Crisp` has no variant for a glyph
    /// mado cannot draw, so this is enforced by the type — asserted anyway
    /// because the *point* of typing it is easy to undo by switching to a
    /// string.
    #[test]
    fn every_mark_glyph_has_renderer_geometry() {
        for g in RAMP {
            assert!(
                Crisp::ALL.contains(&g),
                "{g:?} must be in the crisp set — the set is what guarantees it renders"
            );
        }
    }

    // ---- theme ----------------------------------------------------------

    /// **blue's primary is Nord's deep blue, not the fleet cyan.** A language
    /// called blue whose primary was a cyan would be a name that does not match
    /// its own output.
    #[test]
    fn the_primary_is_nord10_deep_blue() {
        let t = Theme::fleet();
        assert_eq!(t.primary, Color::new(0x5E, 0x81, 0xAC), "nord10");
    }

    /// **And the shared accent is unchanged.** Diverging would make blue's cyan
    /// mean something different from every other fleet app's.
    #[test]
    fn the_accent_is_the_fleets_nord8_frost_cyan() {
        let t = Theme::fleet();
        assert_eq!(t.accent, Color::new(0x88, 0xC0, 0xD0), "nord8");
        assert_ne!(
            t.primary, t.accent,
            "identity and interaction are different roles and must be different colours"
        );
    }

    /// Every colour comes from the palette — blue carries no hex of its own.
    /// This is the drift test: if someone inlines a literal, it stops matching
    /// the palette lookup.
    #[test]
    fn every_theme_colour_comes_from_the_nord_palette() {
        let t = Theme::fleet();
        let nord: Vec<Color> = (0..16).filter_map(|i| NORD.get(i)).collect();
        for (name, c) in [
            ("primary", t.primary),
            ("accent", t.accent),
            ("background", t.background),
            ("foreground", t.foreground),
            ("dim", t.dim),
        ] {
            assert!(
                nord.contains(&c),
                "{name} = {c:?} is not a Nord colour — blue must not carry its own hex"
            );
        }
    }

    /// The bindings follow a passed palette, so blue owns the *roles* and not
    /// the values.
    ///
    /// `nord10` lives at `frost[3]` — the Frost band is `nord7..nord10`, so the
    /// band-relative index is 3, not 10. Writing the flat index here would have
    /// been an out-of-bounds panic rather than a wrong colour, which is at least
    /// loud.
    #[test]
    fn the_theme_follows_a_customised_palette() {
        let mut custom = NORD;
        custom.frost[3] = Color::new(1, 2, 3);
        assert_eq!(
            Theme::from_palette(&custom).primary,
            Color::new(1, 2, 3),
            "a consumer's palette must drive the value; blue supplies the role"
        );
    }

    // ---- wordmark -------------------------------------------------------

    #[test]
    fn the_wordmark_carries_the_name_the_mark_and_the_version() {
        let lines = wordmark("9.9.9");
        let rendered: String = lines.iter().map(Line::render).collect();
        assert!(rendered.contains("blue"), "the name: {rendered:?}");
        assert!(rendered.contains("9.9.9"), "the version: {rendered:?}");
        for g in RAMP {
            assert!(
                rendered.contains(g.ch()),
                "the ramp glyph {g:?} must appear: {rendered:?}"
            );
        }
    }

    /// **The version is never hardcoded.** mado shipped a `0.1.0` wordmark
    /// against a `0.1.98` binary because a literal was a second place to update.
    #[test]
    fn the_wordmark_takes_its_version_from_the_caller() {
        let a: String = wordmark("1.2.3").iter().map(Line::render).collect();
        let b: String = wordmark("4.5.6").iter().map(Line::render).collect();
        assert!(a.contains("1.2.3") && !a.contains("4.5.6"));
        assert!(b.contains("4.5.6") && !b.contains("1.2.3"));
    }
}
