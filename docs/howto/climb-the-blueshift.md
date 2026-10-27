---
kind: howto
order: 2
summary: move a file from dynamic to checked one annotation at a time, reading blue shift at each step
---

# Climb the blueshift

`blue shift` names the rung a file stands on: dynamic, annotated, checked or
restricted. You climb by annotating definitions.

Start with a file that declares nothing:

```blue file=area.b
def area(w, h)
  w * h
end

def square(s)
  area(s, s)
end
```

```console
$ blue shift area.b
█░░░ dynamic  (0/2 typed, 0 nodes analysed)
no annotations — no analysis runs, and nothing is checked

  · untyped declaration      `area` has no annotation — annotate it to shift further
  · untyped declaration      `square` has no annotation — annotate it to shift further
```

Annotate `area`. The file moves up one rung, and `blue shift` names what
still holds it back:

```blue file=area.b
def area(w: Int, h: Int) -> Int
  w * h
end

def square(s)
  area(s, s)
end
```

```console
$ blue shift area.b
██░░ annotated  (1/2 typed, 3 nodes analysed)
some declarations are typed; untyped ones are unchecked

  → type annotation          `area` is annotated, so it is checked
  · untyped declaration      `square` has no annotation — annotate it to shift further
```

Annotate `square` too, and every declaration is checked:

```blue file=area.b
def area(w: Int, h: Int) -> Int
  w * h
end

def square(s: Int) -> Int
  area(s, s)
end
```

```console
$ blue shift area.b
███░ checked  (2/2 typed, 6 nodes analysed)
every declaration is typed, so the whole file is checked

  → type annotation          `area` is annotated, so it is checked
  → type annotation          `square` is annotated, so it is checked
```

A wrong annotation is now an error before the program runs:

```blue file=bad.b
def half(n: Int) -> Int
  "half"
end
```

```console fails
$ blue check bad.b
error[B0003]: `half` declares it returns Int, but its body produces Str
```

The `pleme-io/actions/blue-shift` action holds a project to a floor rung in
CI.
