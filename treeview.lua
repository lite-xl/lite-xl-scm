local core = require "core"
local config = require "core.config"

-- Delay loading of TreeView changes to properly check if the plugin is enabled.
core.add_thread(function()

-- Load treeview if enabled to add menu entries
---@module 'plugins.treeview'
local TreeView
---@module 'core.contextmenu'
local TreeViewMenu

if config.plugins.treeview ~= false then
  TreeView = require "plugins.treeview"
  TreeViewMenu = TreeView.contextmenu
else
  return
end

local scm = require "plugins.scm"
local command = require "core.command"

--------------------------------------------------------------------------------
-- Override treeview to change color of files depending on status
--------------------------------------------------------------------------------
local treeview_get_item_text = TreeView.get_item_text
function TreeView:get_item_text(item, active, hovered)
  local text, font, color = treeview_get_item_text(self, item, active, hovered)
  local path = item.abs_filename
  local status = scm.get_path_changes(path)
  if status then
    if status.text then text = status.text end
    color = status.color
  end
  return text, font, color
end

--------------------------------------------------------------------------------
-- Add entries to treeview contextmenu
--------------------------------------------------------------------------------

-- Entries when right clicking project root
TreeViewMenu:register(
  function()
    return TreeView.hovered_item
      and scm.is_scm_project(TreeView.hovered_item.abs_filename)
  end,
  {
    TreeViewMenu.DIVIDER,
    { text = "Pull From Remote", command = "treeview:scm-pull" },
    { text = "View Changes Diff", command = "treeview:scm-global-diff" },
    { text = "View Project Status", command = "treeview:scm-project-status" }
  }
)

TreeViewMenu:register(function()
    return TreeView.hovered_item
      and scm.get_path_backend(TreeView.hovered_item.abs_filename)
    end, {
    TreeViewMenu.DIVIDER,
    { text = "Add to Repo", command = "treeview:scm-path-add" },
    { text = "Remove from Repo", command = "treeview:scm-path-remove" },
    { text = "Add to Staging", command = "treeview:scm-staging-add" },
    { text = "Remove from Staging", command = "treeview:scm-staging-remove" },
    { text = "Revert Changes", command = "treeview:scm-file-revert" },
    { text = "View Changes Diff", command = "treeview:scm-file-diff" },
})

--------------------------------------------------------------------------------
-- Register treeview commands
--------------------------------------------------------------------------------
command.add(
  function()
    return TreeView.hovered_item
      and scm.is_scm_project(TreeView.hovered_item.abs_filename)
  end, {

  ["treeview:scm-pull"] = function()
    scm.pull(TreeView.hovered_item.abs_filename)
  end,

  ["treeview:scm-global-diff"] = function()
    scm.open_diff(TreeView.hovered_item.abs_filename)
  end,

  ["treeview:scm-project-status"] = function()
    scm.open_project_status(TreeView.hovered_item.abs_filename)
  end
})

command.add(
  function()
    return TreeView.hovered_item
      and scm.get_path_backend(TreeView.hovered_item.abs_filename)
      and scm.get_path_status(TreeView.hovered_item.abs_filename) == "untracked"
  end, {

  ["treeview:scm-path-add"] = function()
    scm.add_path(TreeView.hovered_item.abs_filename)
  end
})

command.add(
  function()
    return TreeView.hovered_item
      and scm.get_path_status(TreeView.hovered_item.abs_filename) == "unchanged"
  end, {

  ["treeview:scm-path-remove"] = function()
    scm.remove_path(TreeView.hovered_item.abs_filename)
  end
})

command.add(
  function()
    if TreeView.hovered_item then
      local path = TreeView.hovered_item.abs_filename
      local status = scm.get_path_status(path)
      if status == "edited" and not scm.is_staged(path) then
        local backend = scm.get_path_backend(path)
        if backend and backend:has_staging() then
          return true
        end
      end
    end
    return false
  end, {

  ["treeview:scm-staging-add"] = function()
    scm.stage_file(TreeView.hovered_item.abs_filename)
  end
})

command.add(
  function()
    if TreeView.hovered_item then
      local backend = scm.get_path_backend(TreeView.hovered_item.abs_filename)
      if backend and backend:has_staging() then
        if scm.is_staged(TreeView.hovered_item.abs_filename) then
          return true
        end
      end
    end
    return false
  end, {

  ["treeview:scm-staging-remove"] = function()
    scm.unstage_file(TreeView.hovered_item.abs_filename)
  end
})

command.add(
  function()
    if TreeView.hovered_item then
      local path = TreeView.hovered_item.abs_filename
      local status = scm.get_path_status(path)
      local backend = scm.get_path_backend(path)
      if backend and backend:has_staging() then
        if status == "edited" and not scm.is_staged(path) then
          return true
        end
      elseif backend then
        return scm.get_path_backend(
          TreeView.hovered_item.abs_filename, true, true
        )
      end
    end
    return false
  end, {

  ["treeview:scm-file-revert"] = function()
    scm.revert_file(TreeView.hovered_item.abs_filename)
  end,
})

command.add(
  function()
    return TreeView.hovered_item
      and scm.get_path_status(TreeView.hovered_item.abs_filename) == "edited"
      and not scm.is_staged(TreeView.hovered_item.abs_filename)
  end, {

  ["treeview:scm-file-diff"] = function()
    scm.open_path_diff(TreeView.hovered_item.abs_filename)
  end
})

end) -- end initialization coroutine
