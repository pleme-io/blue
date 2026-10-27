---
kind: howto
order: 3
summary: hold a program to the host capabilities it needs with --allow, in a run or in a script's shebang
---

# Declare what a program may touch

A program that runs with no flag may reach every host capability. `--allow`
holds a run to the ones you name: `none`, `host`, or any of `process`,
`filesystem`, `environment`, `clock`, `network` and `entropy`.

Here is a program that reads a file:

```blue file=peek.b
write_stdout(read_file("note.txt"))
```

```blue file=note.txt
a note
```

With `--allow none`, blue refuses it before it runs, and names the flag that
grants it:

```console fails
$ blue run --allow none --quiet peek.b
refused: `read_file` reaches the host (filesystem)
```

Grant exactly what it needs:

```console
$ blue run --allow filesystem --quiet peek.b
a note
```

A script states its capabilities in its shebang, so `./peek.b` carries them
with it:

```blue file=peek2.b
#!/usr/bin/env -S blue --allow filesystem
write_stdout(read_file("note.txt"))
```

Every Rust guarantee, the blue gate that matches it and its off switch are in
[SAFETY.md](../SAFETY.md). One access declaration for a whole service, in its
`service(...)` entry, is designed in
[SERVICE-ACCESS.md](../SERVICE-ACCESS.md) and not built yet.
