-- @@@helplesstags
-- #nvim-plugin

-- |||helplesstags.bib|||
-- |||helplesstags.cfg|||
-- |||helplesstags.hl|||
-- |||helplesstags.og|||
-- |||helplesstags.marks|||

---@class TagmarkEntry
---@field name string The tag name
---@field file string Absolute path to the file
---@field lnum number Line number (1-indexed)

---@class TagmarkLoadedEntry
---@field file string Absolute path to the file
---@field lnum number Line number (1-indexed)
---@field section string Provider name that created this tag

---@class TagmarkJumpContext
---@field line string Current line content
---@field col number Cursor column (1-indexed)
---@field bufnr number Buffer number
---@field provider_name string Name of the matched provider

---@class TagmarkProvider
---@field find_at_cursor? fun(line: string, col: number): string|nil, number|nil, number|nil Find tag at cursor position
---@field apply_extmarks? fun(bufnr: number, lnum: number, line: string, ns: number) Apply extmarks for highlighting/concealing
---@field collect_tags? fun(filepath: string, lines: string[]): TagmarkEntry[] Collect tags from buffer for tagfile
---@field on_jump? fun(name: string, ctx: TagmarkJumpContext): boolean Handle jump to tag, return true if handled
---@field on_enter? fun(bufnr: number, lines: string[]) Called when entering a buffer

local M = {}

---@class TagmarksConfig
---@field update_on_save boolean Whether to update tags on BufWritePost
---@field filetypes string[]|nil Filetypes to track (nil = all)
---@field tagkinds table<string, TagKindConfig>|nil Per-tagkind configuration overrides
M.config = {
  update_on_save = true,
  filetypes = nil,
  tagkinds = nil,
}

local ns = vim.api.nvim_create_namespace("tagflux")

---@type table<string, TagmarkProvider> Registered providers
local providers = {}

local config = require("config")

---Comment prefix patterns for different languages
---@type string[]
local COMMENT_PREFIXES = { "^%s*%-%-+%s*", "^%s*//+%s*", "^%s*#+%s*", "^%s*;+%s*" }

---Find pattern in line with optional comment prefix
---@param line string Line content
---@param pattern string Pattern to find (must capture position as first capture)
---@param start? number Starting position (default: 1)
---@return number|nil s Start position of match (including comment)
---@return number|nil e End position of match
---@return ... Captured groups from pattern
local function find_with_comment(line, pattern, start)
  start = start or 1
  
  -- Try without comment prefix first
  local match = { line:find(pattern, start) }
  if match[1] then
    return unpack(match)
  end
  
  -- Try with comment prefix
  for _, prefix in ipairs(COMMENT_PREFIXES) do
    local comment_pattern = prefix .. pattern
    match = { line:find(comment_pattern, start) }
    if match[1] then
      return unpack(match)
    end
  end
  
  return nil
end

---Iterator for pattern matches in line with optional comment prefix
---@param line string Line content
---@param pattern string Pattern to find (must capture position as first capture)
---@return function iterator Iterator function
local function gmatch_with_comment(line, pattern)
  local results = {}
  
  -- Collect matches without comment prefix
  for match in line:gmatch(pattern) do
    table.insert(results, { match })
  end
  
  -- Collect matches with comment prefix
  for _, prefix in ipairs(COMMENT_PREFIXES) do
    local comment_pattern = prefix .. pattern
    for match in line:gmatch(comment_pattern) do
      table.insert(results, { match })
    end
  end
  
  local i = 0
  return function()
    i = i + 1
    if results[i] then
      return unpack(results[i])
    end
  end
end

---Register a tag provider
---@param name string Unique provider name (used as section in tagfile)
---@param provider TagmarkProvider Provider implementation
function M.register(name, provider)
  providers[name] = provider
end

---Load tags from the tagfile for a specific tag kind
---@param section string Tag kind name (required)
---@return table<string, TagmarkLoadedEntry[]> Map of tag names to their locations
local function load_tagfile(section)
  local tagfile_path = config.get_tagfile(section, M.config.tagkinds)
  
  local tags = {}
  if tagfile_path and vim.fn.filereadable(tagfile_path) == 1 then
    for _, line in ipairs(vim.fn.readfile(tagfile_path)) do
      local sec, name, file, lnum = line:match("^([^:]+):([^\t]+)\t([^\t]+)\t(%d+)")
      if sec and sec == section then
        tags[name] = tags[name] or {}
        table.insert(tags[name], { file = file, lnum = tonumber(lnum), section = sec })
      end
    end
  end
  return tags
end

---Save tags to the tagfile for a specific tag kind
---Removes existing tags for the given section+filepath, then appends new ones.
---@param section string Tag kind name
---@param filepath string Absolute path to the source file
---@param new_tags TagmarkEntry[] Tags to save
local function save_tagfile(section, filepath, new_tags)
  local tagfile_path = config.get_tagfile(section, M.config.tagkinds)
  if not tagfile_path then return end  -- Don't save if tagfile is not configured
  
  local lines = {}

  -- Keep tags from other files/sections
  if vim.fn.filereadable(tagfile_path) == 1 then
    for _, line in ipairs(vim.fn.readfile(tagfile_path)) do
      local sec, _, file = line:match("^([^:]+):([^\t]+)\t([^\t]+)")
      if not (sec == section and file == filepath) then
        table.insert(lines, line)
      end
    end
  end

  -- Append new tags
  for _, tag in ipairs(new_tags) do
    table.insert(lines, string.format("%s:%s\t%s\t%d", section, tag.name, tag.file, tag.lnum))
  end

  table.sort(lines)
  vim.fn.writefile(lines, tagfile_path)
end

---Get highlight group for a tag kind
---@param kind string Tag kind name
---@return string hl_group Highlight group name
local function get_hl_group(kind)
  return config.get_hl_group(kind, M.config.tagkinds)
end

---Utility functions exposed for providers
---@class TagmarksUtils
---@field load_tagfile fun(section?: string): table<string, TagmarkLoadedEntry[]>
---@field save_tagfile fun(section: string, filepath: string, new_tags: TagmarkEntry[])
---@field find_with_comment fun(line: string, pattern: string, start?: number): number|nil, number|nil, ...
---@field gmatch_with_comment fun(line: string, pattern: string): function
---@field get_hl_group fun(kind: string): string
---@field ns number
M.utils = {
  load_tagfile = load_tagfile,
  save_tagfile = save_tagfile,
  find_with_comment = find_with_comment,
  gmatch_with_comment = gmatch_with_comment,
  get_hl_group = get_hl_group,
  ns = ns,
}

---Apply extmarks to a buffer for all providers
---@param bufnr? number Buffer number (default: current)
---@private
local function apply_extmarks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].tagflux_disabled then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    for _, provider in pairs(providers) do
      if provider.apply_extmarks then
        provider.apply_extmarks(bufnr, lnum - 1, line, ns)
      end
    end
  end
end

---Push current position onto the tagstack
---Enables <C-t> to return to the previous location after a jump.
---@param tag_name string The tag being jumped to
---@private
local function push_tagstack(tag_name)
  local pos = vim.fn.getcurpos()
  local curitem = {
    tagname = tag_name,
    from = { vim.fn.bufnr("%"), pos[2], pos[3], pos[4] },
  }
  local winid = vim.fn.win_getid()

  vim.fn.settagstack(winid, { items = { curitem } }, "t")
end

---Jump to tag under cursor
---Iterates through providers to find a match, pushes tagstack, then jumps.
---Falls back to normal <C-]> if no provider handles the cursor position.
function M.jump_to_tag()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")

  for name, provider in pairs(providers) do
    if provider.find_at_cursor then
      local tag_name, s, e = provider.find_at_cursor(line, col)
      if tag_name and s and col >= s and col <= e then
        if provider.on_jump then
          push_tagstack(tag_name)
          if provider.on_jump(tag_name, {
            line = line,
            col = col,
            bufnr = vim.api.nvim_get_current_buf(),
            provider_name = name,
          }) then
            return
          end
        end
      end
    end
  end

  -- Fallback to built-in tag jump
  vim.cmd("normal! \x1d")
end

---Update tags for the current buffer
---Collects tags from all providers and saves them to the tagfile.
---@param silent? boolean Suppress notification (default: false)
---@param bufnr? number Buffer number (default: current)
function M.update_tags(silent, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total = 0

  for name, provider in pairs(providers) do
    if provider.collect_tags then
      local tags = provider.collect_tags(filepath, lines)
      if tags then
        save_tagfile(name, filepath, tags)
        total = total + #tags
      end
    end
  end

  if not silent and total > 0 then
    vim.notify(string.format("Updated %d tags", total))
  end
end

---Process on_enter hooks for all providers
---@param bufnr? number Buffer number (default: current)
---@private
local function process_on_enter(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for _, provider in pairs(providers) do
    if provider.on_enter then
      provider.on_enter(bufnr, lines)
    end
  end
end

---Initialize a buffer with tagflux
---Sets conceal options, processes on_enter hooks, updates tags, and applies extmarks.
---@param bufnr? number Buffer number (default: current)
---@private
local function setup_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  vim.opt_local.conceallevel = 2
  vim.opt_local.concealcursor = "nc"

  process_on_enter(bufnr)
  M.update_tags(true, bufnr)
  apply_extmarks(bufnr)
end

---Setup tagflux with the given options
---@param opts? TagmarksConfig Configuration options (merged with defaults)
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Load built-in providers
  require("tagflux.marks").setup(M)
  require("tagflux.ref").setup(M)
  require("tagflux.bib").setup(M)
  require("tagflux.og").setup(M)
  require("tagflux.hl").setup(M)
  require("tagflux.cfg").setup(M)

  -- User commands
  vim.api.nvim_create_user_command("TagmarksUpdate", function()
    M.update_tags(false)
  end, { desc = "Update tagflux for current buffer" })

  vim.api.nvim_create_user_command("TagmarksList", function()
    local lines = {}
    -- Load tags from all tag kinds that use tagfiles
    for kind_name, _ in pairs(config.defaults) do
      local tagfile_path = config.get_tagfile(kind_name, M.config.tagkinds)
      if tagfile_path then
        local tags = load_tagfile(kind_name)
        for name, entries in pairs(tags) do
          for _, entry in ipairs(entries) do
            table.insert(lines, string.format(
              "[%s] %s -> %s:%d",
              entry.section,
              name,
              vim.fn.fnamemodify(entry.file, ":~:."),
              entry.lnum
            ))
          end
        end
      end
    end
    table.sort(lines)
    vim.notify(#lines > 0 and table.concat(lines, "\n") or "No tags", vim.log.levels.INFO)
  end, { desc = "List all tagflux" })

  -- Keymaps
  vim.keymap.set("n", "<C-]>", M.jump_to_tag, { desc = "Jump to tagmark under cursor" })

  -- Autocommands
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    callback = function()
      setup_buffer()
    end,
    desc = "Initialize tagflux for buffer",
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function()
      apply_extmarks()
    end,
    desc = "Update tagflux extmarks on text change",
  })

  if M.config.update_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = M.config.filetypes and ("*." .. table.concat(M.config.filetypes, ",*.")) or "*",
      callback = function()
        M.update_tags(true)
      end,
      desc = "Update tagflux on save",
    })
  end
end

return M
