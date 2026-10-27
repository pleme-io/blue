def fib(n)
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

write_stdout(unlines([fib(27)]))
