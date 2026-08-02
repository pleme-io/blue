//! blue's mark, wordmark, and theme.
//!
//! # The mark is a COLOUR shift across Nord's Frost band
//!
//! blue's central ratified metaphor is **blueshift** — the wave that shifts with
//! the author across tatara-lisp and Rust as a program is written
//! (`theory/BLUE.md` §V.20). A blueshift is a shift in **colour**, so the mark
//! is four solid cells walking Nord's own Frost band toward blue:
//!
//! ```text
//! ████   nord7 → nord8 → nord9 → nord10
//!        teal    cyan    light   deep blue
//! ```
//!
//! ## What this replaced, and why
//!
//! The first version was `░▒▓█` — a *density* ramp, every cell painted the same
//! `Ink::Blue`. It was wrong twice over, and the operator spotted it immediately
//! as "a blue box":
//!
//! - **It rendered a shift with nothing shifting.** One flat colour across four
//!   cells varies only density, which is not what a blueshift is.
//! - **`░▒▓` read as fuzz.** katsuji's docs say so in as many words — "reach for
//!   it deliberately, not for 'texture'" — and the first draft quoted that
//!   warning and then argued past it on the grounds that the gradient *was* the
//!   meaning. Intent does not make an illegible glyph legible. Four dither cells
//!   ending in `█`, all one colour, look like a blue box because that is what
//!   they are.
//!
//! Solid blocks are legible at any size, and the colour does the work the shape
//! was failing to do.
//!
//! # No truecolor, deliberately
//!
//! The Frost tones are named by their **ANSI slot**, never by hex. katsuji has no
//! `Ink::Rgb` and no `from_hex` on purpose: a literal `\x1b[38;2;…m` "pins a
//! colour that stops tracking" the user's theme. Naming the slot means the mark
//! renders in *the reader's* Nord, and follows them if they retheme.
//!
//! # The theme is `irodori`'s Nord, never a local copy
//!
//! Colours come from [`irodori`], the fleet's Nord palette. blue carries no hex:
//! the fleet rule is that an app's visual default *derives* from the shared
//! tokens so one edit propagates, and copying another app's palette is the named
//! anti-pattern. What blue chooses is which Nord *roles* to bind — see [`Theme`].

use irodori::{Color, NordPalette, NORD};
use katsuji::{Attr, Crisp, Ink, Line, Piece};

/// The mark: four solid cells, one per Frost tone, walking toward blue.
///
/// A typed array rather than a string of escapes, so the ramp cannot silently
/// lose a step or reorder — the *progression* is the meaning.
///
/// Named by ANSI slot, not hex, so the mark tracks the reader's theme. Under
/// Nord these are `nord7 → nord8 → nord9 → nord10`; mado pins `ansi[4]` to
/// `#5E81AC` (nord10) and `ansi[6]` to `#88C0D0` (nord8), which is the fleet's
/// own binding rather than upstream Nord's.
pub const SHIFT: [Ink; 4] = [Ink::BrightCyan, Ink::Cyan, Ink::BrightBlue, Ink::Blue];

/// The glyph every cell of the mark uses. Solid — no dither.
pub const CELL: Crisp = Crisp::Full;

/// The mark as plain text, for contexts with no colour — a README, a commit
/// message, a browser tab.
///
/// **The colour is the meaning, so plain text loses it.** This returns the
/// shape only; anywhere colour is available, use [`mark_line`].
#[must_use]
pub fn mark() -> String {
    core::iter::repeat_n(CELL.ch(), SHIFT.len()).collect()
}

/// The mark as a styled line — the real thing.
#[must_use]
pub fn mark_line() -> Line {
    SHIFT
        .iter()
        .fold(Line::new(), |l, ink| l.piece(Piece::glyph(CELL).ink(*ink)))
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
        let at = |i: usize| {
            p.get(i)
                .or_else(|| NORD.get(i))
                .unwrap_or(Color::new(0, 0, 0))
        };
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
    vec![
        // The shift, then the name. One accent slot, gaps doing the spacing —
        // the restraint mado's banner establishes.
        SHIFT
            .iter()
            .fold(Line::new(), |l, ink| l.piece(Piece::glyph(CELL).ink(*ink)))
            .piece(
                Piece::text("  blue  ")
                    .ink(Ink::BrightWhite)
                    .attr(Attr::Bold),
            )
            .piece(Piece::text(version).ink(Ink::BrightBlack)),
        // A single rule under it, in the crisp light set. Not `━` heavy and not
        // `╌` dashed: neither has renderer geometry.
        Line::new().piece(Piece::glyphs(Crisp::Horizontal, 20).ink(Ink::BrightBlack)),
        Line::new().piece(
            Piece::text("a Ruby/Elixir surface on tatara-lisp and Rust").ink(Ink::BrightBlack),
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The mark is four solid cells — no dither.
    #[test]
    fn the_mark_is_four_solid_cells() {
        assert_eq!(mark(), "████");
    }

    /// **No dither glyph may appear in the mark.**
    ///
    /// The first version was `░▒▓█`, which katsuji's own docs warn "read as fuzz
    /// at cell size". It shipped, and the operator read it as a blue box. This
    /// names the mistake so it cannot come back.
    #[test]
    fn the_mark_uses_no_dither_glyph() {
        for bad in [Crisp::ShadeLight, Crisp::ShadeMedium, Crisp::ShadeDark] {
            assert!(
                !mark().contains(bad.ch()),
                "{bad:?} reads as fuzz at cell size — the mark must be solid"
            );
        }
    }

    /// **The colour must actually shift.** This is the whole mark: a blueshift
    /// with one flat colour is not a shift at all, which is precisely what the
    /// first version shipped.
    #[test]
    fn every_cell_of_the_shift_is_a_different_ink() {
        let mut seen: Vec<Ink> = Vec::new();
        for ink in SHIFT {
            assert!(
                !seen.contains(&ink),
                "{ink:?} repeats — a shift with a repeated colour is not shifting"
            );
            seen.push(ink);
        }
        assert_eq!(seen.len(), 4);
    }

    /// **And it must shift toward BLUE**, across Nord's Frost band in order:
    /// nord7 teal → nord8 cyan → nord9 light → nord10 deep. Reversed, it is a
    /// redshift.
    #[test]
    fn the_shift_walks_the_frost_band_toward_blue() {
        assert_eq!(
            SHIFT,
            [Ink::BrightCyan, Ink::Cyan, Ink::BrightBlue, Ink::Blue],
            "the direction is the meaning: toward blue, not away from it"
        );
        assert_eq!(
            *SHIFT.last().expect("non-empty"),
            Ink::Blue,
            "it ends on blue"
        );
    }

    /// **Named by ANSI slot, never by hex.** katsuji has no `Ink::Rgb` on
    /// purpose — a truecolor literal pins a colour that stops tracking the
    /// reader's theme. Rendering must therefore emit plain SGR.
    #[test]
    fn the_mark_emits_no_truecolor_escape() {
        let rendered = mark_line().render();
        assert!(
            !rendered.contains("38;2;"),
            "a truecolor escape would stop tracking the reader's theme: {rendered:?}"
        );
    }

    /// The styled mark carries four distinct colour runs.
    #[test]
    fn the_styled_mark_paints_four_runs() {
        let rendered = mark_line().render();
        for ink in SHIFT {
            let param = match ink {
                Ink::BrightCyan => "96",
                Ink::Cyan => "36",
                Ink::BrightBlue => "94",
                Ink::Blue => "34",
                other => panic!("unexpected ink in SHIFT: {other:?}"),
            };
            assert!(
                rendered.contains(param),
                "expected SGR {param} for {ink:?} in {rendered:?}"
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
        assert!(
            rendered.contains(CELL.ch()),
            "the mark must appear: {rendered:?}"
        );
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
