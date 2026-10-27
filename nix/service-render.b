use("haibi")

lock = json_read(read_file(argv_get(0)))
manifest = lock["manifest"]
name = argv_get(1)
svc = get(manifest["services"], name)

if svc.nil?
  raise(:no_service, "the lock declares no service #{name}")
end

haibi::write_tree(argv_get(2), haibi::files(name, manifest["version"], svc))
