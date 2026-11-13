# waive B0085: rendering debt recorded 2026-11-13: no test of this generator declared kind: :rendering feeds its output to the output's reader yet
use("toriyose/kyasshu", [:schema])

sdl = read_file(
  path_join(
    getenv("GEN_ROOT", "."),
    "bidamas/toriyose/danpen/fixtures/schema/kensa.graphql"
  )
)

write_file(
  getenv("GEN_OUT", "bidamas/toriyose/kyasshu/keys/kensa.json"),
  unlines([json_stringify(schema(sdl))])
)
