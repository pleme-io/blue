use("kyasshu", [:schema])

sdl = read_file(
  path_join(
    getenv("GEN_ROOT", "."),
    "bidamas/danpen/fixtures/schema/kensa.graphql"
  )
)

write_file(
  getenv("GEN_OUT", "bidamas/kyasshu/keys/kensa.json"),
  unlines([json_stringify(schema(sdl))])
)
