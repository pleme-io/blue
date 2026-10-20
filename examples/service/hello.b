# hello: a NATS service that greets. A request on hello.<name> is answered
# with the greeting in greeting.txt (an image asset, in /app, the working
# directory) and the name. It serves while NATS_URL is set, as the workload
# sets it from a Secret; under `blue test` it is unset and only the tests run.

def name_of(subject)
  parts = split(subject, ".")
  nth(count(parts) - 1, parts)
end

def reply(template, subject)
  "#{trim(template)}, #{name_of(subject)}!"
end

# One message: answered when the sender asked for an answer, else dropped.
def serve_once(conn, sub, template)
  m = nats_next_message(sub, 1000)
  if m != nil and get(m, :reply) != nil
    nats_publish(conn, get(m, :reply), reply(template, get(m, :subject)))
  end
end

# A tail call, so the loop runs for as long as the pod does.
def serve(conn, sub, template)
  serve_once(conn, sub, template)
  serve(conn, sub, template)
end

def main(url)
  conn = nats_connect(url)
  sub = nats_subscribe(conn, getenv("HELLO_SUBJECT", "hello.*"), "hello")
  serve(conn, sub, read_file("greeting.txt"))
end

url = getenv("NATS_URL")

if url != nil
  main(url)
end

test "a request on hello.<name> is answered with the greeting and the name"
  assert reply("Hello\n", "hello.ana") == "Hello, ana!"
end

test "the name is the subject's last token"
  assert name_of("hello.x.y") == "y"
end

test "an empty subject has an empty name"
  assert name_of("") == ""
  assert reply("Hi", "") == "Hi, !"
end
