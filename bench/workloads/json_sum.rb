require "json"

records = JSON.parse(File.read(ARGV[0]))
puts records.sum { |r| r["value"] }
