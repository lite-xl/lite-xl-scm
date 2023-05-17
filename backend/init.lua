local core = require "core"
local util = require "plugins.scm.util"
local Object = require "core.object"

---@alias plugins.scm.backend.filestatus
---| "added"
---| "edited"
---| "deleted"
---| "renamed"
---| "unchanged"
---| "untracked"

---@class plugins.scm.backend.filechange
---@field status plugins.scm.backend.filestatus
---@field staged boolean
---@field path string
---@field new_path string?

---@class plugins.scm.backend.stats
---@field inserts integer
---@field deletes integer

---@class plugins.scm.backend.cache
---@field name string
---@field path string
---@field expires number
---@field value any

---@class plugins.scm.backend.commit
---@field hash string
---@field author string
---@field date string
---@field summary string
---@field message string

---@class plugins.scm.backend.blame
---@field commit string
---@field author string
---@field date string

---@alias plugins.scm.backend.onexecute fun(proc?:process, errmsg?:string, errcode?:number)
---@alias plugins.scm.backend.ongetdiff fun(diff?:string, cached?:boolean)
---@alias plugins.scm.backend.ongetbranch fun(branch?:string, cached?:boolean)
---@alias plugins.scm.backend.ongetchanges fun(changes:plugins.scm.backend.filechange[], cached?:boolean)
---@alias plugins.scm.backend.ongetcommit fun(changes:plugins.scm.backend.commit, cached?:boolean)
---@alias plugins.scm.backend.ongetfilestatus fun(status?:plugins.scm.backend.filestatus, cached?:boolean)
---@alias plugins.scm.backend.ongetfileblame fun(list?:plugins.scm.backend.blame[], cached?:boolean)
---@alias plugins.scm.backend.ongetstaged fun(files?:table<string,boolean>, cached?:boolean)
---@alias plugins.scm.backend.ongetstats fun(stats?:plugins.scm.backend.stats, cached?:boolean)
---@alias plugins.scm.backend.ongetstatus fun(status?:string, cached?:boolean)
---@alias plugins.scm.backend.onexecstatus fun(success:boolean, errmsg?:string)

---Base functionality to implement a SCM backend with async support.
---@class plugins.scm.backend : core.object
---@field name string
---@field blocking boolean
---@field command string
---@field cache plugins.scm.backend.cache[]
---@field super plugins.scm.backend
local Backend = Object:extend()

---Constructor
---@param name string
---@param command string
function Backend:new(name, command)
  self.name = name
  self.cache = {}
  self.next_clean = os.time() + 20
  self.blocking = false
  self:set_command(command)
end

---Set the path to the scm executable.
---@param command string
---@return boolean found
function Backend:set_command(command)
  if util.command_exists(command) then
    self.command = command
    return true
  end
  self.command = nil
  return false
end

---Execute coroutine.yield if blocking mode is disabled.
---@param wait? number
function Backend:yield(wait)
  if not self.blocking then
    coroutine.yield(wait)
  end
end

---Enable or disable coroutine execution of process calls.
---@param enabled boolean
function Backend:set_blocking_mode(enabled)
  self.blocking = enabled
end

---Add a value into a temporary cache, this is useful to cache the ouput
---of commands for faster retrieveal until the given expire period.
---@param name string
---@param value any
---@param path string
---@param expires? integer Amount of seconds to expire, defaults to 5
function Backend:add_to_cache(name, value, path, expires)
  local found = nil
  for i, cache in ipairs(self.cache) do
    if cache.name == name and cache.path == path then
      found = i
      break
    end
  end

  if found then
    self.cache[found].value = value
    self.cache[found].expires = os.time() + (expires or 5)
  else
    table.insert(self.cache, {
      name = name,
      value = value,
      path = path,
      expires = os.time() + (expires or 5)
    })
  end
end

---Removes all expired cached elements.
function Backend:clean_cache()
  local current_time = os.time()

  if self.next_clean > current_time then return end

  local deleted = 0
  for i=1, #self.cache do
    local cache = self.cache[i-deleted]
    if cache.expires < current_time then
      table.remove(self.cache, i-deleted)
      deleted = deleted + 1
    end
  end

  self.next_clean = current_time + 20
end

---Get a value that was previously stored on the cache.
---@param name string
---@param path string
function Backend:get_from_cache(name, path)
  self:clean_cache()

  local found = nil
  for i, cache in ipairs(self.cache) do
    if cache.name == name and cache.path == path then
      found = i
      break
    end
  end

  if found then
    if self.cache[found].expires >= os.time() then
      return self.cache[found].value
    end
    table.remove(self.cache, found)
  end

  return nil
end

---Iterates over all the lines that the running process is outputting.
---The iterator can return an empty line while the process gets ready to output.
---@param proc process
---@param from? string | "stdout" | "stderr"
---@return fun():integer,string
function Backend:get_process_lines(proc, from)
  local output = self:get_process_output(proc, from)
  return coroutine.wrap(function()
    local line_num = 1
    for line in (output.."\n"):gmatch("(.-)".."\n") do
      coroutine.yield(line_num, line)
      line_num = line_num + 1
    end
  end)
end

---Gets all the output of the process at once, this function yields
---while reading to allow async support when ran from a coroutine.
---@param proc process
---@param from? string | "stdout" | "stderr"
---@return string
function Backend:get_process_output(proc, from)
  if not proc then return "" end
  from = from and "read_" .. from or "read_stdout"
  local output = ""
  local read_size = 1024 * 10
  local read = proc[from](proc, read_size)
  repeat
    if read ~= nil and read ~= "" then
      output = output .. read
    end
    self:yield(0.01)
    read = proc[from](proc, read_size)
  until (read == nil or read == "") and not proc:running()
  return output
end

---Call the scm command with the given parameters.
---@param callback plugins.scm.backend.onexecute
---@param directory string Path of project directory
---@param ... string parameters to pass to associated command
function Backend:execute(callback, directory, ...)
  if not self.command then return end
  local command = table.pack(self.command, ...)
  local proc, errmsg, errcode
  local ran, ranerr = core.try(function()
    proc, errmsg, errcode = process.start(command, {cwd = directory})
    if not self.blocking then
      core.add_thread(function()
        callback(proc, errmsg, errcode)
        if proc and proc:running() then proc:kill() end
      end)
    else
      callback(proc, errmsg, errcode)
      if proc and proc:running() then proc:kill() end
    end
  end)
  if not proc then
    local msg_code = ran and {errmsg, errcode} or {ranerr, "-1"}
    core.error(
      "[SCM error]: error while executing '%s' - %s:%s",
      table.concat(command, " "),
      table.unpack(msg_code)
    )
  end
end

---Check if given directory is source controlled by current backend.
---@param directory string Project directory
---@return boolean detected
---@diagnostic disable-next-line
function Backend:detect(directory) return false end

---Report if the backend has a staging area.
---@return boolean
function Backend:has_staging() return false end

---Add a file path to staging area.
---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:stage_file(file, directory, callback) callback(false, "not implemented") end

---Remove a file path from staging area.
---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:unstage_file(file, directory, callback) callback(false, "not implemented") end

---Retrieve the list of all staged files.
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetstaged
---@diagnostic disable-next-line
function Backend:get_staged(directory, callback) callback(nil) end

---Retrieve the current branch.
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetbranch
---@diagnostic disable-next-line
function Backend:get_branch(directory, callback) callback(nil) end

---Retrieve a list of file changes.
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetchanges
---@diagnostic disable-next-line
function Backend:get_changes(directory, callback) callback({}, false) end

---Retrieve the entire project unified diff.
---@param id string Hash of the commit
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetcommit
---@diagnostic disable-next-line
function Backend:get_commit_info(id, directory, callback) callback(nil) end

---Retrieve the diff for a given commit.
---@param id string Hash of the commit
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetdiff
---@diagnostic disable-next-line
function Backend:get_commit_diff(id, directory, callback) callback(nil) end

---Retrieve the entire project unified diff.
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetdiff
---@diagnostic disable-next-line
function Backend:get_diff(directory, callback) callback(nil) end

---Retrieve the unified diff for the given file.
---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetdiff
---@diagnostic disable-next-line
function Backend:get_file_diff(file, directory, callback) callback(nil) end

---Retrieve the current status of the given file.
---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetfilestatus
---@diagnostic disable-next-line
function Backend:get_file_status(file, directory, callback) callback("unchanged") end

---Retrieve the blame information for every line on a file.
---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetfileblame
---@diagnostic disable-next-line
function Backend:get_file_blame(file, directory, callback) callback(nil) end

---Retrieve insertion and deletion stats for an entire project.
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetstats
---@diagnostic disable-next-line
function Backend:get_stats(directory, callback) callback({0, 0}) end

---Retrieve the status description for an entire repo.
---@param directory string Project directory
---@param callback plugins.scm.backend.ongetstatus
---@diagnostic disable-next-line
function Backend:get_status(directory, callback) callback(nil) end

---Pull latest changes.
---TODO: this is a WIP we should handle remote and branch
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:pull(directory, callback) callback(false, "not implemented") end

---Restore a file to its previous HEAD state before any changes.
---@param file string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:revert_file(file, directory, callback) callback(false, "not implemented") end

---Add a directory or file to repository
---@param path string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:add_path(path, directory, callback) callback(false, "not implemented") end

---Remove a file or directory from repository without deleting it.
---@param path string Absolute path to file
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:remove_path(path, directory, callback) callback(false, "not implemented") end

---Rename a path of a directory or file in the repository.
---@param from string Path to move
---@param to string Destination of from path
---@param directory string Project directory
---@param callback plugins.scm.backend.onexecstatus
---@diagnostic disable-next-line
function Backend:move_path(from, to, directory, callback) callback(false, "not implemented") end


return Backend
