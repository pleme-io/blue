use("kaaneru/bpf", [:ctx_int])

def sum_args(ctx)
  ctx_int(ctx, 0, 8) + ctx_int(ctx, 8, 8)
end

def sum_words(ctx)
  ctx_int(ctx, 0, 4) + ctx_int(ctx, 4, 4)
end
