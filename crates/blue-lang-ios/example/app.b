def init()
  {taps: 0}
end

def frame(state, input)
  w = input[:width]
  h = input[:height]
  {
    state:,
    draw: [
      {op: :clear, colour: [0.1, 0.2, 0.4]},
      {
        op: :rect,
        x: w * 0.25,
        y: h * 0.25,
        w: w * 0.5,
        h: h * 0.25,
        colour: [1.0, 0.5, 0.0]
      }
    ]
  }
end

def event(state, ev)
  if ev[:phase] == :ended
    {taps: state[:taps] + 1}
  else
    state
  end
end

test "a frame clears and draws one rectangle in the upper half"
  out = frame(init, {t: 0.0, width: 400.0, height: 800.0})
  assert out[:state] == init
  assert map((d) -> d[:op], out[:draw]) == %i[clear rect]
  assert out[:draw][1][:y] == 200.0
end

test "a finished touch counts as a tap"
  assert event(init, {kind: :touch, phase: :ended, x: 1.0, y: 1.0})[:taps] == 1
  assert event(init, {kind: :touch, phase: :began, x: 1.0, y: 1.0}) == init
end
