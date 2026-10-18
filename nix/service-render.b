use("haibi")

lock = json_read(read_file(argv_get(0)))
manifest = get(lock, "manifest")
name = argv_get(1)
svc = get(get(manifest, "services"), name)

if svc == nil
  throw(error(:no_service, "the lock declares no service #{name}"))
end

haibi::write_tree(
  argv_get(2),
  haibi::files(name, get(manifest, "version"), svc)
)
