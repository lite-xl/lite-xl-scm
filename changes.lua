local changes = {}

---Diff additions, deletions and modifications parser.
---@param diff string
---@return table<integer, string>
function changes.parse(diff)
  local deletes, inserts = {}, {}
  local dstart, deletions, astart, additions = 0, 0, 0, 0
  for line in diff:gmatch("[^\n]+") do
    if
      (astart == 0 and dstart == 0)
      and
      line:match("^@@%s+%-%d+,%d+%s+%+%d+,%d+%s+@@")
    then
      dstart, deletions, astart, additions = line:match(
        "^@@%s+%-(%d+),(%d+)%s+%+(%d+),(%d+)%s+@@"
      )

      dstart = tonumber(dstart) or 0
      astart = tonumber(astart) or 0

      deletions = tonumber(deletions) or 0
      deletions = deletions + dstart

      additions = tonumber(additions) or 0
      additions = additions + astart
    elseif dstart > 0 or astart > 0 then
      local type = line:match("^([%+%-%s])")
      if dstart > 0 and (type == "-" or type:match("%s")) then
        if type == "-" then deletes[dstart] = "deletion" end
        dstart = dstart + 1
        if dstart >= deletions then dstart = 0 end
      end
      if astart > 0 and (type == "+" or type:match("%s")) then
        if type == "+" then inserts[astart] = "addition" end
        astart = astart + 1
        if astart >= additions then astart = 0 end
      end
    end
  end

  for line, change in pairs(deletes) do
    if inserts[line] then
      inserts[line] = "modification"
    else
      inserts[line] = change
    end
  end

  return inserts
end

return changes
