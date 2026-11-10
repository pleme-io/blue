def init()
  0
end

def frame(s, i)
  {
    state: s,
    draw: [
      {op: :circle},
      {op: :clear, colour: [0, 1, 0]},
      {op: :rect, x: 0, y: 0, w: 1, h: 1, colour: [2, 0, 0]}
    ]
  }
end

def event(s, e)
  s
end
