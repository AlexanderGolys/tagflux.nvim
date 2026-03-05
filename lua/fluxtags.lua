--- @brief [[
--- fluxtags core rewritten around a small OOP runtime.
---
--- The module exports a singleton facade (`M`) for backward compatibility,
--- but all state and behavior live in `FluxtagsApp`, a metatable-backed class.
--- Tag kinds register themselves against the app and use app utilities for
--- tagfile IO, diagnostics, and file navigation.
--- @brief ]]

local config_mod = require("fluxtags_config")

local M = {}

--- @class Config
--- @field filetypes_inc? string[] Filetypes included for processing (empty/nil = all)
--- @field filetypes_exc? string[] Filetypes excluded from processing
--- @field filetypes_whitelist? string[] Deprecated alias for `filetypes_inc`
--- @field filetypes_ignore? string[] Deprecated alias for `filetypes_exc`
--- @field kinds? table<string, KindConfig> Per-kind overrides
--- @field highlights? table<string, string|vim.api.keyset.highlight> Highlight overrides

--- @class FluxtagsApp
--- @field config Config
--- @field ns integer
--- @field diag_ns integer
--- @field tag_kinds table<string, TagKind>
--- @field kind_order string[]
--- @field tag_cache table<string, table<string, {file:string, lnum:number, col?:number}[]>>
--- @field utils table
local App = {}
App.__index = App

local BUILTIN_FILETYPE_EXCLUDES = { oil = true, ["neo-tree"] = true, neotree = true }

---@param list? string[]
---@param value string
---@return boolean
local function in_list(list, value)
    if not list then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

---@param line string
---@return string|nil
---@return string|nil
---@return integer|nil
---@return integer|nil
local function parse_tagfile_line(line)
    local name, file, lnum, col = line:match("^([^\t]+)\t([^\t]+)\t(%d+)\t?(%d*)")
    if not (name and file and lnum) then return nil end
    return name, file, tonumber(lnum), col ~= "" and tonumber(col) or nil
end

---@param pos {lnum:number, col?:number}
---@return string
local function pos_key(pos)
    return string.format("%d:%d", pos.lnum, pos.col or 0)
end

---@param list {lnum:number, col?:number}[]
local function sort_positions(list)
    table.sort(list, function(a, b)
        if a.lnum ~= b.lnum then return a.lnum < b.lnum end
        return (a.col or 0) < (b.col or 0)
    end)
end

---@param tags {name:string, lnum:number, col?:number}[]
---@return table<string, {lnum:number, col?:number}[]>
local function group_by_name(tags)
    local grouped = {}
    for _, tag in ipairs(tags) do
        grouped[tag.name] = grouped[tag.name] or {}
        table.insert(grouped[tag.name], { lnum = tag.lnum, col = tag.col })
    end
    for _, positions in pairs(grouped) do
        sort_positions(positions)
    end
    return grouped
end

---@param prev table<string, {lnum:number, col?:number}[]>
---@param curr table<string, {lnum:number, col?:number}[]>
---@return integer added
---@return integer removed
---@return integer modified
local function diff_entries(prev, curr)
    local added, removed, modified = 0, 0, 0
    local names = {}
    for name in pairs(prev) do names[name] = true end
    for name in pairs(curr) do names[name] = true end

    for name in pairs(names) do
        local a, b = prev[name] or {}, curr[name] or {}
        local common = math.min(#a, #b)
        for i = 1, common do
            if pos_key(a[i]) ~= pos_key(b[i]) then modified = modified + 1 end
        end
        if #b > #a then
            added = added + (#b - #a)
        elseif #a > #b then
            removed = removed + (#a - #b)
        end
    end

    return added, removed, modified
end

---@param intervals? table[]
---@param lnum integer
---@param col integer
---@return boolean
local function in_intervals(intervals, lnum, col)
    if not intervals or #intervals == 0 then return false end
    for _, iv in ipairs(intervals) do
        local sl, sc, el, ec = iv[1], iv[2], iv[3], iv[4]
        local after_start = (lnum > sl) or (lnum == sl and col >= sc)
        local before_end = (lnum < el) or (lnum == el and col <= ec)
        if after_start and before_end then return true end
    end
    return false
end

---@param added integer
---@param removed integer
---@param modified integer
---@return string[]
local function format_changes(added, removed, modified)
    local out = {}
    if added > 0 then table.insert(out, ("+%d"):format(added)) end
    if removed > 0 then table.insert(out, ("-%d"):format(removed)) end
    if modified > 0 then table.insert(out, ("~%d"):format(modified)) end
    return out
end

---@return FluxtagsApp
function App.new()
    ---@type FluxtagsApp
    local self = setmetatable({
        config = {
            filetypes_inc = nil,
            filetypes_exc = {},
            filetypes_whitelist = nil,
            filetypes_ignore = {},
            kinds = {},
            highlights = nil,
        },
        ns = vim.api.nvim_create_namespace("fluxtags"),
        diag_ns = vim.api.nvim_create_namespace("fluxtags_diag"),
        tag_kinds = {},
        kind_order = {},
        tag_cache = {},
    }, App)

    self.utils = {
        load_tagfile = function(kind_name) return self:load_tagfile(kind_name) end,
        save_tagfile = function(kind_name, filepath, tags) return self:write_tagfile(kind_name, filepath, tags) end,
        ns = self.ns,
        diag_ns = self.diag_ns,
        make_diag_ns = function(source) return vim.api.nvim_create_namespace("fluxtags_diag." .. source) end,
        open_file = function(path, ctx) self:open_file(path, ctx) end,
        set_diagnostics = function(bufnr, ns_id, diags) vim.diagnostic.set(ns_id, bufnr, diags) end,
    }

    return self
end

---@param cfg Config
---@return Config
local function normalize_config(cfg)
    if cfg.filetypes_inc == nil and cfg.filetypes_whitelist ~= nil then
        cfg.filetypes_inc = cfg.filetypes_whitelist
    end
    if cfg.filetypes_exc == nil and cfg.filetypes_ignore ~= nil then
        cfg.filetypes_exc = cfg.filetypes_ignore
    end

    cfg.filetypes_whitelist = cfg.filetypes_inc
    cfg.filetypes_ignore = cfg.filetypes_exc or {}
    cfg.filetypes_exc = cfg.filetypes_ignore
    return cfg
end

---@return fun(): string, TagKind
function App:ordered_kinds()
    local i = 0
    return function()
        i = i + 1
        local name = self.kind_order[i]
        if not name then return nil end
        return name, self.tag_kinds[name]
    end
end

---@param bufnr integer
---@return boolean
function App:should_process_buf(bufnr)
    local ft, bt = vim.bo[bufnr].filetype, vim.bo[bufnr].buftype
    if bt == "terminal" or BUILTIN_FILETYPE_EXCLUDES[ft] then return false end
    if ft == "" then return true end
    local deny = self.config.filetypes_exc or self.config.filetypes_ignore
    if in_list(deny, ft) then return false end
    local allow = self.config.filetypes_inc or self.config.filetypes_whitelist
    return allow == nil or #allow == 0 or in_list(allow, ft)
end

---@param kind TagKind
function App:register_kind(kind)
    if not self.tag_kinds[kind.name] then table.insert(self.kind_order, kind.name) end
    self.tag_kinds[kind.name] = kind
end

---@param kind_name string
---@return table<string, {file:string, lnum:number, col?:number}[]>
function App:load_tagfile(kind_name)
    local kind = self.tag_kinds[kind_name]
    if not kind or not kind.tagfile or vim.fn.filereadable(kind.tagfile) ~= 1 then return {} end

    local tags = {}
    for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
        local name, file, lnum, col = parse_tagfile_line(line)
        if name then
            tags[name] = tags[name] or {}
            local entry = { file = file, lnum = lnum }
            if col then entry.col = col end
            table.insert(tags[name], entry)
        end
    end
    return tags
end

---@param kind_name string
---@param filepath string
---@param new_tags {name:string, file:string, lnum:number, col?:number}[]
---@return {added:integer, removed:integer, modified:integer}
function App:write_tagfile(kind_name, filepath, new_tags)
    local kind = self.tag_kinds[kind_name]
    if not kind or not kind.tagfile then
        return { added = 0, removed = 0, modified = 0 }
    end

    local previous, keep = {}, {}
    if vim.fn.filereadable(kind.tagfile) == 1 then
        for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
            local name, file, lnum, col = parse_tagfile_line(line)
            if name and file == filepath then
                previous[name] = previous[name] or {}
                table.insert(previous[name], { lnum = lnum, col = col })
            elseif file ~= filepath then
                table.insert(keep, line)
            end
        end
        for _, positions in pairs(previous) do sort_positions(positions) end
    end

    for _, tag in ipairs(new_tags) do
        table.insert(keep, tag.col and ("%s\t%s\t%d\t%d"):format(tag.name, tag.file, tag.lnum, tag.col)
            or ("%s\t%s\t%d"):format(tag.name, tag.file, tag.lnum))
    end

    local added, removed, modified = diff_entries(previous, group_by_name(new_tags))
    table.sort(keep)
    vim.fn.writefile(keep, kind.tagfile)
    return { added = added, removed = removed, modified = modified }
end

---@param kind_name string
---@return integer removed
function App:prune_tagfile(kind_name)
    local kind = self.tag_kinds[kind_name]
    if not kind or not kind.tagfile or vim.fn.filereadable(kind.tagfile) ~= 1 then return 0 end

    local cache, kept, removed = {}, {}, 0
    for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
        local name, file, lnum = parse_tagfile_line(line)
        if not (name and file and lnum) or vim.fn.filereadable(file) ~= 1 then
            removed = removed + 1
        else
            if not cache[file] then cache[file] = vim.fn.readfile(file) end
            local text, present = cache[file][lnum], false
            if text then
                for match in text:gmatch(kind.pattern) do
                    if match == name then
                        present = true
                        break
                    end
                end
            end
            if present then table.insert(kept, line) else removed = removed + 1 end
        end
    end

    table.sort(kept)
    vim.fn.writefile(kept, kind.tagfile)
    return removed
end

---@param path string
---@param ctx? table
function App:open_file(path, ctx)
    local target = vim.fn.fnamemodify(path, ":p")
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(winid) then
            local win_buf = vim.api.nvim_win_get_buf(winid)
            local win_path = vim.api.nvim_buf_get_name(win_buf)
            if win_path ~= "" and vim.fn.fnamemodify(win_path, ":p") == target then
                vim.api.nvim_set_current_win(winid)
                return
            end
        end
    end

    local bufnr = (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
    local cmd = vim.bo[bufnr].modified and "keepalt split " or "keepalt edit "
    vim.cmd(cmd .. vim.fn.fnameescape(target))
end

---@param kind_name string
---@return table<string, {file:string, lnum:number, col?:number}[]>
function App:load_tags(kind_name)
    local tags = self:load_tagfile(kind_name)
    self.tag_cache[kind_name] = tags
    return tags
end

---@return integer
function App:load_all_tags()
    local total = 0
    for kind_name, kind in self:ordered_kinds() do
        if kind.save_to_tagfile then
            for _, entries in pairs(self:load_tags(kind_name)) do
                total = total + #entries
            end
        end
    end
    return total
end

---@param bufnr? integer
function App:redraw_extmarks(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, self.ns, 0, -1)

    if vim.b[bufnr].fluxtags_disabled then
        for kind_name in self:ordered_kinds() do
            vim.diagnostic.set(self.utils.make_diag_ns(kind_name), bufnr, {})
        end
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local intervals = {}
    local cfg_kind = self.tag_kinds.cfg
    if cfg_kind and cfg_kind.get_disabled_intervals then
        intervals = cfg_kind:get_disabled_intervals(lines, "fluxtags_hl")
    end
    local is_disabled = function(lnum, col) return in_intervals(intervals, lnum, col) end

    for lnum, line in ipairs(lines) do
        for _, kind in self:ordered_kinds() do
            kind:apply_extmarks(bufnr, lnum - 1, line, self.ns, is_disabled)
        end
    end

    for _, kind in self:ordered_kinds() do
        if kind.apply_diagnostics then kind:apply_diagnostics(bufnr, lines, is_disabled) end
    end
end

function App:jump_to_tag()
    local line, col = vim.api.nvim_get_current_line(), vim.fn.col(".")
    for kind_name, kind in self:ordered_kinds() do
        local name, s, e = kind:find_at_cursor(line, col)
        if name and s and col >= s and col <= e then
            if kind.on_jump(name, {
                line = line,
                col = col,
                bufnr = vim.api.nvim_get_current_buf(),
                kind_name = kind_name,
                utils = self.utils,
            }) then
                return
            end
        end
    end
    pcall(vim.cmd, "normal! \x1d")
end

---@param silent boolean
---@param bufnr? integer
function App:update_tags(silent, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not self:should_process_buf(bufnr) then return end
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath == "" then return end

    local disabled = vim.b[bufnr].fluxtags_disabled
    local lines = disabled and {} or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local intervals = {}
    local cfg_kind = self.tag_kinds.cfg
    if not disabled and cfg_kind and cfg_kind.get_disabled_intervals then
        intervals = cfg_kind:get_disabled_intervals(lines, "fluxtags_reg")
    end
    local is_disabled = function(lnum, col) return in_intervals(intervals, lnum, col) end

    local total = { added = 0, removed = 0, modified = 0 }
    local changed = {}

    for kind_name, kind in self:ordered_kinds() do
        if kind.save_to_tagfile then
            local tags = disabled and {} or kind:collect_tags(filepath, lines, is_disabled)
            local stats = self:write_tagfile(kind_name, filepath, tags)
            total.added = total.added + stats.added
            total.removed = total.removed + stats.removed
            total.modified = total.modified + stats.modified
            if (stats.added + stats.removed + stats.modified) > 0 then
                table.insert(changed, {
                    name = kind_name,
                    added = stats.added,
                    removed = stats.removed,
                    modified = stats.modified,
                })
            end
        end
    end

    local total_changed = total.added + total.removed + total.modified
    if silent or total_changed == 0 then return end

    table.sort(changed, function(a, b) return a.name < b.name end)
    local per_kind = {}
    for _, item in ipairs(changed) do
        table.insert(per_kind, ("%s(%s)"):format(item.name, table.concat(format_changes(item.added, item.removed, item.modified), " ")))
    end

    vim.notify(("Tags changed: %s [%s]"):format(
        table.concat(format_changes(total.added, total.removed, total.modified), " "),
        table.concat(per_kind, ", ")
    ), vim.log.levels.INFO)
end

---@param bufnr integer
function App:run_on_enter_hooks(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, kind in self:ordered_kinds() do
        if kind.on_enter then kind.on_enter(bufnr, lines) end
    end
end

---@param bufnr? integer
---@param force? boolean
function App:setup_buffer(bufnr, force)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not self:should_process_buf(bufnr) then return end

    if not force then
        if vim.b[bufnr].fluxtags_initialized then return end
        vim.b[bufnr].fluxtags_initialized = true
    end

    vim.b[bufnr].fluxtags_disabled = false
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"

    self:run_on_enter_hooks(bufnr)
    self:redraw_extmarks(bufnr)
end

---@param bufnr integer
function App:schedule_refresh(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].fluxtags_refresh_scheduled then return end
    vim.b[bufnr].fluxtags_refresh_scheduled = true

    vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        vim.b[bufnr].fluxtags_refresh_scheduled = false
        self:setup_buffer(bufnr, true)
        if not vim.bo[bufnr].modified then self:update_tags(true, bufnr) end
    end, 80)
end

---@param opts? Config
function App:setup(opts)
    self.config = normalize_config(vim.tbl_deep_extend("force", self.config, opts or {}))
    config_mod.setup_default_highlights(self.config.highlights)

    require("tagkinds.mark").register(M)
    require("tagkinds.ref").register(M)
    require("tagkinds.refog").register(M)
    require("tagkinds.bib").register(M)
    require("tagkinds.og").register(M)
    require("tagkinds.hl").register(M)
    require("tagkinds.cfg").register(M)

    require("fluxtags.autocmds").setup(M, function(bufnr) self:schedule_refresh(bufnr) end)
    require("fluxtags.commands").setup(M)
end

local app = App.new()

M.config = app.config
M.utils = app.utils
M.tag_cache = app.tag_cache
M.tag_kinds = app.tag_kinds
M.load_tagfile = function(kind_name) return app:load_tagfile(kind_name) end
M.prune_tagfile = function(kind_name) return app:prune_tagfile(kind_name) end
M.load_tags = function(kind_name) return app:load_tags(kind_name) end
M.load_all_tags = function() return app:load_all_tags() end
M.register_kind = function(kind) return app:register_kind(kind) end
M.jump_to_tag = function() return app:jump_to_tag() end
M.update_tags = function(silent, bufnr) return app:update_tags(silent, bufnr) end
M.setup_buffer = function(bufnr, force) return app:setup_buffer(bufnr, force) end
M.setup = function(opts)
    app:setup(opts)
    M.config = app.config
end

return M
