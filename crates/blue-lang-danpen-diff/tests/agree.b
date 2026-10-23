use("danpen")

def printed(text, compact)
  format = if compact
    :compact
  else
    :graphql
  end
  danpen::render(danpen::parse(text), format)
rescue e
  "!#{e.kind}: #{e.message}"
end

def shown(findings)
  map((f) -> "#{get(f, :rule)}: #{get(f, :message)}", findings)
end

def schema_findings(text)
  shown(danpen::check(danpen::parse(text)))
rescue e
  ["#{e.kind}: #{e.message}"]
end

def prepared(text)
  danpen::schema_of(danpen::parse(text))
end

def document_findings(text, schema)
  shown(danpen::check(danpen::parse(text), schema))
rescue e
  ["#{e.kind}: #{e.message}"]
end
