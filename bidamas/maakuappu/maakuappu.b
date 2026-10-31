@moduledoc """
maakuappu (マークアップ) — XML as data: a document parsed by the runtime's xml_parse (quick-xml) into element maps {name, attributes, children, text}, the queries a reader of a scanner export asks of it (children and descendants by name, attributes, text, a path of element names), and the element rendered back with every value escaped. A DTD entity is never expanded or fetched: the document is refused (:xml_refused), and a document that is not well-formed raises :xml_malformed.

    attr(child(parse("<r><c id=\"7\"/></r>"), "c"), "id") #=> "7"
"""

use("kyohi", [:raised])
use("retsu", %i[first flat_map size])

@doc """
parse: the root element of an XML document. Raises :xml_malformed when the text is not well-formed and :xml_refused when it declares or references a DTD entity.

    parse("<r/>").name #=> "r"
"""
def parse(text)
  xml_parse(text)
end

@doc """
render: the element as XML text that parse reads back equal, attributes in key order and every value escaped.

    render(parse("<r a=\"&lt;\"/>")) #=> "<r a=\"&lt;\"/>"
"""
def render(el)
  xml_render(el)
end

@doc """
escape: text made safe inside an XML element or a double-quoted attribute, with &, <, > and " written as entities, for XML built as text rather than through render.

    escape("a < b & \"c\"") #=> "a &lt; b &amp; &quot;c&quot;"
"""
def escape(text)
  replace(
    replace(replace(replace(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"),
    "\"",
    "&quot;"
  )
end

@doc """
element: a new element with this name, attributes map, children and text, the shape parse returns.

    render(element("r", {}, [], "x")) #=> "<r>x</r>"
"""
def element(name, attributes, children, text)
  {name:, attributes:, children:, text:}
end

@doc """
children: the child elements of el named name, in document order; [] when el is nil.

    children(nil, "c") #=> []
"""
def children(el, name)
  if el.nil?
    []
  else
    filter((c) -> c.name == name, el.children)
  end
end

@doc """
child: the first child element of el named name, or nil.

    child(parse("<r/>"), "c") #=> nil
"""
def child(el, name)
  first(children(el, name))
end

@doc """
descendants: every element below el named name, in document order, at any depth; [] when el is nil.

    descendants(nil, "c") #=> []
"""
def descendants(el, name)
  if el.nil?
    []
  else
    flat_map(
      el.children,
      fn(c)
        below = descendants(c, name)
        if c.name == name
          cons(c, below)
        else
          below
        end
      end
    )
  end
end

@doc """
attr: the value of el's attribute key, or nil when el is nil or has no such attribute.

    attr(parse("<r a=\"1\"/>"), "b") #=> nil
"""
def attr(el, key)
  if el.nil?
    nil
  else
    get(el.attributes, key)
  end
end

@doc """
text_of: el's own text with surrounding whitespace trimmed, or nil when el is nil.

    text_of(parse("<r>  x </r>")) #=> "x"
"""
def text_of(el)
  if el.nil?
    nil
  else
    trim(el.text)
  end
end

@doc """
find: every element reached from el by following path, a list of element names, one level per name (the XPath a/b/c); [el] for the empty path, [] when el is nil.

    find(nil, ["a"]) #=> []
"""
def find(el, path)
  if el.nil?
    []
  else
    reduce(
      (found, name) -> flat_map(found, (e) -> children(e, name)),
      [el],
      path
    )
  end
end

test "the empty cases: no document, no element, no path"
  assert raised(() -> parse("")) == :xml_malformed
  assert children(nil, "c") == []
  assert child(nil, "c").nil?
  assert descendants(nil, "c") == []
  assert attr(nil, "a").nil?
  assert text_of(nil).nil?
  assert find(nil, ["a"]) == []
  e = parse("<r/>")
  assert e.children == []
  assert e.text == ""
  assert find(e, []) == [e]
  assert render(e) == "<r/>"
end

test "escaped text reads back as itself inside an element and an attribute"
  s = "a<b>&\"c\" d"
  doc = parse("<r v=\"#{escape(s)}\">#{escape(s)}</r>")
  assert text_of(doc) == s
  assert attr(doc, "v") == s
  assert escape("") == ""
end

test "render then parse is the identity on a parsed document"
  src = "<?xml version=\"1.0\"?><!DOCTYPE run><run v=\"1 &amp; &lt;2&gt; &quot;q&quot;\" ns:x=\"a&#10;b\"><host><port id=\"22\">ssh &amp; more</port><port id=\"80\"/></host><![CDATA[<raw>&]]></run>"
  e = parse(src)
  assert parse(render(e)) == e
  assert render(parse(render(e))) == render(e)
  built = element("a", {"k" => "<\"&'>"}, [element("b", {}, [], "x > y")], "")
  assert parse(render(built)) == built
end

test "an nmap-shaped document answers values checked by hand"
  doc = parse(
    join_lines(
      [
        "<nmaprun scanner=\"nmap\">",
        "  <host><address addr=\"203.0.113.5\" addrtype=\"ipv4\"/>",
        "    <ports>",
        "      <port protocol=\"tcp\" portid=\"22\"><state state=\"open\"/><service name=\"ssh\"/></port>",
        "      <port protocol=\"tcp\" portid=\"443\"><state state=\"closed\"/></port>",
        "    </ports>",
        "  </host>",
        "  <host><address addr=\"203.0.113.6\" addrtype=\"ipv4\"/><ports/></host>",
        "</nmaprun>"
      ]
    )
  )
  assert size(children(doc, "host")) == 2
  assert map((p) -> attr(p, "portid"), find(doc, %w[host ports port])) ==
    %w[22 443]
  assert size(descendants(doc, "port")) == 2
  assert size(descendants(doc, "address")) == 2
  assert attr(
    child(first(find(doc, %w[host ports port])), "service"),
    "name"
  ) == "ssh"
  assert attr(child(child(doc, "host"), "address"), "addr") == "203.0.113.5"
  assert text_of(parse(join_lines(["<a>", "  x &amp; y ", "</a>"]))) == "x & y"
  assert parse("<x:r xmlns:x=\"urn:example\"/>").name == "x:r"
end

test "a control: what is not well-formed or names a DTD entity is refused, never nil"
  assert raised(() -> parse("<a><b></a>")) == :xml_malformed
  assert raised(() -> parse("<a/><b/>")) == :xml_malformed
  assert raised(() -> parse("<a x=\"1\" x=\"2\"/>")) == :xml_malformed
  assert raised(() -> parse("<r>&nbsp;</r>")) == :xml_refused
  assert parse("<r>&amp;&#65;</r>").text == "&A"
  assert raised(() -> render(element("bad name", {}, [], ""))) == :xml_refused
  assert raised(() -> render(5)) == :xml_refused
end

test "an external entity (XXE) and a billion laughs are refused before any expansion"
  xxe = "<?xml version=\"1.0\"?><!DOCTYPE r [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><r>&x;</r>"
  assert raised(() -> parse(xxe)) == :xml_refused
  laughs = "<!DOCTYPE r [<!ENTITY a \"ha\"><!ENTITY b \"&a;&a;&a;&a;&a;&a;&a;&a;\"><!ENTITY c \"&b;&b;&b;&b;&b;&b;&b;&b;\">]><r>&c;</r>"
  assert raised(() -> parse(laughs)) == :xml_refused
  burp_dtd = "<!DOCTYPE issues [<!ELEMENT issues (issue*)><!ATTLIST issues burpVersion CDATA \"\">]><issues burpVersion=\"2\"/>"
  assert attr(parse(burp_dtd), "burpVersion") == "2"
end
