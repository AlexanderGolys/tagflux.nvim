

-- @@@helplesstags
-- #nvim-plugin

-- |||helplesstags.bib|||
-- |||helplesstags.cfg|||
-- |||helplesstags.hl|||
-- |||helplesstags.og|||
-- |||helplesstags.marks|||


local M = {}

M.config = {
  tagfile = vim.fn.stdpath("data") .. "/tagmarks.tags",
  update_on_save = true,
  filetypes = nil,
}

local ns = vim.api.nvim_create_namespace("tagmarks")
local providers = {}

function M.register(name, provider)
  providers[name] = provider
end

local function load_tagfile(section)
  local tags = {}
  if vim.fn.filereadable(M.config.tagfile) == 1 then
    for _, line in ipairs(vim.fn.readfile(M.config.tagfile)) do
      local sec, name, file, lnum = line:match("^([^:]+):([^\t]+)\t([^\t]+)\t(%d+)")
      if sec and (not section or sec == section) then
        tags[name] = tags[name] or {}
        table.insert(tags[name], { file = file, lnum = tonumber(lnum), section = sec })
      end
    end
  end
  return tags
end

local function save_tagfile(section, filepath, new_tags)
  local lines = {}

  if vim.fn.filereadable(M.config.tagfile) == 1 then
    for _, line in ipairs(vim.fn.readfile(M.config.tagfile)) do
      local sec, _, file = line:match("^([^:]+):([^\t]+)\t([^\t]+)")
      if not (sec == section and file == filepath) then
        table.insert(lines, line)
      end
    end
  end

  for _, tag in ipairs(new_tags) do
    table.insert(lines, string.format("%s:%s\t%s\t%d", section, tag.name, tag.file, tag.lnum))
  end

  table.sort(lines)
  vim.fn.writefile(lines, M.config.tagfile)
end

M.utils = {
  load_tagfile = load_tagfile,
  save_tagfile = save_tagfile,
  ns = ns,
}

local function apply_extmarks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].tagmarks_disabled then return end

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

local function push_tagstack(tag_name)
  local pos = vim.fn.getcurpos()
  local curitem = {
    tagname = tag_name,
    from = { vim.fn.bufnr("%"), pos[2], pos[3], pos[4] },
  }
  local winid = vim.fn.win_getid()
  local stack = vim.fn.gettagstack(winid)
  local curidx = stack.curidx

  vim.fn.settagstack(winid, { items = { curitem } }, "t")
end

function M.jump_to_tag()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")

  for name, provider in pairs(providers) do
    if provider.find_at_cursor then
      local tag_name, s, e = provider.find_at_cursor(line, col)
      if tag_name and s and col >= s and col <= e then
        if provider.on_jump then
          push_tagstack(tag_name)
          if provider.on_jump(tag_name, { line = line, col = col, bufnr = vim.api.nvim_get_current_buf(), provider_name = name }) then
            return
          end
        end
      end
    end
  end

  vim.cmd("normal! \x1d")
end

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

local function process_on_enter(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for _, provider in pairs(providers) do
    if provider.on_enter then
      provider.on_enter(bufnr, lines)
    end
  end
end

local function setup_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  vim.opt_local.conceallevel = 2
  vim.opt_local.concealcursor = "nc"

  process_on_enter(bufnr)
  M.update_tags(true, bufnr)
  apply_extmarks(bufnr)
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "TagmarkDefinition", { link = "Define" })
  vim.api.nvim_set_hl(0, "TagmarkReference", { link = "Tag" })
  vim.api.nvim_set_hl(0, "TagmarkBib", { link = "Underlined" })
  vim.api.nvim_set_hl(0, "TagmarkOg", { link = "Label" })
  vim.api.nvim_set_hl(0, "TagmarkCfg", { link = "Comment" })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  setup_highlights()

  require("marks").setup(M)
  require("ref").setup(M)
  require("bib").setup(M)
  require("og").setup(M)
  require("hl").setup(M)
  require("cfg").setup(M)

  vim.api.nvim_create_user_command("TagmarksUpdate", function()
    M.update_tags(false)
  end, {})

  vim.api.nvim_create_user_command("TagmarksList", function()
    local tags = load_tagfile()
    local lines = {}
    for name, entries in pairs(tags) do
      for _, entry in ipairs(entries) do
        table.insert(lines, string.format("[%s] %s -> %s:%d", entry.section, name, vim.fn.fnamemodify(entry.file, ":~:."), entry.lnum))
      end
    end
    table.sort(lines)
    vim.notify(#lines > 0 and table.concat(lines, "\n") or "No tags", vim.log.levels.INFO)
  end, {})

  vim.keymap.set("n", "<C-]>", M.jump_to_tag, { desc = "Jump to tag" })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    callback = function() setup_buffer() end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function() apply_extmarks() end,
  })

  if M.config.update_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = M.config.filetypes and ("*." .. table.concat(M.config.filetypes, ",*.")) or "*",
      callback = function() M.update_tags(true) end,
    })
  end
end

return M
