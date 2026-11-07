use("junjo", [:sort])

def adult?(person)
  age = person["age"]
  age != nil and age >= 18
end

def adults(text)
  sort(map((p) -> p["name"], filter(adult?, json_read(text))))
end
