puts (0...1_000_000).map { |x| x * 3 }.select(&:even?).reduce(0) { |a, x| a + x }
