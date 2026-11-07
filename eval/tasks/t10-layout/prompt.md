# t10: the one layout

Blue has one layout, the one `blue fmt` writes, and `blue check` refuses any
other (B0024). This program works but is not laid out that way:

```blue
def   area( w,h )
    if w<0 or h<0
      nil
    else
       w*h
    end
end


def describe( shape )
  "#{shape[:name]}: #{area(shape[:w],shape[:h])}"
end
def describe_all(shapes)
  join(map(describe, filter((shape) -> area(shape[:w], shape[:h]) != nil, shapes)), "; ")
end
```

Write it out as `blue fmt` would, without running a formatter: two-space
indentation, spaces around operators and after commas, one blank line between
definitions, and no line longer than 80 columns (a call that does not fit
puts one argument per line). Change nothing it does.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
