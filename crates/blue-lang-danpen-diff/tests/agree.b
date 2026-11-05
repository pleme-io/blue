use("toriyose/danpen")

def printed(text, compact)
  format = if compact
    :compact
  else
    :graphql
  end
  toriyose::danpen::render(toriyose::danpen::parse(text), format)
rescue e
  "!#{e.kind}: #{e.message}"
end

def shown(findings)
  map((f) -> "#{f[:rule]}: #{f[:message]}", findings)
end

def schema_findings(text)
  shown(toriyose::danpen::check(toriyose::danpen::parse(text)))
rescue e
  ["#{e.kind}: #{e.message}"]
end

def prepared(text)
  toriyose::danpen::schema_of(toriyose::danpen::parse(text))
end

def document_findings(text, schema)
  shown(toriyose::danpen::check(toriyose::danpen::parse(text), schema))
rescue e
  ["#{e.kind}: #{e.message}"]
end
