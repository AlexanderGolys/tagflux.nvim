

-- @@@helplesstags.cfg
-- ~/nvim-plugins/tagmarks/lua/tagmarks/cfg.lua

---@brief [[
--- Buffer configuration provider for tagmarks
---
--- Syntax: $$$key:value (concealed to $key:value)
--- With comment: -- $$$ft:lua or // $$$conceallevel:0
---
--- Built-in handlers:
---   $$$ft:python          -> set filetype
---   $$$conceallevel:0     -> set conceallevel
---   $$$tagmarks:off       -> disable tagmarks for this buffer
---   $$$modeline:set sw=2  -> execute arbitrary vim command
---
--- Custom handlers can be registered with cfg.register_handler().
---@brief ]]

local M = {}

---Pattern for config directive (without comment prefix)
---@type string
local PATTERN = "()%$%$%$([%w_]+):([^\n%s]+)"

---@type table<string, fun(value: string, bufnr: number)>
local handlers = {
  ---Set buffer filetype
  ft = function(value, bufnr)
    vim.bo[bufnr].filetype = value
  end,

  ---Set window conceallevel
  conceallevel = function(value, bufnr)
    vim.wo[bufnr].conceallevel = tonumber(value) or 0
  end,

  ---Disable tagmarks for this buffer
  tagmarks = function(value, bufnr)
    if value == "off" then
      vim.b[bufnr].tagmarks_disabled = true
    end
  end,

  ---Execute arbitrary vim command
  modeline = function(value, bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, value)
    end)
  end,
}

---Setup the configuration provider
---@param tagmarks table The main tagmarks module
function M.setup(tagmarks)
  local find_with_comment = tagmarks.utils.find_with_comment
  local gmatch_with_comment = tagmarks.utils.gmatch_with_comment

  tagmarks.register("cfg", {
    ---Find a config directive at the cursor position
    ---@param line string Current line content
    ---@param col number Cursor column (1-indexed)
    ---@return string|nil match "key:value" if found
    ---@return number|nil s Start column
    ---@return number|nil e End column
    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, tag_start, key, value = find_with_comment(line, PATTERN, start_pos)
        if not s then return nil end
        if col >= s and col <= e then return key .. ":" .. value, s, e end
        start_pos = e + 1
      end
    end,

    ---Apply extmarks for concealing $$ and highlighting $key:value
    ---@param bufnr number Buffer number
    ---@param lnum number Line number (0-indexed)
    ---@param line string Line content
    ---@param ns number Namespace for extmarks
    apply_extmarks = function(bufnr, lnum, line, ns)
      for tag_start, key, value in gmatch_with_comment(line, PATTERN) do
        local col0 = tag_start - 1
        -- Conceal first 2 $ (show $key:value)
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 2,
          conceal = "",
        })
        -- Highlight $key:value
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 3 + #key + 1 + #value,
          hl_group = "TagmarkCfg",
        })
      end
    end,

    ---Process config directives when entering buffer
    ---@param bufnr number Buffer number
    ---@param lines string[] Buffer lines
    on_enter = function(bufnr, lines)
      for _, line in ipairs(lines) do
        for tag_start, key, value in gmatch_with_comment(line, PATTERN) do
          if handlers[key] then
            handlers[key](value, bufnr)
          end
        end
      end
    end,
  })
end

---Register a custom config handler
---@param key string Config key (e.g., "myopt" for $$$myopt:value)
---@param fn fun(value: string, bufnr: number) Handler function
function M.register_handler(key, fn)
  handlers[key] = fn
end

return M
