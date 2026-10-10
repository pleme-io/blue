# A rule that never returns, beside one that does.

def spin(n)
  spin(n + 1)
end

def spin_forever(form)
  spin(0)
end

def every_form(form)
  [{at: [], message: "seen"}]
end
