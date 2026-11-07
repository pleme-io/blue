def area(w, h)
  if w < 0 or h < 0
    nil
  else
    w * h
  end
end

def describe(shape)
  "#{shape[:name]}: #{area(shape[:w], shape[:h])}"
end

def describe_all(shapes)
  join(
    map(describe, filter((shape) -> area(shape[:w], shape[:h]) != nil, shapes)),
    "; "
  )
end
