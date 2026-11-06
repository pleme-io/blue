use("kaaneru/bpf", [:ctx_int])

def socket_len(ctx)
  ctx_int(ctx, 0, 4)
end

def short_frame(ctx)
  if ctx_int(ctx, 0, 4) < 20
    1
  else
    0
  end
end
