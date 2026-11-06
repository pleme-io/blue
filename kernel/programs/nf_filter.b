use("kaaneru/bpf", %i[ctx_int declare_map kernel_read map_add])

SEEN = declare_map(:nf_seen, :array, 4, 8, 256)

NF_DROP = 0

NF_ACCEPT = 1

ICMP = 1

MARKED_TTL = 33

def nf_filter(ctx)
  skb = ctx_int(ctx, 8, 8)
  head = kernel_read(skb, "sk_buff", ["head"], 8)
  header = kernel_read(skb, "sk_buff", ["network_header"], 2)
  ip = wrapping_add(head, header)
  proto = kernel_read(ip, "iphdr", ["protocol"], 1)
  ttl = kernel_read(ip, "iphdr", ["ttl"], 1)
  map_add(SEEN, proto, 1)
  if proto == ICMP and ttl == MARKED_TTL
    NF_DROP
  else
    NF_ACCEPT
  end
end
