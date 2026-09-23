use("sabi")
# The character tables of blue-lang-syntax's `kigou` module, authored in blue.
#
# This file is the source of truth for OPERATOR_ALIASES and WELCOME. Running it
# renders them into ../src/kigou/tables.rs through `sabi`, and the
# `kigou-tables-fresh` check in blue's flake fails when the committed Rust no
# longer matches what this file produces. To change a table: edit a row here,
# then regenerate:
#
#   GEN_OUT=crates/blue-lang-syntax/src/kigou/tables.rs \
#     BLUE_PATH=bidamas blue run crates/blue-lang-syntax/gen/kigou.b
#
# Blue compiling part of blue's own Rust: the curation is authored as data in
# blue, and the Rust compiler then checks the result like any other source.

# [symbol, the ASCII operator it spells, what it means].
#
# Curated: every row is a symbol that mathematics or ordinary typography already
# uses for exactly this operator, so a reader needs no lookup.
def operator_aliases()
  [
    ["≠", "!=", "not equal"],
    ["≤", "<=", "less than or equal"],
    ["≥", ">=", "greater than or equal"],
    ["×", "*", "multiplication"],
    ["÷", "/", "division"],
    ["−", "-", "minus sign (U+2212, not the ASCII hyphen)"],
    ["∧", "&&", "logical and"],
    ["∨", "||", "logical or"],
    ["¬", "!", "logical not"],
    ["≡", "==", "identical to"]
  ]
end

# [symbol, what it names], the symbols welcome inside identifiers.
def welcome()
  [
    ["λ", "lambda — the traditional name for an anonymous function"],
    ["∀", "for all"],
    ["∃", "there exists"],
    ["∈", "element of"],
    ["∉", "not an element of"],
    ["∅", "the empty set"],
    ["∪", "union"],
    ["∩", "intersection"],
    ["⊆", "subset of"],
    ["∘", "function composition"],
    ["∑", "sum"],
    ["∏", "product"],
    ["√", "square root"],
    ["∞", "infinity"],
    ["∂", "partial derivative"],
    ["∇", "gradient / nabla"],
    ["∫", "integral"],
    ["→", "maps to / implies"],
    ["←", "assigned from"],
    ["↔", "if and only if"],
    ["⇒", "implies"],
    ["⊤", "top / true"],
    ["⊥", "bottom / false"],
    ["⊢", "proves / entails"],
    ["π", "pi"],
    ["α", "alpha"],
    ["β", "beta"],
    ["γ", "gamma"],
    ["δ", "delta"],
    ["ε", "epsilon"],
    ["θ", "theta"],
    ["μ", "mu"],
    ["σ", "sigma"],
    ["φ", "phi"],
    ["ω", "omega"],
    ["ℕ", "the naturals"],
    ["ℤ", "the integers"],
    ["ℚ", "the rationals"],
    ["ℝ", "the reals"],
    ["ℂ", "the complex numbers"]
  ]
end

def str_ref()
  rs_ty_ref(rs_ty("str"))
end

def tables()
  rs_file("crates/blue-lang-syntax/gen/kigou.b", [
    rs_const(
      "OPERATOR_ALIASES",
      rs_ty_ref(rs_ty_slice(rs_ty_tuple([rs_ty("char"), str_ref(), str_ref()]))),
      rs_slice(map(fn(r) rs_tuple([rs_char(nth(0, r)), rs_str(nth(1, r)), rs_str(nth(2, r))]) end, operator_aliases())),
      [
        "The typographic spellings of blue's operators.",
        "",
        "Curated in `gen/kigou.b`, not inferred: every row is a symbol that mathematics",
        "or ordinary typography already uses for exactly this operator, so a reader",
        "needs no lookup. A symbol whose meaning would have to be *taught* belongs in an",
        "identifier instead, where the author names it."
      ]
    ),
    rs_const(
      "WELCOME",
      rs_ty_ref(rs_ty_slice(rs_ty_tuple([rs_ty("char"), str_ref()]))),
      rs_slice(map(fn(r) rs_tuple([rs_char(nth(0, r)), rs_str(nth(1, r))]) end, welcome())),
      [
        "The symbols blue explicitly welcomes inside identifiers.",
        "",
        "Not exhaustive — [`super::classify`] admits any alphabetic character and any",
        "symbol not on the operator list — but *named*, because a catalog a reader",
        "can scan is worth more than a rule they have to infer. These are the ones",
        "worth reaching for."
      ]
    )
  ])
end

bad = rs_invalid_names(tables())
if is_empty(bad)
  write_file(getenv("GEN_OUT", "crates/blue-lang-syntax/src/kigou/tables.rs"), render_rust(tables()))
else
  write_file(getenv("GEN_OUT", "crates/blue-lang-syntax/src/kigou/tables.rs"), "compile_error!(\"invalid Rust identifiers in gen/kigou.b\");\n")
end
