local core = require "core"
local common = require "core.common"
local DocView = require "core.docview"

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


return util
