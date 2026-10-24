parts = []
for i in range(1000000):
    parts.append(str(i % 10))
print(len("".join(parts)))
