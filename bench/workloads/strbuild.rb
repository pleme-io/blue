s = +""
1_000_000.times { |i| s << (i % 10).to_s }
puts s.length
