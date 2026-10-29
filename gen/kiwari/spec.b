use("kiwari", %i[blue render])

# crates/blue-lang-kiwari/blue.kiwari.json, rendered from blue's grammar spec (bidamas/kiwari).
write_file(
  getenv("GEN_OUT", "crates/blue-lang-kiwari/blue.kiwari.json"),
  render(blue, "blue.kiwari.json")
)
