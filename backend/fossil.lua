-- Backend implementation for Fossil.
-- More details at: https://www.fossil-scm.org/

local common = require "core.common"
local Backend = require "plugins.scm.backend"

---@class plugins.scm.backend.fossil : plugins.scm.backend
---@field super plugins.scm.backend
local Fossil = Backend:extend()

function Fossil:new()
  self.super.new(self, "Fossil", "fossil")
end

function Fossil:detect(directory)
  local list = system.list_dir(directory)
  if list then
    for _, file in ipairs(list) do
      if file == ".fslckout" then
        return true
      end
    end
  end
  return false
end

---@param callback plugins.scm.backend.ongetbranch
function Fossil:get_branch(directory, callback)
  local cached = self:get_from_cache("get_branch", directory)
  if cached then callback(cached, true) return end
  self:execute(function(proc)
    local branch = nil
    for line in self:get_process_lines(proc, "stdout") do
      local result = line:match("%s*%*%s*([^%s]+)")
      if result then
        branch = result
        break
      end
      self:yield()
    end
    self:add_to_cache("get_branch", branch, directory, 3)
    callback(branch)
  end, directory, "branch")
end

---@param directory string
---@param callback plugins.scm.backend.ongetchanges
function Fossil:get_changes(directory, callback)
  directory = directory:gsub("[/\\]$", "/")
  local cached = self:get_from_cache("get_changes", directory)
  if cached then callback(cached, true) return end
  self:execute(function(proc)
    ---@type plugins.scm.backend.filechange[]
    local changes = {}
    local output = self:get_process_output(proc, "stdout")
    local iterations = 1
    for line in output:gmatch("[^\n]+") do
      if line ~= "" then
        local status, path = line:match("%s*(%S+)%s+(%S+)")
        local new_path = nil
        if status and path then
          if status == "ADDED" then
            status = "added"
          elseif status == "DELETED" then
            status = "deleted"
          elseif status == "EDITED" then
            status = "edited"
          elseif status == "RENAMED" then
            status = "renamed"
            new_path = line:match("%s*%S+%s+%S+%s*%S+%s*(%S+)")
          elseif status == "EXTRA" then
            status = "untracked"
          end
          table.insert(changes, {
            status = status,
            path = directory .. PATHSEP .. path,
            new_path = new_path and (directory .. PATHSEP .. new_path) or nil
          })
        end
      end
      self:yield()
      iterations = iterations + 1
    end
    self:add_to_cache("get_changes", changes, directory)
    callback(changes)
  end, directory, "changes", "--differ")
end

---@param directory string
---@param callback plugins.scm.backend.ongetdiff
function Fossil:get_diff(directory, callback)
  self:execute(function(proc)
    local diff = self:get_process_output(proc, "stdout")
    callback(diff)
  end, directory, "diff")
end

---@param file string
---@param callback plugins.scm.backend.ongetdiff
function Fossil:get_file_diff(file, directory, callback)
  local cached = self:get_from_cache("get_file_diff", file)
  if cached then callback(cached, true) return end
  self:execute(function(proc)
    local diff = self:get_process_output(proc, "stdout")
    self:add_to_cache("get_file_diff", diff, directory, 1)
    callback(diff)
  end, directory, "diff", common.relative_path(directory, file))
end

---@param file string
---@param directory string
---@param callback plugins.scm.backend.ongetfilestatus
function Fossil:get_file_status(file, directory, callback)
  local cached = self:get_from_cache("get_file_status", file)
  if cached then callback(cached, true) return end
  self:execute(function(proc)
    local status = "unchanged"
    local output = self:get_process_output(proc, "stdout")
    for line in output:gmatch("[^\n]+") do
      if line ~= "" then
        status = line:match("^%S+")
        if status then
          if status == "new" then
            status = "added"
          elseif status == "deleted" then
            status = "deleted"
          elseif status == "edited" then
            status = "edited"
          elseif status == "renamed" then
            status = "renamed"
          elseif status == "unchanged" then
            status = "unchanged"
          elseif status == "unknown" then
            status = "untracked"
          end
          break
        end
      end
      self:yield()
    end
    self:add_to_cache("get_file_status", status, file, 1)
    callback(status)
  end, directory, "finfo", "-s", common.relative_path(directory, file))

end

---@param callback plugins.scm.backend.ongetstats
function Fossil:get_stats(directory, callback)
  local cached = self:get_from_cache("get_stats", directory)
  if cached then callback(cached, true) return end
  self:execute(function(proc)
    local inserts = 0
    local deletes = 0
    local last_line = ""
    for line in self:get_process_lines(proc, "stdout") do
      if line ~= "" then
        last_line = line
      end
      self:yield()
    end
    local i, d = last_line:match("%s*(%d+)%s+(%d+)")
    inserts = tonumber(i) or 0
    deletes = tonumber(d) or 0
    local stats = {inserts = inserts, deletes = deletes}
    self:add_to_cache("get_stats", stats, directory, 5)
    callback(stats)
  end, directory, "diff", "--numstat")
end

---@param directory string Project directory
---@param callback plugins.scm.backend.ongetstatus
function Fossil:get_status(directory, callback)
  self:execute(function(proc)
    local status = ""
    local stdout = self:get_process_output(proc, "stdout")
    local stderr = self:get_process_output(proc, "stderr")
    if stderr ~= "" then
      status = stderr
    elseif stdout ~= "" then
      status = stdout
    end
    callback(status)
  end, directory, "status")
end

---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
function Fossil:pull(directory, callback)
  self:execute(function(proc)
    local success = false
    local errmsg = ""
    local stdout = self:get_process_output(proc, "stdout")
    local stderr = self:get_process_output(proc, "stderr")
    if proc:returncode() == 0 then
      success = true
    else
      if stderr ~= "" then
        errmsg = stderr
      elseif stdout ~= "" then
        errmsg = stdout
      end
    end
    callback(success, errmsg)
  end, directory, "pull")
end

---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
function Fossil:revert_file(file, directory, callback)
  self:execute(function(proc)
    local success = false
    local errmsg = ""
    local stdout = self:get_process_output(proc, "stdout")
    local stderr = self:get_process_output(proc, "stderr")
    if proc:returncode() == 0 then
      success = true
    else
      if stderr ~= "" then
        errmsg = stderr
      elseif stdout ~= "" then
        errmsg = stdout
      end
    end
    callback(success, errmsg)
  end, directory, "revert", common.relative_path(directory, file))
end

---@param path string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
function Fossil:add_path(path, directory, callback)
  self:execute(function(proc)
    local success = false
    local errmsg = ""
    local stdout = self:get_process_output(proc, "stdout")
    local stderr = self:get_process_output(proc, "stderr")
    if proc:returncode() == 0 then
      success = true
    else
      if stderr ~= "" then
        errmsg = stderr
      elseif stdout ~= "" then
        errmsg = stdout
      end
    end
    callback(success, errmsg)
  end, directory, "add", common.relative_path(directory, path))
end

---@param path string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
function Fossil:remove_path(path, directory, callback)
  self:execute(function(proc)
    local success = false
    local errmsg = ""
    local stdout = self:get_process_output(proc, "stdout")
    local stderr = self:get_process_output(proc, "stderr")
    if proc:returncode() == 0 then
      success = true
    else
      if stderr ~= "" then
        errmsg = stderr
      elseif stdout ~= "" then
        errmsg = stdout
      end
    end
    callback(success, errmsg)
  end, directory, "rm", common.relative_path(directory, path))
end

---@param from string Path to move
---@param to string Destination of from path
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
function Fossil:move_path(from, to, directory, callback)
  self:execute(
    function(proc)
      local success = false
      local errmsg = ""
      local stdout = self:get_process_output(proc, "stdout")
      local stderr = self:get_process_output(proc, "stderr")
      if proc:returncode() == 0 then
        success = true
      else
        if stderr ~= "" then
          errmsg = stderr
        elseif stdout ~= "" then
          errmsg = stdout
        end
      end
      callback(success, errmsg)
    end,
    directory, "mv",
    common.relative_path(directory, from),
    common.relative_path(directory, to)
  )
end


return Fossil
