def worker(parent, i)
  send(parent, i)
end

map((i) -> spawn(worker, [self, i]), range(10000))
write_stdout("#{reduce((a, _i) -> a + receive(:_), 0, range(10000))}\n")
