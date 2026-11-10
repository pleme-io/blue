def init()
  0
end

def frame(s, i)
  {
    state: s,
    draw: [
      {op: :rect, x: 0, y: 0, w: 10, h: 10, colour: [1, 0, 0]},
      {op: :clear, colour: [0, 0, 1]},
      {op: :rect, x: 0, y: 0, w: 20, h: 20, colour: [0, 1, 0]}
    ]
  }
end

def event(s, e)
  s
end
