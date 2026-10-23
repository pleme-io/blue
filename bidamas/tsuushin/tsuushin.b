use(
  "moji",
  [
    :after_first,
    :before_first,
    :char_index,
    :drop_chars,
    :is_alnum,
    :is_alpha,
    :is_digit,
    :last_char_index,
    :lower,
    :present,
    :starts_with,
    :take_chars
  ]
)

use("retsu", [:all_but_last, :first, :is_empty, :last, :push, :rest])
use("ronri", [:every])

def default_port(scheme)
  if scheme == "http"
    80
  elsif scheme == "https"
    443
  elsif scheme == "ftp"
    21
  elsif scheme == "ws"
    80
  elsif scheme == "wss"
    443
  end
end

def scheme_chars?(s)
  every((c) -> is_alnum(c) or c == "+" or c == "-" or c == ".", chars(s))
end

def valid_scheme?(s)
  present(s) and is_alpha(take_chars(s, 1)) and scheme_chars?(s)
end

def absolute_url?(text)
  i = char_index(text, "://")
  i > 0 and valid_scheme?(take_chars(text, i))
end

def split_authority(rest)
  i = char_index(rest, "/")
  if i < 0
    [rest, ""]
  else
    [take_chars(rest, i), drop_chars(rest, i)]
  end
end

def split_host_port(hostport)
  if starts_with(hostport, "[")
    close = char_index(hostport, "]")
    if close < 0
      raise(:parse_error, "tsuushin::parse: unclosed [ in #{hostport}")
    end
    after = drop_chars(hostport, close + 1)
    [take_chars(hostport, close + 1), after_first(after, ":")]
  else
    [before_first(hostport, ":"), after_first(hostport, ":")]
  end
end

def port_of(text)
  if text == ""
    nil
  elsif every(is_digit, chars(text)) and
    length(text) <= 5 and
    to_int(text) <= 65535
    to_int(text)
  else
    raise(:parse_error, "tsuushin::parse: bad port #{text}")
  end
end

def split_userinfo(authority)
  i = last_char_index(authority, "@")
  if i < 0
    ["", authority]
  else
    [take_chars(authority, i), drop_chars(authority, i + 1)]
  end
end

def parse(text, format)
  if format != :url
    raise(:parse_error, "tsuushin::parse: format #{format} is not :url")
  end
  if not absolute_url?(text)
    raise(:parse_error, "tsuushin::parse: no scheme:// in #{text}")
  end
  i = char_index(text, "://")
  scheme = lower(take_chars(text, i))
  rest = drop_chars(text, i + 3)
  fragment = after_first(rest, "#")
  no_fragment = before_first(rest, "#")
  query = after_first(no_fragment, "?")
  no_query = before_first(no_fragment, "?")
  parts = split_authority(no_query)
  ui = split_userinfo(first(parts))
  hp = split_host_port(nth(1, ui))
  host = lower(first(hp))
  if host == ""
    raise(:parse_error, "tsuushin::parse: no host in #{text}")
  end
  {
    "scheme" => scheme,
    "userinfo" => first(ui),
    "host" => host,
    "port" => port_of(nth(1, hp)),
    "path" => nth(1, parts),
    "query" => query,
    "fragment" => fragment
  }
end

def marked(pre, s, post)
  if s == ""
    ""
  else
    "#{pre}#{s}#{post}"
  end
end

def authority_text(u)
  port = get(u, "port")
  shown = if port == nil or port == default_port(get(u, "scheme"))
    ""
  else
    ":#{port}"
  end
  "#{marked("", get(u, "userinfo"), "@")}#{get(u, "host")}#{shown}"
end

def render(u, format)
  if format != :url
    raise(:render_error, "tsuushin::render: format #{format} is not :url")
  end
  "#{get(u, "scheme")}://#{authority_text(u)}#{get(u, "path")}#{marked("?", get(u, "query"), "")}#{marked("#", get(u, "fragment"), "")}"
end

def settle(stack, seg)
  if seg == "."
    stack
  elsif seg == ".."
    all_but_last(stack)
  else
    push(stack, seg)
  end
end

def glue(xs)
  reduce((acc, s) -> "#{acc}/#{s}", "", xs)
end

def last_or_empty(xs)
  if is_empty(xs)
    ""
  else
    last(xs)
  end
end

def without_final_empty(xs)
  if last_or_empty(xs) == ""
    all_but_last(xs)
  else
    xs
  end
end

def remove_dots(path)
  segs = rest(split(path, "/"))
  tail = last_or_empty(segs)
  trailing = tail == "" or tail == "." or tail == ".."
  body = without_final_empty(segs)
  kept = reduce(settle, [], body)
  if is_empty(kept)
    "/"
  elsif trailing
    "#{glue(kept)}/"
  else
    glue(kept)
  end
end

def merge_path(base_path, ref_path)
  if base_path == ""
    "/#{ref_path}"
  else
    "#{take_chars(base_path, last_char_index(base_path, "/") + 1)}#{ref_path}"
  end
end

def with_tail(u, path, query, fragment)
  assoc(assoc(assoc(u, "path", path), "query", query), "fragment", fragment)
end

def query_or(b, ref, query)
  if char_index(ref, "?") < 0
    get(b, "query")
  else
    query
  end
end

def join(base, path)
  b = parse(base, :url)
  if absolute_url?(path)
    render(parse(path, :url), :url)
  elsif starts_with(path, "//")
    render(parse("#{get(b, "scheme")}:#{path}", :url), :url)
  else
    fragment = after_first(path, "#")
    no_fragment = before_first(path, "#")
    query = after_first(no_fragment, "?")
    ref_path = before_first(no_fragment, "?")
    if ref_path == "" and not present(path)
      render(with_tail(b, get(b, "path"), get(b, "query"), ""), :url)
    elsif ref_path == ""
      render(
        with_tail(b, get(b, "path"), query_or(b, no_fragment, query), fragment),
        :url
      )
    elsif starts_with(ref_path, "/")
      render(with_tail(b, remove_dots(ref_path), query, fragment), :url)
    else
      render(
        with_tail(
          b,
          remove_dots(merge_path(get(b, "path"), ref_path)),
          query,
          fragment
        ),
        :url
      )
    end
  end
end

test "parse reads every part of a url and lowercases scheme and host"
  u = parse("HTTPS://User:pw@Example.COM:8443/a/b?x=1&y=2#top", :url)
  assert get(u, "scheme") == "https"
  assert get(u, "userinfo") == "User:pw"
  assert get(u, "host") == "example.com"
  assert get(u, "port") == 8443
  assert get(u, "path") == "/a/b"
  assert get(u, "query") == "x=1&y=2"
  assert get(u, "fragment") == "top"
end

test "parse of a bare host has an empty path and no port"
  u = parse("http://example.com", :url)
  assert get(u, "path") == ""
  assert get(u, "port") == nil
  assert get(u, "query") == ""
end

test "parse keeps an ipv6 host whole"
  u = parse("http://[::1]:80/x", :url)
  assert get(u, "host") == "[::1]"
  assert get(u, "port") == 80
end

test "parse refuses what is not an absolute url"
  assert (parse("example.com/a", :url) rescue :refused) == :refused
  assert (parse("http:///a", :url) rescue :refused) == :refused
  assert (parse("http://h:99999/", :url) rescue :refused) == :refused
  assert (parse("http://h:ab/", :url) rescue :refused) == :refused
  assert (parse("1ttp://h/", :url) rescue :refused) == :refused
  assert (parse("http://h/", :json) rescue :refused) == :refused
end

test "render writes canonical text and drops a default port"
  assert render(parse("HTTP://Example.com:80/a?b=1#c", :url), :url) ==
    "http://example.com/a?b=1#c"
  assert render(parse("http://example.com:8080/a", :url), :url) ==
    "http://example.com:8080/a"
  assert render(parse("https://u@h:443", :url), :url) == "https://u@h"
end

test "render of parse is a fixed point"
  t = render(parse("https://A.b:444/p/q?x#f", :url), :url)
  assert render(parse(t, :url), :url) == t
end

test "join resolves relative paths the way a browser does"
  b = "http://a.com/b/c/d?q=1#f"
  assert join(b, "g") == "http://a.com/b/c/g"
  assert join(b, "./g") == "http://a.com/b/c/g"
  assert join(b, "g/") == "http://a.com/b/c/g/"
  assert join(b, "/g") == "http://a.com/g"
  assert join(b, "//g.org/x") == "http://g.org/x"
  assert join(b, "?y=2") == "http://a.com/b/c/d?y=2"
  assert join(b, "#s") == "http://a.com/b/c/d?q=1#s"
  assert join(b, "") == "http://a.com/b/c/d?q=1"
  assert join(b, "g?y=2#s") == "http://a.com/b/c/g?y=2#s"
  assert join(b, ".") == "http://a.com/b/c/"
  assert join(b, "..") == "http://a.com/b/"
  assert join(b, "../g") == "http://a.com/b/g"
  assert join(b, "../../g") == "http://a.com/g"
  assert join(b, "../../../g") == "http://a.com/g"
  assert join(b, "g/../h") == "http://a.com/b/c/h"
end

test "join keeps an absolute url and resolves against a bare host"
  assert join("http://a.com/x", "https://B.org/y") == "https://b.org/y"
  assert join("http://a.com", "g") == "http://a.com/g"
end
