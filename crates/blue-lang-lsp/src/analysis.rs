//! The analysis core — **transport-free**.
//!
//! Nothing here knows about JSON-RPC, stdio, or LSP. It takes source text and
//! returns diagnostics, formatting edits and hovers, as plain Rust types.
//!
//! That split is not tidiness. An analysis core reachable only through a
//! protocol can be tested only by speaking that protocol, so its tests become
//! slow, awkward, and few — and the editor experience is exactly what nobody
//! wants to be under-tested. Everything below is a direct function call.
//!
//! ## Positions
//!
//! blue's lexer carries byte offsets. LSP speaks UTF-16 code units on lines.
//! The conversion lives in [`LineIndex`] and is the one place that knows about
//! it — a per-call conversion is how an editor ends up underlining the wrong
//! characters in a file with any non-ASCII in it.

use blue_lang_syntax::Span;

/// Severity, in LSP's numbering so the shim does not have to translate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
}

/// A zero-based line and UTF-16 character offset — LSP's coordinates.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Position {
    pub line: u32,
    pub character: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Range {
    pub start: Position,
    pub end: Position,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Diagnostic {
    pub range: Range,
    pub severity: Severity,
    pub message: String,
    /// Which analysis produced it, so a reader can tell a parse failure from a
    /// type error without parsing the message.
    pub source: &'static str,
}

/// Byte offsets ↔ LSP positions.
///
/// Built once per analysis. Line starts are cached because a diagnostic list
/// needs many conversions over one document, and a linear scan per conversion
/// makes a large file's diagnostics quadratic.
pub struct LineIndex {
    /// Byte offset of the start of each line.
    line_starts: Vec<usize>,
    text: String,
}

impl LineIndex {
    pub fn new(text: &str) -> Self {
        let mut line_starts = vec![0];
        for (i, b) in text.bytes().enumerate() {
            if b == b'\n' {
                line_starts.push(i + 1);
            }
        }
        Self {
            line_starts,
            text: text.to_string(),
        }
    }

    /// Byte offset → position, counting **UTF-16 code units** within the line.
    ///
    /// Not bytes and not chars. LSP specifies UTF-16, and a client given byte
    /// offsets underlines the wrong span in any file containing non-ASCII —
    /// silently, and only for the users who have such files.
    pub fn position(&self, offset: usize) -> Position {
        let mut offset = offset.min(self.text.len());
        // Snap DOWN to a char boundary before slicing.
        //
        // Clamping to `len()` is not enough: a byte offset can land INSIDE a
        // multi-byte character, and `self.text[line_start..offset]` below then
        // panics with "byte index N is not a char boundary". Measured
        // 2026-08-01: `analyse("🔥🔥🔥")` aborted here at offset 1.
        //
        // The irony is the reason this is worth a comment — this function
        // exists to compute UTF-16 offsets correctly FOR non-ASCII files, and
        // it was the one place that crashed on them. Offsets arrive from
        // parser error spans, which are byte indices into a buffer the user may
        // have half-typed a character into, so mid-codepoint is a normal
        // arrival, not a corrupt one.
        //
        // Snapping down (rather than up) keeps the reported position inside the
        // character the offset pointed at, which is where an editor should
        // underline. `str::floor_char_boundary` would say this in one call but
        // is still unstable.
        while offset > 0 && !self.text.is_char_boundary(offset) {
            offset -= 1;
        }
        let line = match self.line_starts.binary_search(&offset) {
            Ok(exact) => exact,
            Err(next) => next - 1,
        };
        let line_start = self.line_starts[line];
        let character = self.text[line_start..offset]
            .chars()
            .map(|c| c.len_utf16() as u32)
            .sum();
        Position {
            line: line as u32,
            character,
        }
    }

    /// Span → range.
    ///
    /// A **synthetic** span becomes the whole document rather than a position.
    /// `Span::synthetic()` is `usize::MAX..usize::MAX`, which [`Self::position`]
    /// would dutifully clamp to the last byte of the file — a precise-looking
    /// answer that is a lie about a node with no source origin. Nothing blue's
    /// parser emits is synthetic, so this arm exists for the macro-expanded and
    /// cross-file trees that will reach here later; the whole document is the
    /// honest statement "somewhere in this file, and I cannot say where".
    ///
    /// It is deliberately NOT `Range::default()`. Line 0, column 0 is a real
    /// position — it names the first character — and reporting an unknown
    /// location as a known one is precisely the bug that made every blue type
    /// error appear at the top of the file.
    pub fn range(&self, span: Span) -> Range {
        if span.is_synthetic() {
            return self.whole_document();
        }
        Range {
            start: self.position(span.start),
            end: self.position(span.end),
        }
    }

    /// Position → byte offset. Needed for hover, which arrives as a position.
    pub fn offset(&self, pos: Position) -> usize {
        let line = pos.line as usize;
        if line >= self.line_starts.len() {
            return self.text.len();
        }
        let line_start = self.line_starts[line];
        let line_end = self
            .line_starts
            .get(line + 1)
            .copied()
            .unwrap_or(self.text.len());
        let mut utf16 = 0u32;
        for (byte_off, c) in self.text[line_start..line_end].char_indices() {
            if utf16 >= pos.character {
                return line_start + byte_off;
            }
            utf16 += c.len_utf16() as u32;
        }
        line_end
    }

    pub fn whole_document(&self) -> Range {
        Range {
            start: Position::default(),
            end: self.position(self.text.len()),
        }
    }
}

/// Everything the editor gets for one document.
#[derive(Clone, Debug, Default)]
pub struct Analysis {
    pub diagnostics: Vec<Diagnostic>,
    /// Canonical formatting, or `None` when the source does not parse.
    ///
    /// `None` rather than the original text: returning the input unchanged
    /// would make "format on save" appear to succeed on a file it could not
    /// format.
    pub formatted: Option<String>,
    /// Typed declarations found, for hover and for the status line.
    pub declarations: Vec<Declaration>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Declaration {
    pub name: String,
    /// The signature as blue source, e.g. `def add(a: Int, b: Int) -> Int`.
    pub signature: String,
    pub range: Range,
}

/// Analyse one document.
///
/// **Parse failures suppress the later stages rather than compounding.** A file
/// mid-edit is unparseable most of the time, and a type checker run on a
/// half-tree produces cascades of errors about code the author has not written
/// yet — which trains people to ignore the diagnostics.
///
/// That is the *preference*; there is also no choice. blue's parser performs no
/// error recovery — `parse_program_tree` returns `Result<Vec<Spanned>, _>` and
/// bails on the first failure — so on a parse error there is no half-tree to
/// check even if we wanted one. Reporting parse AND type diagnostics together
/// is not a matter of deleting the early return here; it needs the parser to
/// synthesize error nodes and keep going, which it does not do. Stated so the
/// next reader does not go looking for the `if` to remove.
pub fn analyse(src: &str) -> Analysis {
    let index = LineIndex::new(src);
    let mut out = Analysis::default();

    // `parse_program_tree`, NOT `parse_program`.
    //
    // The tree carries a span on every node, and the spanless parse does not.
    // While the checker walked `Sexp`, a type diagnostic arrived here with no
    // position at all and was attached to `Range::default()` — line 0, column 0
    // — so an error on line 200 of a file underlined its first character while
    // the parse error beside it pointed at the right byte. Reaching for
    // `parse_program` here is how that comes back.
    let forms = match blue_lang_syntax::parse_program_tree(src) {
        Ok(f) => f,
        Err(e) => {
            out.diagnostics.push(Diagnostic {
                range: index.range(e.span),
                severity: Severity::Error,
                message: e.message.clone(),
                source: "parse",
            });
            return out;
        }
    };

    for d in blue_lang_check::check_program(&forms).diagnostics {
        out.diagnostics.push(Diagnostic {
            range: index.range(d.span),
            severity: Severity::Error,
            message: d.message,
            source: "types",
        });
    }

    // `format_source_lossless`, not `format_forms`. Comments are not in the
    // tree, so a formatter that starts from parsed forms cannot emit them —
    // `format_forms` on `spec/bindings.b` returned 707 bytes for 1010 in and
    // **deleted all six comments**. Measured, not inferred.
    //
    // This is the same defect `fmt --write` had, fixed there and not here,
    // because the two paths reached the formatter through different doors. An
    // editor is the worse place for it: `textDocument/formatting` replaces the
    // whole buffer with this string, so every comment in the file vanished on
    // format, in a tool whose whole promise is that it is safe to run.
    //
    // Falling back to the lossy render on error would reintroduce exactly that,
    // so a document that cannot be losslessly formatted offers no formatting.
    out.formatted = blue_lang_fmt::format_source_lossless(src).ok();
    out.declarations = declarations(&forms, &index);
    out
}

fn declarations(forms: &[blue_lang_syntax::Spanned], index: &LineIndex) -> Vec<Declaration> {
    let mut out = Vec::new();
    for form in forms {
        let Some(items) = form.as_list() else {
            continue;
        };
        let Some(head) = items.first().and_then(|h| h.as_symbol()) else {
            continue;
        };
        let name = match (head, items.get(1)) {
            ("define" | "define-typed", Some(sig)) => {
                match sig.as_list().and_then(|s| s.first()?.as_symbol()) {
                    Some(n) => n.to_string(),
                    None => continue,
                }
            }
            ("defmacro", Some(n)) => match n.as_symbol() {
                Some(n) => n.to_string(),
                None => continue,
            },
            _ => continue,
        };
        // The signature is the FORMATTER's first line. Reusing it means hover
        // and the file cannot disagree about how a signature is spelled — the
        // same reason the test framework renders assertions through it.
        let rendered = blue_lang_fmt::format_forms(std::slice::from_ref(&form.to_sexp()));
        let signature = rendered.lines().next().unwrap_or_default().to_string();
        out.push(Declaration {
            name,
            signature,
            // The declaration's OWN range, not `whole_document()`.
            //
            // It was the whole document, for the same reason type diagnostics
            // were at line 0: nothing downstream had a span to offer. A
            // document-wide range is what makes a symbol list unusable —
            // "go to definition" lands on byte 0 for every name in the file.
            range: index.range(form.span),
        });
    }
    out
}

/// The declaration whose name appears at `pos`, for hover.
pub fn hover(src: &str, pos: Position) -> Option<String> {
    let index = LineIndex::new(src);
    let offset = index.offset(pos);
    let word = word_at(src, offset)?;
    analyse(src)
        .declarations
        .into_iter()
        .find(|d| d.name == word)
        .map(|d| d.signature)
}

fn word_at(src: &str, offset: usize) -> Option<String> {
    let is_word = |c: char| c.is_alphanumeric() || c == '_' || c == '-' || c == '?' || c == '!';
    if offset > src.len() {
        return None;
    }
    let start = src[..offset]
        .char_indices()
        .rev()
        .take_while(|(_, c)| is_word(*c))
        .last()
        .map_or(offset, |(i, _)| i);
    let end = src[offset..]
        .char_indices()
        .take_while(|(_, c)| is_word(*c))
        .last()
        .map_or(offset, |(i, c)| offset + i + c.len_utf8());
    let word = &src[start..end];
    if word.is_empty() {
        None
    } else {
        Some(word.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PROGRAM: &str = "def add(a: Int, b: Int) -> Int\n  a + b\nend\nadd(1, 2)";

    #[test]
    fn a_clean_document_has_no_diagnostics_and_formats() {
        let a = analyse(PROGRAM);
        assert!(a.diagnostics.is_empty(), "{:?}", a.diagnostics);
        assert!(a.formatted.is_some());
    }

    /// **Formatting a document must not delete its comments.**
    ///
    /// `analyse` used to call `format_forms`, which renders the parsed tree —
    /// and comments are deliberately not in the tree, so it could not emit
    /// them. On `spec/bindings.b` that was 1010 bytes in, 707 out, six
    /// comments to zero, delivered to the editor as a whole-buffer replace.
    ///
    /// The count is asserted, not just non-emptiness: a formatter that dropped
    /// five of six comments would satisfy "some comments survive".
    #[test]
    fn formatting_preserves_every_comment() {
        let src = "# header one\n# header two\nx = 1\n\n# about add\ndef add(a, b)\n  a + b\nend\n";
        let formatted = analyse(src).formatted.expect("clean document formats");

        let count = |s: &str| {
            s.lines()
                .filter(|l| l.trim_start().starts_with('#'))
                .count()
        };
        assert_eq!(
            count(&formatted),
            count(src),
            "comments were lost.\n--- in ---\n{src}\n--- out ---\n{formatted}"
        );
        for comment in ["# header one", "# header two", "# about add"] {
            assert!(
                formatted.contains(comment),
                "`{comment}` is missing from:\n{formatted}"
            );
        }
    }

    /// The LSP and the CLI must format through the same door.
    ///
    /// They diverged once: `fmt --write` learned to re-interleave comments and
    /// `analyse` kept the lossy renderer, so the same file formatted two
    /// different ways depending on which tool you used. Asserting byte
    /// equality against the CLI's own entry point makes a second divergence a
    /// red build rather than a bug report from someone who lost their comments.
    #[test]
    fn the_editor_and_the_cli_format_identically() {
        let src = "# keep me\nx    =    1\ndef add(a,b)\n  a+b\nend\n";
        assert_eq!(
            analyse(src).formatted.as_deref(),
            blue_lang_fmt::format_source_lossless(src).ok().as_deref(),
            "the editor and the CLI disagree about how this file should look"
        );
    }

    /// A parse error is reported at its span, tagged `parse`.
    #[test]
    fn a_parse_error_is_reported_with_a_position() {
        let a = analyse("def add(\n");
        assert_eq!(a.diagnostics.len(), 1);
        assert_eq!(a.diagnostics[0].source, "parse");
        assert_eq!(a.diagnostics[0].severity, Severity::Error);
    }

    /// **An unparseable document must not also be formatted.** Returning the
    /// input unchanged would make format-on-save appear to succeed on a file it
    /// could not format.
    #[test]
    fn an_unparseable_document_yields_no_formatting() {
        assert!(analyse("def add(").formatted.is_none());
    }

    /// **A parse error must not produce type errors too.** A file mid-edit is
    /// unparseable most of the time, and cascading errors about code the author
    /// has not written yet trains people to ignore diagnostics.
    #[test]
    fn a_parse_error_does_not_cascade_into_type_errors() {
        let a = analyse("def bad(a: Int) -> Str\n  a\n");
        assert!(
            a.diagnostics.iter().all(|d| d.source == "parse"),
            "only the parse failure should be reported: {:?}",
            a.diagnostics
        );
    }

    #[test]
    fn a_type_error_is_reported_and_tagged() {
        let a = analyse("def bad(a: Int) -> Str\n  a\nend");
        assert_eq!(a.diagnostics.len(), 1, "{:?}", a.diagnostics);
        assert_eq!(a.diagnostics[0].source, "types");
        assert!(a.diagnostics[0].message.contains("Str"));
    }

    // ---- type diagnostics have REAL positions ---------------------------
    //
    // Until 2026-08-12 `blue_lang_check::Diagnostic` carried only a message, so
    // every type diagnostic here was emitted with `Range::default()` — line 0,
    // character 0 — and an author with a type error on line 200 got a squiggle
    // under the first character of their file. The parse-error path beside it
    // had a real span the whole time, which is what made the asymmetry visible.
    //
    // Every fixture below puts its error somewhere other than line 0, and every
    // expected position is counted by hand from the fixture rather than read
    // back from the analysis. A gate whose fixture had its error at byte 0 would
    // pass against the exact bug.

    /// A type error is reported at ITS OWN position, not at the top of the file.
    ///
    /// RED RUN (2026-08-12): the type arm in `analyse` reverted to
    /// `range: Range::default()`, which is precisely the code this replaces:
    ///
    ///   assertion `left == right` failed: a type error must be reported where
    ///   it is, not at the top of the file
    ///     left: Position { line: 0, character: 0 }
    ///    right: Position { line: 4, character: 2 }
    #[test]
    fn a_type_error_is_reported_at_its_own_position() {
        // line 0: # a comment, so nothing is at byte 0 by accident
        // line 1: def fine(a: Int) -> Int
        // line 2:   a
        // line 3: end
        // line 4: def bad(a: Int) -> Str
        // line 5:   a          <- the body, at character 2
        // line 6: end
        let src = "# a comment, so nothing is at byte 0 by accident\n\
                   def fine(a: Int) -> Int\n\
                   \x20 a\n\
                   end\n\
                   def bad(a: Int) -> Str\n\
                   \x20 a\n\
                   end\n";
        let a = analyse(src);
        let d = a
            .diagnostics
            .iter()
            .find(|d| d.source == "types")
            .unwrap_or_else(|| panic!("expected a type diagnostic: {:?}", a.diagnostics));

        assert_eq!(
            d.range.start,
            Position {
                line: 5,
                character: 2
            },
            "a type error must be reported where it is, not at the top of the file"
        );
        assert_eq!(
            d.range.end,
            Position {
                line: 5,
                character: 3
            },
            "the range must cover exactly the one-character body"
        );
    }

    /// **The type-diagnostic range is counted in UTF-16 code units too.**
    ///
    /// The conversion was already correct and already tested — for PARSE errors,
    /// the only diagnostics that had a span. Routing type diagnostics through the
    /// same [`LineIndex`] is what puts them under the same guarantee, and this is
    /// the test that says so: the expected character is 15, while the byte offset
    /// within the line is 18. An implementation that shipped bytes would report
    /// 18 and this fixture is the only kind that can tell.
    #[test]
    fn a_type_diagnostic_position_counts_utf16_code_units() {
        // line 0: def bad(s: Str) -> Int
        // line 1:   "héllo 😀" + s
        //
        // UTF-16 units on line 1:  0,1 spaces · 2 `"` · 3 h · 4 é · 5,6 ll · 7 o
        //                          8 space · 9,10 😀 (a surrogate pair) · 11 `"`
        //                          12 space · 13 `+` · 14 space · 15 s
        // Bytes on line 1 put `s` at 18, because é is 2 bytes and 😀 is 4.
        let src = "def bad(s: Str) -> Int\n  \"héllo 😀\" + s\nend\n";
        let a = analyse(src);
        let types: Vec<&Diagnostic> = a
            .diagnostics
            .iter()
            .filter(|d| d.source == "types")
            .collect();
        assert_eq!(types.len(), 2, "{:?}", a.diagnostics);

        // The string literal is the first bad operand: characters 2..12.
        assert_eq!(
            (types[0].range.start.character, types[0].range.end.character),
            (2, 12),
            "the string literal's range: {:?}",
            types[0].range
        );
        // `s` is the second: character 15, NOT byte 18.
        assert_eq!(
            types[1].range.start,
            Position {
                line: 1,
                character: 15
            },
            "`s` sits after a 2-byte é and a 4-byte 😀; 18 would mean bytes leaked \
             into a UTF-16 field. Got {:?}",
            types[1].range
        );
    }

    /// **No type diagnostic lands on the whole-document default.**
    ///
    /// The class gate rather than a per-fixture one: a future construction site
    /// in the checker that forgets its span reports `Span::synthetic()`, which
    /// [`LineIndex::range`] turns into the whole document — visibly wrong, but
    /// only if something is looking.
    ///
    /// RED RUN (2026-08-12): with the type arm reverted to `Range::default()`:
    ///
    ///   assertion `left != right` failed: "# pad\ndef f(a: Int) -> Str\n  a\nend\n":
    ///   ``f` declares it returns Str, but its body produces Int` reported at 0,0
    ///     left: Position { line: 0, character: 0 }
    ///    right: Position { line: 0, character: 0 }
    ///
    /// It trips on the first corpus entry and panics there, so the run proves the
    /// gate fires — not that every entry independently would.
    #[test]
    fn no_type_diagnostic_lands_on_a_default_or_whole_document_range() {
        let corpus = [
            "# pad\ndef f(a: Int) -> Str\n  a\nend\n",
            "# pad\ndef f(s: Str) -> Int\n  s + 1\nend\n",
            "# pad\ndef add(a: Int, b: Int) -> Int\n  a + b\nend\ndef g() -> Int\n  add(1, \"x\")\nend\n",
            "# pad\ndef f(a: Int, b) -> Int\n  a\nend\ndef g() -> Int\n  f(\"bad\", 1)\nend\n",
        ];
        let mut seen = 0;
        for src in corpus {
            let a = analyse(src);
            let whole = LineIndex::new(src).whole_document();
            for d in a.diagnostics.iter().filter(|d| d.source == "types") {
                assert_ne!(
                    d.range.start,
                    Position::default(),
                    "{src:?}: `{}` reported at 0,0 — every fixture here is padded \
                     with a comment line, so nothing legitimately starts there",
                    d.message
                );
                assert_ne!(
                    d.range, whole,
                    "{src:?}: `{}` reported over the whole document, which is what a \
                     synthetic span converts to",
                    d.message
                );
                seen += 1;
            }
        }
        // Anti-vacuity: counted, so a corpus that stopped producing three of
        // four diagnostics fails rather than passing over an empty loop.
        assert_eq!(seen, 4, "the corpus stopped producing type diagnostics");
    }

    /// A declaration's range is the declaration, not the file.
    ///
    /// Same defect, same cause: `declarations` had no span to offer and used
    /// `whole_document()`, so every symbol in a file claimed to span all of it.
    ///
    /// RED RUN (2026-08-12): `range: index.range(form.span)` in `declarations`
    /// reverted to `index.whole_document()`:
    ///
    ///   assertion `left == right` failed
    ///     left: Position { line: 6, character: 0 }
    ///    right: Position { line: 2, character: 3 }
    ///
    /// The first declaration claimed to end at the end of the file. Note that
    /// reverting the *diagnostic* arm does NOT redden this test and reverting
    /// this one does not redden those — two construction sites, two gates.
    #[test]
    fn a_declaration_range_is_the_declaration_not_the_whole_file() {
        // line 0: def one(a)
        // line 1:   a
        // line 2: end
        // line 3: def two(b)
        let src = "def one(a)\n  a\nend\ndef two(b)\n  b\nend\n";
        let a = analyse(src);
        assert_eq!(a.declarations.len(), 2, "{:?}", a.declarations);

        assert_eq!(
            a.declarations[0].range.start,
            Position {
                line: 0,
                character: 0
            }
        );
        assert_eq!(
            a.declarations[0].range.end,
            Position {
                line: 2,
                character: 3
            }
        );
        assert_eq!(
            a.declarations[1].range.start,
            Position {
                line: 3,
                character: 0
            }
        );
        assert_eq!(
            a.declarations[1].range.end,
            Position {
                line: 5,
                character: 3
            }
        );

        let whole = LineIndex::new(src).whole_document();
        for d in &a.declarations {
            assert_ne!(d.range, whole, "`{}` still spans the whole file", d.name);
        }
    }

    /// A synthetic span becomes the whole document, never line 0.
    ///
    /// Nothing blue's parser emits is synthetic, so this pins the conversion
    /// directly rather than through `analyse`. The distinction matters: `0,0` is
    /// a real position naming the first character, so reporting an unknown
    /// location that way is a false claim, while the whole document is the true
    /// one — "somewhere in this file".
    #[test]
    fn a_synthetic_span_becomes_the_whole_document_not_the_origin() {
        let index = LineIndex::new("abc\ndef\n");
        let r = index.range(blue_lang_syntax::Span::synthetic());
        assert_eq!(r, index.whole_document());
        assert_ne!(r, Range::default());
    }

    /// Anti-vacuity: an untyped program produces no type diagnostics, so the
    /// one above is the annotation's doing.
    #[test]
    fn an_untyped_program_produces_no_type_diagnostics() {
        assert!(analyse("def ok(a)\n  a\nend").diagnostics.is_empty());
    }

    // ---- positions ------------------------------------------------------

    #[test]
    fn positions_are_line_and_character() {
        let index = LineIndex::new("abc\ndefg\nhi");
        assert_eq!(
            index.position(0),
            Position {
                line: 0,
                character: 0
            }
        );
        assert_eq!(
            index.position(2),
            Position {
                line: 0,
                character: 2
            }
        );
        assert_eq!(
            index.position(4),
            Position {
                line: 1,
                character: 0
            }
        );
        assert_eq!(
            index.position(6),
            Position {
                line: 1,
                character: 2
            }
        );
        assert_eq!(
            index.position(9),
            Position {
                line: 2,
                character: 0
            }
        );
    }

    /// **UTF-16 code units, not bytes and not chars.** LSP specifies UTF-16; a
    /// client given byte offsets underlines the wrong span in any file with
    /// non-ASCII, silently, and only for the users who have such files.
    #[test]
    fn characters_are_counted_in_utf16_code_units() {
        // "é" is 2 bytes, 1 UTF-16 unit. "😀" is 4 bytes, 2 UTF-16 units.
        let text = "é😀x";
        let index = LineIndex::new(text);
        assert_eq!(index.position(2).character, 1, "é is one UTF-16 unit");
        assert_eq!(index.position(6).character, 3, "é + 😀 is three");
        assert_eq!(
            index.position(7).character,
            4,
            "and 7 bytes in is four UTF-16 units, not seven"
        );
    }

    /// Round-trip, so hover's position→offset agrees with diagnostics'
    /// offset→position. A mismatch means hover reads a different word than the
    /// one the user pointed at.
    #[test]
    fn positions_round_trip_through_offsets() {
        for text in ["abc\ndefg\nhi", "é😀x\nyz", "", "\n\n\n", "one line only"] {
            let index = LineIndex::new(text);
            for offset in 0..=text.len() {
                if !text.is_char_boundary(offset) {
                    continue;
                }
                let pos = index.position(offset);
                assert_eq!(
                    index.offset(pos),
                    offset,
                    "round trip failed at {offset} in {text:?} (pos {pos:?})"
                );
            }
        }
    }

    #[test]
    fn an_offset_past_the_end_is_clamped_rather_than_panicking() {
        let index = LineIndex::new("ab");
        assert_eq!(index.position(999), index.position(2));
        assert_eq!(
            index.offset(Position {
                line: 99,
                character: 99
            }),
            2
        );
    }

    // ---- declarations and hover ----------------------------------------

    #[test]
    fn declarations_are_found_for_defs_and_macros() {
        let a = analyse("def f(x)\n  x\nend\ndefmacro m(y)\n  quote\n    unquote(y)\n  end\nend");
        let names: Vec<&str> = a.declarations.iter().map(|d| d.name.as_str()).collect();
        assert_eq!(names, vec!["f", "m"]);
    }

    /// **The hover signature is the formatter's output.** Hover and the file
    /// cannot disagree about how a signature is spelled.
    #[test]
    fn hover_reports_the_signature_as_canonical_blue_source() {
        // Point at `add` in the definition on line 0.
        let sig = hover(
            PROGRAM,
            Position {
                line: 0,
                character: 5,
            },
        )
        .expect("hover");
        assert_eq!(sig, "def add(a: Int, b: Int) -> Int");
    }

    #[test]
    fn hover_finds_a_declaration_from_its_call_site() {
        // `add(1, 2)` is on line 3.
        let sig = hover(
            PROGRAM,
            Position {
                line: 3,
                character: 1,
            },
        )
        .expect("hover");
        assert!(sig.starts_with("def add("), "got {sig}");
    }

    #[test]
    fn hover_on_nothing_is_none() {
        assert!(hover(
            PROGRAM,
            Position {
                line: 1,
                character: 4
            }
        )
        .is_none());
        assert!(hover("", Position::default()).is_none());
    }
}
