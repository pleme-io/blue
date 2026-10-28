# XML through quick-xml as plain blue data, pure and the same on every evaluator; DTD entities are never expanded.

row(
  "xml.parse",
  join_lines(
    [
      "e = xml_parse(\"<r a=\\\"1 &amp; 2\\\"><c>x &lt; y</c><c/></r>\")",
      "[get(e, :name), get(get(e, :attributes), \"a\"), length(get(e, :children)), get(first(get(e, :children)), :text)]"
    ]
  ),
  value("[\"r\", \"1 & 2\", 2, \"x < y\"]"),
  covers("builtin:xml_parse")
)

row(
  "xml.parse.malformed",
  "xml_parse(\"<a><b></a>\")",
  fails(:eval, "xml_malformed")
)

row(
  "xml.parse.entity",
  "xml_parse(\"<!DOCTYPE r [<!ENTITY x SYSTEM \\\"file:///etc/passwd\\\">]><r>&x;</r>\")",
  fails(:eval, "xml_refused")
)

row(
  "xml.render",
  "xml_render(xml_parse(\"<r b=\\\"&quot;\\\" a=\\\"&lt;\\\">t &amp; u<c/></r>\"))",
  value("\"<r a=\\\"&lt;\\\" b=\\\"&quot;\\\">t &amp; u<c/></r>\""),
  covers("builtin:xml_render")
)
