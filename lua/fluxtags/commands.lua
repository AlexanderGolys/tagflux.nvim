local M = {}

---@alias FluxtagsKind "mark"|"ref"|"refog"|"bib"|"og"|"hl"|"cfg"

---@class FluxtagsKindHelpItem
---@field syntax string
---@field info string

---@type table<FluxtagsKind, FluxtagsKindHelpItem>
local KIND_HELP = {
  mark = { syntax = "-- @@@<name>", info = "Named anchors persisted to tagfiles; refs jump to these." },
  ref = { syntax = "/@@<name> or @<base>.<subtag>", info = "References to marks; resolves base name on Ctrl-]." },
  refog = { syntax = "#|#||<name>||", info = "Reference-only OG jump tag; does not create saved hashtag entries." },
  bib = { syntax = "-- ///<target>", info = "External links (URL/file/help topic); opens target on Ctrl-]." },
  og = { syntax = "@##<name>", info = "Topic hashtags across files; Ctrl-] opens a picker of occurrences." },
  hl = { syntax = "&&&<HlGroup>&&&<text>&&&", info = "Inline styled text using any Neovim highlight group." },
  cfg = { syntax = "$$$<key>(<value>)", info = "Buffer-local config directives applied on enter." },
}

local PREVIEW_KINDS = { "mark", "ref", "refog", "bib", "og", "hl", "cfg" }

local KIND_SYMBOLS = { mark = "@", ref = "&", refog = "#", og = "#", cfg = "$", hl = "%", bib = "/" }

---@param kind string
---@return boolean
local function notify_kind_help(kind)
  local item = KIND_HELP[kind]
  if not item then
    return false
  end
  vim.notify(("[%s] %s\n%s"):format(kind, item.syntax, item.info), vim.log.levels.INFO)
  return true
end

---@return FluxtagsKind[]
local function preview_kinds()
  return PREVIEW_KINDS
end

---@return table<FluxtagsKind, FluxtagsKindHelpItem>
local function kind_help()
  return KIND_HELP
end

---@param kind FluxtagsKind|string
---@return string
local function kind_symbol(kind)
  return KIND_SYMBOLS[kind] or "?"
end

---@param title string
---@param items {text:string, ordinal?:string}[]
---@return boolean
local function pick_static_items(title, items)
  local ok_telescope, pickers = pcall(require, "telescope.pickers")
  if not ok_telescope then
    return false
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = items,
      entry_maker = function(entry)
        return { value = entry, display = entry.text, ordinal = entry.ordinal or entry.text }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
      end)
      return true
    end,
  }):find()

  return true
end

---@param tag_kinds table<string, TagKind>
---@param load_tagfile fun(kind_name: string): table
---@param kind_filter? string
---@return table[]
local function collect_entries(tag_kinds, load_tagfile, kind_filter)
  local entries = {}
  for kind_name, kind in pairs(tag_kinds) do
    if kind.save_to_tagfile and (not kind_filter or kind_name == kind_filter) then
      for name, tag_entries in pairs(load_tagfile(kind_name)) do
        for _, e in ipairs(tag_entries) do
          table.insert(entries, {
            kind = kind_name,
            name = name,
            file = e.file,
            lnum = e.lnum,
            col = e.col,
            text = ("[%s] %s"):format(kind_symbol(kind_name), name),
          })
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.text < b.text
  end)
  return entries
end

---@param title string
---@param entries table[]
---@param on_confirm fun(entry: table)
local function pick_tag_entries(title, entries, on_confirm)
  local ok_telescope, telescope = pcall(require, "telescope.pickers")
  if ok_telescope then
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")

    telescope.new({}, {
      prompt_title = title,
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.text,
            ordinal = entry.kind .. entry.name .. entry.file .. entry.lnum,
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        define_preview = function(self, entry)
          conf.buffer_previewer_maker(entry.value.file, self.state.bufnr, { bufname = self.state.bufname })
          vim.api.nvim_buf_call(self.state.bufnr, function()
            vim.fn.cursor(entry.value.lnum, 1)
          end)
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.value then
            on_confirm(selection.value)
          end
        end)
        return true
      end,
    }):find()
    return
  end

  local lines = {}
  for _, entry in ipairs(entries) do
    table.insert(lines, entry.text)
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param fluxtags table
---@param tag_kinds table<string, TagKind>
---@param entry {kind:string,name:string,file:string,lnum:number}
local function jump_to_picker_entry(fluxtags, tag_kinds, entry)
  local kind = tag_kinds[entry.kind]
  local prefix = kind and kind.open or ""
  fluxtags.utils.open_file(entry.file, { bufnr = vim.api.nvim_get_current_buf() })
  local line = vim.api.nvim_buf_get_lines(0, entry.lnum - 1, entry.lnum, false)[1] or ""
  local col = line:find(prefix .. entry.name, 1, true)
  vim.fn.cursor(entry.lnum, col or 1)
end

---@param load_tagfile fun(kind_name:string):table
---@param output_file? string
local function generate_tree(load_tagfile, output_file)
  local marks = load_tagfile("mark") or {}
  local ogs = load_tagfile("og") or {}
  local cwd_prefix = vim.loop.cwd() .. "/"

  local function relpath(path)
    return path:gsub("^" .. cwd_prefix, "")
  end

  local lines = {
    "# Fluxtags Project Tree",
    "",
    "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"),
    "",
  }

  if next(marks) then
    table.insert(lines, "## Marks (@@@name)")
    table.insert(lines, "")
    local sorted_marks = {}
    for name, entries in pairs(marks) do
      table.insert(sorted_marks, { name = name, entry = entries[1] })
    end
    table.sort(sorted_marks, function(a, b)
      return a.name < b.name
    end)
    for _, item in ipairs(sorted_marks) do
      table.insert(lines, ("- `@@@%s` — %s:%d"):format(item.name, relpath(item.entry.file), item.entry.lnum))
    end
    table.insert(lines, "")
  end

  if next(ogs) then
    table.insert(lines, "## Topics (@##name)")
    table.insert(lines, "")
    local sorted_ogs = {}
    for name, entries in pairs(ogs) do
      table.insert(sorted_ogs, { name = name, entries = entries })
    end
    table.sort(sorted_ogs, function(a, b)
      return a.name < b.name
    end)

    for _, item in ipairs(sorted_ogs) do
      table.insert(lines, ("### @##%s (%d occurrences)"):format(item.name, #item.entries))
      for _, tree_entry in ipairs(item.entries) do
        table.insert(lines, ("  - %s:%d"):format(relpath(tree_entry.file), tree_entry.lnum))
      end
      table.insert(lines, "")
    end
  end

  if output_file then
    vim.fn.writefile(lines, output_file)
    vim.notify(("Project tree written to %s (%d lines)"):format(output_file, #lines), vim.log.levels.INFO)
  else
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end
end

---@param ns number
---@param tag_kinds table<string, TagKind>
local function setup_debug_commands(ns, tag_kinds)
  vim.api.nvim_create_user_command("FTagsDebug", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_get_current_line()
    local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    local info = {
      buffer = bufnr,
      conceallevel = vim.opt_local.conceallevel:get(),
      concealcursor = vim.opt_local.concealcursor:get(),
      extmarks = #all_extmarks,
      kinds = {},
    }

    for name, kind in pairs(tag_kinds) do
      local matches = {}
      for m in line:gmatch(kind.pattern) do
        table.insert(matches, m)
      end
      table.insert(info.kinds, {
        name = name,
        pattern = kind.pattern,
        hl_group = kind.hl_group,
        hl = kind.hl_group and vim.api.nvim_get_hl(0, { name = kind.hl_group }) or nil,
        priority = kind.priority,
        matches = matches,
      })
    end

    vim.notify(vim.inspect(info), vim.log.levels.INFO)
  end, { desc = "Dump fluxtags debug info for current line" })

  vim.api.nvim_create_user_command("FTagsDebugMarks", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    vim.notify(vim.inspect(marks), vim.log.levels.INFO)
  end, { desc = "Dump all fluxtags extmarks in current buffer" })

  vim.api.nvim_create_user_command("FTagsDebugAtCursor", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local row = vim.fn.line(".") - 1
    local col = vim.fn.col(".") - 1
    local line_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 }, { details = true })
    local at_cursor = {}

    for _, mark in ipairs(line_marks) do
      local start_col = mark[3]
      local details = mark[4] or {}
      local end_col = details.end_col or start_col
      local end_row = details.end_row or row
      if end_row == row and col >= start_col and col < end_col then
        table.insert(at_cursor, mark)
      end
    end

    vim.notify(vim.inspect({ row = row, col = col, marks = at_cursor }), vim.log.levels.INFO)
  end, { desc = "Dump fluxtags extmarks covering the cursor" })
end

---@class FluxtagsCommands
---@field private fluxtags table
---@field private ns number
---@field private tag_kinds table<string, TagKind>
---@field private load_tagfile fun(kind_name: string): table<string, { file:string, lnum:number, col?:number }[]>
---@field private prune_tagfile fun(kind_name: string): integer
---@field private setup_buffer fun(bufnr: integer|nil, force: boolean)
---@field private config_mod table
local Commands = {}
Commands.__index = Commands

---@param fluxtags table
---@return FluxtagsCommands
function Commands.new(fluxtags)
  ---@type FluxtagsCommands
  return setmetatable({
    fluxtags = fluxtags,
    ns = fluxtags.utils.ns,
    tag_kinds = fluxtags.tag_kinds,
    load_tagfile = fluxtags.load_tagfile,
    prune_tagfile = fluxtags.prune_tagfile,
    setup_buffer = fluxtags.setup_buffer,
    config_mod = require("fluxtags_config"),
  }, Commands)
end

---@param name string
---@param callback fun(opts: vim.api.keyset.user_command)
---@param opts vim.api.keyset.user_command
function Commands:_register(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
end

---@return table
function Commands:_pickable_kinds()
  local kinds = {}
  for name, kind in pairs(self.tag_kinds) do
    if kind.save_to_tagfile then
      table.insert(kinds, name)
    end
  end
  table.sort(kinds)
  return kinds
end

function Commands:_notify_info(message)
  vim.notify(message, vim.log.levels.INFO)
end

function Commands:_notify_error(message)
  vim.notify(message, vim.log.levels.ERROR)
end

function Commands:_update_tags()
  self.fluxtags.update_tags(false)
end

function Commands:_load_all()
  local total = self.fluxtags.load_all_tags()
  self:_notify_info(total > 0 and ("Loaded %d tags"):format(total) or "No tags")
end

function Commands:_reapply_buffer_highlights()
  self.setup_buffer(nil, true)
end

function Commands:_relink_highlights()
  self.config_mod.setup_default_highlights(self.fluxtags.config.highlights)
end

function Commands:_list_tags(opts)
  local kind_filter = opts.args ~= "" and opts.args or nil
  if kind_filter and not self.tag_kinds[kind_filter] then
    self:_notify_error("Unknown tag kind: " .. kind_filter)
    return
  end

  local entries = collect_entries(self.tag_kinds, self.load_tagfile, kind_filter)
  if #entries == 0 then
    self:_notify_info("No tags")
    return
  end

  local title = kind_filter and ("Tags (" .. kind_filter .. ")") or "Tags"
  pick_tag_entries(title, entries, function(entry)
    jump_to_picker_entry(self.fluxtags, self.tag_kinds, entry)
  end)
end

function Commands:_cfg_list()
  local directives = require("tagkinds.cfg").get_directives_info()
  if #directives == 0 then
    self:_notify_info("No cfg directives registered")
    return
  end

  local items = {}
  for _, item in ipairs(directives) do
    table.insert(items, {
      text = ("%-16s %s"):format(item.key, item.description),
      ordinal = item.key,
    })
  end

  if pick_static_items("Cfg Directives", items) then
    return
  end

  local lines = { "Cfg Directives:" }
  for _, item in ipairs(items) do
    table.insert(lines, "  " .. item.text)
  end
  self:_notify_info(table.concat(lines, "\n"))
end

function Commands:_preview(opts)
  local kind = opts.args ~= "" and opts.args or nil
  if kind then
    if not notify_kind_help(kind) then
      self:_notify_error("Unknown tag kind: " .. kind)
    end
    return
  end

  local lines = { "Tag kinds:" }
  local help = kind_help()
  for _, key in ipairs(preview_kinds()) do
    table.insert(lines, ("  %-5s %s"):format(key .. ":", help[key].syntax))
  end
  table.insert(lines, "")
  table.insert(lines, "Use :FTagsPreview <kind> for details.")
  self:_notify_info(table.concat(lines, "\n"))
end

function Commands:_tree(opts)
  if not self.load_tagfile then
    return
  end
  generate_tree(self.load_tagfile, opts.args ~= "" and opts.args or nil)
end

function Commands:_clear()
  local cleared = 0
  for _, kind in pairs(self.tag_kinds) do
    if kind.save_to_tagfile and kind.tagfile then
      vim.fn.writefile({}, kind.tagfile)
      cleared = cleared + 1
    end
  end
  self:_notify_info(("Cleared %d tagfiles"):format(cleared))
end

function Commands:_prune()
  local removed = 0
  for kind_name, kind in pairs(self.tag_kinds) do
    if kind.save_to_tagfile then
      removed = removed + self.prune_tagfile(kind_name)
    end
  end
  self:_notify_info(("Removed %d stale tag entries"):format(removed))
end

function Commands:_setup_debug_commands()
  setup_debug_commands(self.ns, self.tag_kinds)
end

function Commands:setup_keymap()
  vim.keymap.set("n", "<C-]>", self.fluxtags.jump_to_tag, { desc = "Jump to fluxtag under cursor" })
end

---@param fluxtags table
function Commands:setup()
  self:_register("FTagsUpdate", function()
    self:_update_tags()
  end, {
    desc = "Scan buffer and persist tags to tagfiles",
  })
  self:_register("FTagsSave", function()
    self:_update_tags()
  end, {
    desc = "Alias for FTagsUpdate",
  })
  self:_register("FTagsLoad", function()
    self:_load_all()
  end, {
    desc = "Load all tagfiles into memory",
  })
  self:_register("FTagsHL", function()
    self:_reapply_buffer_highlights()
  end, {
    desc = "Re-apply extmarks to current buffer",
  })
  self:_register("FTagsHi", function()
    self:_relink_highlights()
  end, {
    desc = "Re-link default FluxTag highlight groups",
  })
  self:_register("FTagsList", function(opts)
    self:_list_tags(opts)
  end, {
    nargs = "?",
    desc = "Open a picker of saved tags; optional kind argument filters results",
    complete = function()
      return self:_pickable_kinds()
    end,
  })
  self:_register("FTagsCfgList", function()
    self:_cfg_list()
  end, {
    desc = "List all registered cfg directives with descriptions",
  })
  self:_register("FTagsPreview", function(opts)
    self:_preview(opts)
  end, {
    nargs = "?",
    desc = "Show syntax and quick help for tag kinds",
    complete = function()
      return preview_kinds()
    end,
  })
  self:_register("FTagsTree", function(opts)
    self:_tree(opts)
  end, {
    nargs = "?",
    desc = "Generate project tree of marks and og tags (optional output file path)",
  })
  self:_register("FTagsClear", function()
    self:_clear()
  end, {
    desc = "Truncate all tagfiles",
  })
  self:_register("FTagsPrune", function()
    self:_prune()
  end, {
    desc = "Remove stale entries from all tagfiles",
  })

  self:_setup_debug_commands()
  self:setup_keymap()
end

--- @param fluxtags table
function M.setup(fluxtags)
  local commands = Commands.new(fluxtags)
  commands:setup()
end

return M
