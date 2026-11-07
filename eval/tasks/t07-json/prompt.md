# t07: parse JSON and transform it

Write `adults(text)`. `text` is a JSON array of people, each an object with a
`"name"` string and usually an `"age"` integer:

```json
[{"name": "Rui", "age": 30}, {"name": "Ana", "age": 12}, {"name": "Bea"}]
```

Answer the names of the people whose age is 18 or more, sorted
alphabetically. A person with no age is not an adult. For the text above the
answer is `["Rui"]`; for `[]` it is `[]`.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
