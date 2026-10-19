# Processes and supervision
#
# spawn runs a function as a process of its own; send copies a message into its
# mailbox and receive takes the oldest message matching a pattern (:_ matches
# anything). A process shares nothing: the function's code and copies of the
# values it reads go with it. The program runs its processes while it waits in
# receive. A supervisor restarts a crashed child with an empty mailbox, and the
# crash writes a trace that blue replay runs again.
def squarer(parent)
  n = receive()
  if n < 0
    throw(error(:negative, "cannot square #{n}"))
  end
  send(parent, [:square, n, n * n])
  squarer(parent)
end

def ask(worker, n)
  send(worker, n)
  nth(2, receive([:square, n, :_]))
end

test "a worker answers by message"
  w = spawn(squarer, [self])
  assert ask(w, 7) == 49
end

test "a supervised worker survives a bad job"
  sup = supervisor(:one_for_one, [[squarer, [self]]], 3)
  w = nth(0, children(sup))
  send(w, -1)
  receive(:never, 50)
  assert ask(w, 3) == 9
end
