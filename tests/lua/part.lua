-- A busted helper (`--helper`): with WFJ_PART=k/n in the environment, only every n-th test of the file is
-- registered, starting at the k-th, so n processes with k = 1..n run every test of the file once. A spec
-- that loads the whole addon before each test is slow as one process; in parts its tests run side by side.
-- Returning `nil, false` from a `register` subscriber is how busted's own name and tag filters skip a test.
return function(busted)
  local k, n = (os.getenv("WFJ_PART") or ""):match("^(%d+)/(%d+)$")
  if not k then return true end
  k, n = tonumber(k), tonumber(n)
  local seen = 0
  busted.subscribe({ "register", "it" }, function()
    seen = seen + 1
    return nil, (seen - 1) % n == k - 1
  end, { priority = 1 })
  return true
end
