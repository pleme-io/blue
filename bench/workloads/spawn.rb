q = Queue.new
fibers = (0...10_000).map { |i| Fiber.new { q << i } }
fibers.each(&:resume)
puts (0...10_000).sum { q.pop }
