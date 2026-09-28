use("okite")
# Writes bidamas/okite/RULES.md, the rule card, from the ledger (`ok_card` in
# okite.b). Declared in the root Bluefile with generate(); a generator lives here,
# never inside a package, because a package loads every .b file it holds.
write_file(getenv("GEN_OUT", "bidamas/okite/RULES.md"), ok_card())
nil
