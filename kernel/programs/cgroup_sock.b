use("kaaneru/bpf", [:ctx_int])

ICMP = 1

def no_ping_socket(ctx)
  if ctx_int(ctx, 12, 4) == ICMP
    0
  else
    1
  end
end
