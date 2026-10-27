---
kind: tutorial
order: 1
summary: install blue, evaluate one expression and run a first file, in about a minute
---

# Install blue

You need [Nix](https://nixos.org) with flakes turned on. Install blue into
your profile:

```console host
$ nix profile install github:pleme-io/blue
```

To try blue without installing it, put `nix run github:pleme-io/blue --` in
front of each command below.

Ask blue for a value:

```console
$ blue eval '1 + 2'
3
```

Write a file called `hello.b`:

```blue file=hello.b
write_stdout(unlines(["Olá, mundo!"]))
```

Run it:

```console
$ blue hello.b
Olá, mundo!
```

That is a whole blue program. The next tutorial, [a first script](first-script.md),
gives it arguments.
