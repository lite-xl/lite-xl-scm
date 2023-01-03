---@type core.doc
local Doc = require "core.doc"

---A readonly core.doc.
---@class plugins.scm.readdoc : core.doc
local ReadDoc = Doc:extend()

---Set the text.
---@param text string
function ReadDoc:set_text(text)
  self.lines = {}
  local i = 1
  for line in text:gmatch("([^\n]*)\n?") do
    if line:byte(-1) == 13 then
      line = line:sub(1, -2)
      self.crlf = true
    end
    table.insert(self.lines, line .. "\n")
    self.highlighter.lines[i] = false
    i = i + 1
  end
  self:reset_syntax()
end

function ReadDoc:raw_insert(...) end
function ReadDoc:raw_remove(...) end
function ReadDoc:load(...) end
function ReadDoc:reload() end
function ReadDoc:save(...) end


return ReadDoc
