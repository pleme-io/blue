def quiet(x)
  x
end

def loud(x)
  x
end

# waive FX0001: this one must be loud
def shout(x)
  loud(x)
end

shout(1)
