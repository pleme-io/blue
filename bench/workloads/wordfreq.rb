words = File.read(ARGV[0]).strip.downcase.split(" ")
p words.tally.max_by(3) { |_, n| n }
