use("junjo", [:sort])

def adult?(p)
  age = json_get(p, :age)
  age != nil and age >= 18
end

def adults(text)
  sort(map((p) -> json_get(p, :name), filter(adult?, json_parse(text))))
end

test "adults of the empty array is empty"
  assert adults("[]") == []
end

test "adults matches the example"
  text = "[{\"name\": \"Rui\", \"age\": 30}, {\"name\": \"Ana\", \"age\": 12}]"
  assert adults(text) == ["Rui"]
end

test "adults sorts names and skips the ageless"
  people = [
    {name: "Zoe", age: 18},
    {name: "Bea"},
    {name: "Ana", age: 40},
    {name: "Kim", age: 17}
  ]
  assert adults(json_stringify(people)) == %w[Ana Zoe]
end
