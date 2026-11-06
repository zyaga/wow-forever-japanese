-- Core/Fsrs.lua: the FSRS-6 memory model (ADR-071, docs/systems/study.md). Pure: no globals, no frames.
-- Ported as published, nothing tuned: the 21 default parameters and every formula follow py-fsrs 6.3.2
-- (fsrs/scheduler.py: DEFAULT_PARAMETERS, get_card_retrievability, review_card and its helpers) and fsrs-rs 6.6.2
-- (src/inference_v6.rs, src/model_v6.rs), which agree. The elapsed days are rounded to whole days as fsrs-rs does
-- (Anki works in calendar days); under one whole day the same-day (short-term) formula applies.
--   Fsrs.review(s, d, elapsedDays, rating) → s, d     s < 0: the card was never graded
--   Fsrs.retrievability(elapsedDays, s) → the chance of recall, 0.9 when elapsedDays == s
-- Core/Study turns the stability into a due date; this file knows nothing about cards or time.
local _, WFJ = ...
local Fsrs = {}
WFJ.Fsrs = Fsrs

-- py-fsrs 6.3.2 DEFAULT_PARAMETERS (= fsrs-rs FSRS6_DEFAULT_PARAMETERS): w[1]..w[21]; w[21] is the decay
local W = {
  0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
  1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
}

-- A fresh copy on every read, so no caller can change the model every player uses.
function Fsrs.W()
  local out = {}
  for i, v in ipairs(W) do out[i] = v end
  return out
end

Fsrs.AGAIN, Fsrs.HARD, Fsrs.GOOD, Fsrs.EASY = 1, 2, 3, 4

local S_MIN = 0.001 -- py-fsrs STABILITY_MIN
local D_MIN, D_MAX = 1, 10 -- py-fsrs MIN_DIFFICULTY / MAX_DIFFICULTY

local DECAY = -W[21]
local FACTOR = 0.9 ^ (1 / DECAY) - 1 -- so that R(t = S) = 0.9

local function clampS(s) return math.max(s, S_MIN) end
local function clampD(d) return math.min(math.max(d, D_MIN), D_MAX) end

-- R(t, S) = (1 + FACTOR * t / S) ^ DECAY, t in days
function Fsrs.retrievability(elapsedDays, s)
  return (1 + FACTOR * math.max(0, elapsedDays) / s) ^ DECAY
end

-- D0(G) = w5 - e^(w6 (G - 1)) + 1, unclamped: the mean-reversion target uses the unclamped D0(Easy)
local function initialDifficultyRaw(rating)
  return W[5] - math.exp(W[6] * (rating - 1)) + 1
end

-- linear damping, then mean reversion toward D0(Easy) with weight w8
local function nextDifficulty(d, rating)
  local delta = -(W[7] * (rating - 3))
  local damped = d + (10 - d) * delta / 9
  return clampD(W[8] * initialDifficultyRaw(Fsrs.EASY) + (1 - W[8]) * damped)
end

-- same-day review: S' = S * e^(w18 (G - 3 + w19)) * S^-w20, the increase floored at 1 for Hard / Good / Easy
local function shortTermStability(s, rating)
  local inc = math.exp(W[18] * (rating - 3 + W[19])) * s ^ -W[20]
  if rating >= Fsrs.HARD then inc = math.max(inc, 1) end
  return clampS(s * inc)
end

local function recallStability(d, s, r, rating)
  local hardPenalty = rating == Fsrs.HARD and W[16] or 1
  local easyBonus = rating == Fsrs.EASY and W[17] or 1
  return clampS(s * (1 + math.exp(W[9]) * (11 - d) * s ^ -W[10] * (math.exp((1 - r) * W[11]) - 1)
    * hardPenalty * easyBonus))
end

-- a lapse: the smaller of the long-term post-lapse stability and S / e^(w18 w19)
local function forgetStability(d, s, r)
  local longTerm = W[12] * d ^ -W[13] * ((s + 1) ^ W[14] - 1) * math.exp((1 - r) * W[15])
  local shortTerm = s / math.exp(W[18] * W[19])
  return clampS(math.min(longTerm, shortTerm))
end

-- One grade: the stability and difficulty update of fsrs-rs next_state / py-fsrs review_card (learning steps and
-- intervals are scheduling, not memory: Core/Study's part). `s < 0`: never graded. `elapsedDays` is rounded half
-- away from zero to whole days; 0 whole days is a same-day review.
function Fsrs.review(s, d, elapsedDays, rating)
  if s < 0 then return clampS(W[rating]), clampD(initialDifficultyRaw(rating)) end
  local whole = math.floor(math.max(0, elapsedDays) + 0.5)
  local nextS
  if whole < 1 then
    nextS = shortTermStability(s, rating)
  else
    local r = Fsrs.retrievability(whole, s)
    nextS = rating == Fsrs.AGAIN and forgetStability(d, s, r) or recallStability(d, s, r, rating)
  end
  return nextS, nextDifficulty(d, rating)
end
