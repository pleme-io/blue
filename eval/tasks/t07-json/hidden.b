test "eval t07: adults keeps ages of 18 and more, sorted by name"
  assert adults("[]") == []
  text = "[{\"name\": \"Rui\", \"age\": 30}, {\"name\": \"Ana\", \"age\": 12}, {\"name\": \"Bea\"}]"
  assert adults(text) == ["Rui"]
  many = "[{\"name\": \"Zoe\", \"age\": 18}, {\"name\": \"Ivo\", \"age\": 17}, {\"name\": \"Cal\", \"age\": 81}]"
  assert adults(many) == %w[Cal Zoe]
end
