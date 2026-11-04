use("bpf", [:ctx_int])

AF_INET = 2

IPPROTO_TCP = 6

SK_DROP = 0

SK_PASS = 1

def sk_lookup(ctx)
  family = ctx_int(ctx, 8, 4)
  protocol = ctx_int(ctx, 12, 4)
  port = ctx_int(ctx, 60, 4)
  if family == AF_INET and protocol == IPPROTO_TCP and port == 80
    SK_DROP
  else
    SK_PASS
  end
end
