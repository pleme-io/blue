# waive B0085: rendering debt recorded 2026-11-13: no test of this generator declared kind: :rendering feeds its output to the output's reader yet
use("kiwari", %i[blue render])

# crates/blue-lang-kiwari/blue.kiwari.json, rendered from blue's grammar spec (bidamas/kiwari).
write_file(
  getenv("GEN_OUT", "crates/blue-lang-kiwari/blue.kiwari.json"),
  render(blue, "blue.kiwari.json")
)
