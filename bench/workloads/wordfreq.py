import sys
from collections import Counter

with open(sys.argv[1]) as f:
    words = f.read().strip().lower().split(" ")
print(Counter(words).most_common(3))
