---
kind: tutorial
order: 2
summary: write a script that reads its arguments, and let blue start one for you
---

# A first script

A script is one file that runs from the command line. It needs no project
and no configuration.

Write `greet.b`:

```blue file=greet.b
#!/usr/bin/env blue
def greeting(who)
  "hello, #{who}"
end

write_stdout(unlines([greeting(argv_get(0, "world"))]))
```

`argv_get(0, "world")` reads the first argument, or `"world"` when there is
none. Run the script with and without one:

```console
$ blue greet.b
hello, world
$ blue greet.b ryn
hello, ryn
```

The first line is a shebang. After `chmod +x greet.b`, the script also runs as
`./greet.b ryn`.

blue writes one formatting. Ask it whether the file is in that form:

```console
$ blue fmt --check greet.b
```

No output means yes. `blue fmt --write` puts a file into the form.

`blue new --script` starts a script for you, already executable and already
formatted:

```console
$ blue new --script tool.b
created tool.b, executable
run it   ./tool.b  (or blue tool.b)
$ blue tool.b a b
hello, a (2 argument(s))
```

A script can `use` every standard bidama with no setup. When a script
outgrows one file, it becomes [a first program](first-program.md).
