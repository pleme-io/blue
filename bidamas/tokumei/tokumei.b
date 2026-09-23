use("ran")
use("toukei")
use("kazu")
# tokumei (匿名) — anonymity: learn what a group is without exposing anyone in it.
#
# Four instruments, each with the number that says how private it is:
#
#   forced response   each person answers truthfully with probability p and
#                     otherwise answers a coin flip (Warner 1965, in its
#                     forced-response form). No single answer means anything;
#                     the share is still recoverable. Its privacy is
#                     epsilon = ln((1 + p) / (1 - p)).
#   Laplace noise     a count published with noise of scale 1 / epsilon is
#                     epsilon-differentially private (Dwork et al. 2006).
#   suppression       a count below k is not published at all — the rule every
#                     statistics office uses for small cells.
#   uniqueness        how likely a person is alone in their cell of attributes
#                     in a group of a given size — the re-identification risk
#                     that makes households and small communities hard to
#                     protect.
#
# Nothing here decides what a group should do with what it learns; that is
# the caller's, and privacy that is spent on a decision stays spent.

# ── forced response ────────────────────────────────────────────────────────

# One answer: the truth with probability p, else a fair coin.
def forced_response(truth, p, seed)
  if next_float(replicate_stream(seed, 1)) < p
    truth
  else
    next_float(replicate_stream(seed, 2)) < 0.5
  end
end

# The share of true "yes" recovered from the share of "yes" answers:
# P(yes) = p x share + (1 - p) / 2, solved for share and kept in [0, 1].
def forced_response_estimate(yes_share, p)
  clamp((yes_share - ((1 - p) / 2)) / p, 0, 1)
end

# The privacy of one forced-response answer: epsilon = ln((1 + p) / (1 - p)).
# nil at p = 1, where every answer is the truth and there is no guarantee.
def forced_response_epsilon(p)
  if p >= 1
    nil
  else
    log((1 + p) / (1 - p))
  end
end

# How sure an observer is that someone who answered "yes" truly holds the
# trait, given its prevalence: the exposure a person actually carries.
def forced_response_exposure(prevalence, p)
  yes_if_true = (1 + p) / 2
  yes_if_false = (1 - p) / 2
  (prevalence * yes_if_true) / ((prevalence * yes_if_true) + ((1 - prevalence) * yes_if_false))
end

# ── Laplace noise ──────────────────────────────────────────────────────────

# A draw from Laplace(0, scale), by the inverse CDF.
def laplace_draw(scale, seed)
  u = next_float(seed) - 0.5
  tail = max(1 - (2 * abs(u)), 0.000000001)
  if u < 0
    scale * log(tail)
  else
    0 - (scale * log(tail))
  end
end

# A count published with epsilon-differential privacy.
def private_count(count, epsilon, seed)
  count + laplace_draw(1 / epsilon, seed)
end

# A share of n published with epsilon-differential privacy, kept in [0, 1].
def private_share(count, n, epsilon, seed)
  clamp(private_count(count, epsilon, seed) / n, 0, 1)
end

# ── suppression and uniqueness ─────────────────────────────────────────────

# The count, or nil when it is below the publication threshold k.
def suppress_small(count, k)
  if count < k
    nil
  else
    count
  end
end

# The chance a person is alone in their cell when a group of `group_size`
# falls uniformly into `cells` attribute combinations: (1 - 1/cells)^(size - 1).
# Two yes/no traits make 4 cells; in a household of 4, 42% of people are unique.
def unique_share(group_size, cells)
  expt(1 - (1 / cells), group_size - 1)
end

# ── seeds ──────────────────────────────────────────────────────────────────

# An independent stream derived from a seed — ran's stream_seed, named here so
# a caller reading tokumei sees where its randomness comes from.
def replicate_stream(seed, i)
  stream_seed(seed, i)
end

# ── tests ──────────────────────────────────────────────────────────────────

test "forced response recovers the true share from answers that each mean nothing"
  truths = map(fn(i) i < 180 end, range(0, 600))
  answers = map(fn(i) forced_response(nth(i, truths), 0.5, stream_seed(11, i)) end, range(0, 600))
  yes = size(filter(fn(a) a end, answers)) / 600
  assert abs(forced_response_estimate(yes, 0.5) - 0.3) < 0.08
end

test "control: a truthful answer at p = 1 is the truth, and costs all privacy"
  assert forced_response(true, 1, 5) == true
  assert forced_response(false, 1, 5) == false
  assert forced_response_epsilon(1) == nil
end

test "the privacy budget and the exposure of a forced-response answer"
  assert abs(forced_response_epsilon(0.5) - log(3)) < 0.000001
  assert abs(forced_response_exposure(0.5, 0.5) - 0.75) < 0.000001
  assert forced_response_exposure(0.1, 0.5) < 0.3
end

test "Laplace noise is centred on zero and scales with 1 / epsilon"
  draws = map(fn(i) laplace_draw(1, stream_seed(3, i)) end, range(0, 400))
  assert abs(mean(draws)) < 0.3
  wide = map(fn(i) abs(laplace_draw(10, stream_seed(3, i))) end, range(0, 200))
  narrow = map(fn(i) abs(laplace_draw(1, stream_seed(3, i))) end, range(0, 200))
  assert mean(wide) > mean(narrow)
end

test "a private share stays a share"
  s = private_share(3, 4, 0.1, 9)
  assert s >= 0 && s <= 1
end

test "small counts are suppressed, and the threshold is inclusive"
  assert suppress_small(3, 5) == nil
  assert suppress_small(5, 5) == 5
end

test "uniqueness: alone is unique, and a small group of four in four cells is 42%"
  assert abs(unique_share(1, 4) - 1) < 0.000001
  assert abs(unique_share(4, 4) - 0.421875) < 0.000001
  assert unique_share(100, 4) < 0.001
end
