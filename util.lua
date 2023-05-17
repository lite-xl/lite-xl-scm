local core = require "core"
local common = require "core.common"
local DocView = require "core.docview"

---Utility functions for the SCM plugin.
local util = {}

---@return string project_dir
function util.get_current_project()
  if core.active_view and core.active_view.doc and core.active_view.doc.abs_filename then
    local filename = core.active_view.doc.abs_filename
    for _, project in ipairs(core.project_directories) do
      if common.path_belongs_to(filename, project.name) then
        return project.name
      end
    end
  end
  return core.project_dir
end

---@param filepath string
---@return string? project_dir
function util.get_file_project_dir(filepath)
  for _, project in ipairs(core.project_directories) do
    if common.path_belongs_to(filepath, project.name) then
      return project.name
    end
  end
  return nil
end

---Get project directory for given file or current project dir if non given.
---@param filepath? string
---@return string? project_dir
function util.get_project_dir(filepath)
  local project
  if not filepath then
    project = util.get_current_project()
  else
    project = util.get_file_project_dir(filepath)
  end
  return project
end

function util.reload_doc(abs_filename)
  for _, doc in ipairs(core.docs) do
    if doc.abs_filename == abs_filename then
      doc:reload()
      break
    end
  end
end

---@return core.doc?
function util.get_current_doc()
  if core.active_view and core.active_view:extends(DocView) then
    local doc = core.active_view.doc
    if doc and doc.abs_filename then
      return doc
    end
  end
  return nil
end

---Split a string by the given delimeter
---@param s string The string to split
---@param delimeter string Delimeter without lua patterns
---@param delimeter_pattern? string Optional delimeter with lua patterns
---@return table
function util.split(s, delimeter, delimeter_pattern)
  if not delimeter_pattern then
    delimeter_pattern = delimeter
  end

  local result = {};
  for match in (s..delimeter):gmatch("(.-)"..delimeter_pattern) do
    table.insert(result, match);
  end
  return result;
end

---Check if a file exists.
---@param file_path string
---@return boolean
function util.file_exists(file_path)
  local file = io.open(file_path, "r")
  if file ~= nil then
    file:close()
    return true
  end
 return false
end

---Check if a command exists on the system by inspecting the PATH envar.
---@param command string
---@return boolean
function util.command_exists(command)
  local command_win = nil

  if PLATFORM == "Windows" then
    if not command:find("%.exe$") then
      command_win = command .. ".exe"
    end
  end

  if
    util.file_exists(command)
    or
    (command_win and util.file_exists(command_win))
  then
    return true
  end

  local env_path = os.getenv("PATH")

  if env_path then
    local path_list = {}

    if PLATFORM ~= "Windows" then
      path_list = util.split(env_path, ":")
    else
      path_list = util.split(env_path, ";")
    end

    -- Automatic support for brew, macports, etc...
    if PLATFORM == "Mac OS X" then
      if
        system.get_file_info("/usr/local/bin")
        and
        not string.find(env_path, "/usr/local/bin", 1, true)
      then
        table.insert(path_list, 1, "/usr/local/bin")
      end
    end

    for _, path in pairs(path_list) do
      local path_fix = path:gsub("[/\\]$", "") .. PATHSEP
      if util.file_exists(path_fix .. command) then
        return true
      elseif command_win and util.file_exists(path_fix .. command_win) then
        return true
      end
    end
  end

  return false
end


return util
