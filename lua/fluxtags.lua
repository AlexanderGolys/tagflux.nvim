-- ###nvim-plugin
-- ###tag-kind

-- @@@fluxtags
-- /@@fluxtags.bib
-- /@@fluxtags.cfg
-- /@@fluxtags.hl
-- /@@fluxtags.og
-- /@@fluxtags.ref
-- /@@fluxtags.mark
-- /@@fluxtags.config
-- ///a
-- $$$loca
-- &&&Error&&&err&&&

local M = {}
local _config = require("fluxtags_config")

--- @class Config
--- @field filetypes_whitelist? string[] Deprecated alias for filetypes_inc; kept for compat
--- @field filetypes_ignore? string[]   Filetypes to exclude from tag processing
--- @field kinds? table<string, KindConfig> Per-kind overrides merged on top of defaults
--- @field highlights? table<string, string|vim.api.keyset.highlight> Override FluxTag* highlights
M.config = {
    filetypes_whitelist = nil,
    filetypes_ignore = {},
    kinds = {},
    highlights = nil,
}

--- Return true when `value` exists in `list`.
---
--- @param list? string[]
--- @param value string
--- @return boolean
local function list_contains(list, value)
    if not list then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

--- Decide whether fluxtags should process this buffer based on config.
---
--- filetypes_whitelist = nil or {} means "all filetypes".
--- filetypes_ignore always excludes matching filetypes.
--- Always excludes terminal, oil, neo-tree, and other special buffers.
---
--- @param bufnr number
--- @return boolean
local function should_process_buf(bufnr)
    local ft = vim.bo[bufnr].filetype
    local bt = vim.bo[bufnr].buftype
    
    -- Exclude terminal buffers
    if bt == "terminal" then
        return false
    end
    
    -- Exclude special UI buffers
    local excluded_filetypes = { "oil", "neo-tree", "neotree" }
    if list_contains(excluded_filetypes, ft) then
        return false
    end
    
    if ft == "" then
        return true
    end
    if list_contains(M.config.filetypes_ignore, ft) then
        return false
    end

    local whitelist = M.config.filetypes_whitelist
    if whitelist == nil or #whitelist == 0 then
        return true
    end

    return list_contains(whitelist, ft)
end

--- Extmark namespace shared by all kinds for highlight and conceal extmarks.
local ns = vim.api.nvim_create_namespace("fluxtags")

--- Diagnostic namespace for fluxtags-generated diagnostics (errors/warnings).
local diag_ns = vim.api.nvim_create_namespace("fluxtags_diag")

--- Registry of all active TagKind instances, keyed by kind name.
--- Populated during setup() as each kind module calls register_kind().
local tag_kinds = {}
local tag_kind_order = {}

---@return fun(): string, TagKind
local function ordered_kinds()
    local index = 0
    return function()
        index = index + 1
        local kind_name = tag_kind_order[index]
        if not kind_name then
            return nil
        end

        return kind_name, tag_kinds[kind_name]
    end
end

--- In-memory cache of loaded tagfile contents, keyed by kind name.
--- Each value is a table mapping tag name -> list of {file, lnum, col?} entries.
M.tag_cache = {}

--- Register a TagKind so it participates in scanning, highlighting, and jumping.
--- Called by each tagkind module during setup().
---
--- @param kind TagKind
function M.register_kind(kind)
    if not tag_kinds[kind.name] then
        table.insert(tag_kind_order, kind.name)
    end
    tag_kinds[kind.name] = kind
end

---@param line string
---@return string|nil
---@return string|nil
---@return number|nil
---@return number|nil
local function parse_tagfile_line(line)
    local name, file, lnum, col = line:match("^([^\t]+)\t([^\t]+)\t(%d+)\t?(%d*)")
    if not (name and file and lnum) then
        return nil
    end

    local lnum_num = tonumber(lnum)
    local col_num = col ~= "" and tonumber(col) or nil
    return name, file, lnum_num, col_num
end

--- Read a tagfile from disk and return its contents as a name-indexed table.
---
--- Tagfile format: one entry per line, tab-separated: `name\tfile\tlnum[\tcol]`
--- The returned table maps each tag name to a list of location entries because
--- the same name can appear in multiple files (especially for `og` hashtags).
---
--- Returns an empty table when the kind has no tagfile or the file does not exist.
---
--- @param kind_name string
--- @return table<string, {file:string, lnum:number, col?:number}[]>
local function read_tagfile(kind_name)
    local kind = tag_kinds[kind_name]
    if not kind or not kind.tagfile then return {} end
    if vim.fn.filereadable(kind.tagfile) ~= 1 then return {} end

    local tags = {}
    for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
        local name, file, lnum, col = parse_tagfile_line(line)
        if name then
            tags[name] = tags[name] or {}
            local entry = { file = file, lnum = lnum }
            if col then
                entry.col = col
            end
            table.insert(tags[name], entry)
        end
    end
    return tags
end

---@param tag {lnum:number, col?:number}
---@return string
local function tag_position_key(tag)
    return string.format("%d:%d", tag.lnum, tag.col or 0)
end

---@param positions {lnum:number, col?:number}[]
local function sort_positions(positions)
    table.sort(positions, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        return (a.col or 0) < (b.col or 0)
    end)
end

---@param tags {name:string, lnum:number, col?:number}[]
---@return table<string, {lnum:number, col?:number}[]>
local function group_tags_by_name(tags)
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

---@param previous table<string, {lnum:number, col?:number}[]>
---@param current table<string, {lnum:number, col?:number}[]>
---@return number
---@return number
---@return number
local function diff_entries(previous, current)
    local added, removed, modified = 0, 0, 0
    local all_names = {}

    for name in pairs(previous) do
        all_names[name] = true
    end
    for name in pairs(current) do
        all_names[name] = true
    end

    for name in pairs(all_names) do
        local prev_entries = previous[name] or {}
        local curr_entries = current[name] or {}
        local common = math.min(#prev_entries, #curr_entries)

        for i = 1, common do
            if tag_position_key(prev_entries[i]) ~= tag_position_key(curr_entries[i]) then
                modified = modified + 1
            end
        end

        if #curr_entries > #prev_entries then
            added = added + (#curr_entries - #prev_entries)
        elseif #prev_entries > #curr_entries then
            removed = removed + (#prev_entries - #curr_entries)
        end
    end

    return added, removed, modified
end

---@param added number
---@param removed number
---@param modified number
---@return string[]
local function format_change_parts(added, removed, modified)
    local parts = {}
    if added > 0 then table.insert(parts, string.format("+%d", added)) end
    if removed > 0 then table.insert(parts, string.format("-%d", removed)) end
    if modified > 0 then table.insert(parts, string.format("~%d", modified)) end
    return parts
end

--- Persist the tags found in a single file, replacing that file's previous entries.
---
--- Reads the existing tagfile, discards all lines that belong to `filepath`,
--- appends the new entries, sorts the result, and writes it back.
---
--- Returns change counts `{ added, removed, modified }` so callers can report
--- a useful summary to the user.
---
--- @param kind_name string
--- @param filepath string Absolute path of the scanned buffer
--- @param new_tags {name:string, file:string, lnum:number, col?:number}[]
--- @return {added:number, removed:number, modified:number}
local function write_tagfile(kind_name, filepath, new_tags)
    local kind = tag_kinds[kind_name]
    if not kind or not kind.tagfile then
        return { added = 0, removed = 0, modified = 0 }
    end

    -- Split existing tagfile into entries for this file (to diff) and others (to keep).
    local previous_entries = {}
    local lines_to_keep    = {}
    if vim.fn.filereadable(kind.tagfile) == 1 then
        for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
            local name, file, lnum, col = parse_tagfile_line(line)
            if file == filepath and name then
                previous_entries[name] = previous_entries[name] or {}
                table.insert(previous_entries[name], { lnum = lnum, col = col })
            elseif file ~= filepath then
                table.insert(lines_to_keep, line)
            end
        end

        for _, positions in pairs(previous_entries) do
            sort_positions(positions)
        end
    end

    -- Append new entries and build a lookup for diffing.
    for _, tag in ipairs(new_tags) do
        if tag.col then
            table.insert(lines_to_keep, string.format("%s\t%s\t%d\t%d", tag.name, tag.file, tag.lnum, tag.col))
        else
            table.insert(lines_to_keep, string.format("%s\t%s\t%d", tag.name, tag.file, tag.lnum))
        end
    end

    local new_entries_by_name = group_tags_by_name(new_tags)
    local added, removed, modified = diff_entries(previous_entries, new_entries_by_name)

    table.sort(lines_to_keep)
    vim.fn.writefile(lines_to_keep, kind.tagfile)
    return { added = added, removed = removed, modified = modified }
end

--- Remove tagfile entries that no longer match any line in their source file.
---
--- An entry is considered stale when its file no longer exists on disk, or when
--- the recorded line no longer contains the tag name for this kind.
--- Returns the number of entries removed.
---
--- @param kind_name string
--- @return number removed
local function remove_stale_tagfile_entries(kind_name)
    local kind = tag_kinds[kind_name]
    if not kind or not kind.tagfile then return 0 end
    if vim.fn.filereadable(kind.tagfile) ~= 1 then return 0 end

    local file_lines_cache = {}
    local kept    = {}
    local removed = 0

    for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
        local name, file, lnum = parse_tagfile_line(line)
        
        -- Malformed entries or non-existent files get removed
        if not (name and file and lnum) or vim.fn.filereadable(file) ~= 1 then
            removed = removed + 1
        else
            if not file_lines_cache[file] then
                file_lines_cache[file] = vim.fn.readfile(file)
            end

            local text = file_lines_cache[file][lnum]
            local still_present = false
            if text then
                for match in text:gmatch(kind.pattern) do
                    if match == name then
                        still_present = true
                        break
                    end
                end
            end

            if still_present then
                table.insert(kept, line)
            else
                removed = removed + 1
            end
        end
    end

    table.sort(kept)
    vim.fn.writefile(kept, kind.tagfile)
    return removed
end

--- Open `path` in the current window, or in a split when the buffer is modified.
--- Using a split avoids losing unsaved changes in the current buffer.
---
--- @param path string
--- @param ctx? table Optional context table; `ctx.bufnr` identifies the source buffer
local function open_file_for_jump(path, ctx)
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

    local bufnr = ctx and ctx.bufnr or vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].modified then
        vim.cmd("keepalt split " .. vim.fn.fnameescape(target))
    else
        vim.cmd("keepalt edit " .. vim.fn.fnameescape(target))
    end
end

--- Create a child diagnostic namespace for a named source.
--- Each kind that emits diagnostics should call this once and store the result.
--- Using per-source namespaces lets each kind clear/replace only its own diagnostics.
---
--- @param source string  E.g. "fluxtags.mark"
--- @return number ns_id
local function make_diag_ns(source)
    return vim.api.nvim_create_namespace("fluxtags_diag." .. source)
end

--- Replace the diagnostics emitted by `diag_ns_id` in `bufnr` with `diags`.
---
--- @param bufnr number
--- @param diag_ns_id number  Namespace returned by make_diag_ns
--- @param diags vim.Diagnostic[]
local function set_diagnostics(bufnr, diag_ns_id, diags)
    vim.diagnostic.set(diag_ns_id, bufnr, diags)
end

--- Utilities passed to on_jump callbacks so each kind can navigate without
--- depending directly on fluxtags internals.
M.utils = {
    load_tagfile     = read_tagfile,
    save_tagfile     = write_tagfile,
    ns               = ns,
    diag_ns          = diag_ns,
    make_diag_ns     = make_diag_ns,
    open_file        = open_file_for_jump,
    set_diagnostics  = set_diagnostics,
}

--- Load a single kind's tagfile into M.tag_cache and return the result.
---
--- @param kind_name string
--- @return table<string, {file:string, lnum:number, col?:number}[]>
function M.load_tags(kind_name)
    local tags = read_tagfile(kind_name)
    M.tag_cache[kind_name] = tags
    return tags
end

--- Load tagfiles for all kinds that persist to disk.
--- Returns the total number of tag entries loaded.
---
--- @return number total
function M.load_all_tags()
    local total = 0
    for kind_name, kind in ordered_kinds() do
        if kind.save_to_tagfile then
            for _, entries in pairs(M.load_tags(kind_name)) do
                total = total + #entries
            end
        end
    end
    return total
end

--- Check if a given position falls within any of the disabled intervals.
--- @param intervals table[] Array of {start_lnum, start_col, end_lnum, end_col}
--- @param lnum number 0-indexed line number
--- @param col number 0-indexed column number
--- @return boolean
local function is_in_intervals(intervals, lnum, col)
    if not intervals or #intervals == 0 then return false end
    for _, iv in ipairs(intervals) do
        local sl, sc, el, ec = iv[1], iv[2], iv[3], iv[4]
        local after_start = (lnum > sl) or (lnum == sl and col >= sc)
        local before_end  = (lnum < el) or (lnum == el and col <= ec)
        if after_start and before_end then return true end
    end
    return false
end

--- Clear and redraw all fluxtags extmarks in a buffer.
--- Iterates every line and asks each kind to place its extmarks.
--- After extmarks, calls each kind's apply_diagnostics hook (when present)
--- so kinds that validate tags can publish vim.diagnostic entries.
---
--- @param bufnr? number Defaults to current buffer
local function redraw_extmarks(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    if vim.b[bufnr].fluxtags_disabled then
        -- Clear diagnostics for all kinds since tags are disabled
        for kind_name in ordered_kinds() do
            local kind_diag_ns = make_diag_ns(kind_name)
            set_diagnostics(bufnr, kind_diag_ns, {})
        end
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local hl_intervals = {}
    if tag_kinds.cfg and tag_kinds.cfg.get_disabled_intervals then
        hl_intervals = tag_kinds.cfg:get_disabled_intervals(lines, "fluxtags_hl")
    end

    local check_hl_disabled = function(lnum, col)
        return is_in_intervals(hl_intervals, lnum, col)
    end

    for lnum, line in ipairs(lines) do
        for _, kind in ordered_kinds() do
            kind:apply_extmarks(bufnr, lnum - 1, line, ns, check_hl_disabled)
        end
    end

    for _, kind in ordered_kinds() do
        if kind.apply_diagnostics then
            kind:apply_diagnostics(bufnr, lines, check_hl_disabled)
        end
    end
end

--- Attempt to jump to the tag under the cursor.
---
--- Asks each kind in turn whether the cursor overlaps one of its tags.
--- The first kind whose on_jump returns true wins and the function returns.
--- Falls back to the built-in Ctrl-] (`:tag`) when no kind claims the position.
function M.jump_to_tag()
    local line = vim.api.nvim_get_current_line()
    local col  = vim.fn.col(".")

    for kind_name, kind in ordered_kinds() do
        local tag_name, s, e = kind:find_at_cursor(line, col)
        if tag_name and s and col >= s and col <= e then
            local claimed = kind.on_jump(tag_name, {
                line      = line,
                col       = col,
                bufnr     = vim.api.nvim_get_current_buf(),
                kind_name = kind_name,
                utils     = M.utils,
            })
            if claimed then return end
        end
    end

    -- No kind handled it; fall through to the built-in tag jump (Ctrl-]).
    pcall(vim.cmd, "normal! \x1d")
end

--- Scan the current buffer, update tagfiles for all persisting kinds,
--- and optionally report change counts via vim.notify.
---
--- @param silent boolean Suppress notification when true
--- @param bufnr? number Defaults to current buffer
function M.update_tags(silent, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not should_process_buf(bufnr) then return end
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath == "" then return end

    local is_disabled = vim.b[bufnr].fluxtags_disabled
    local lines = is_disabled and {} or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local reg_intervals = {}
    if not is_disabled and tag_kinds.cfg and tag_kinds.cfg.get_disabled_intervals then
        reg_intervals = tag_kinds.cfg:get_disabled_intervals(lines, "fluxtags_reg")
    end

    local check_reg_disabled = function(lnum, col)
        return is_in_intervals(reg_intervals, lnum, col)
    end

    local total_added, total_removed, total_modified = 0, 0, 0
    local changed_kinds = {}

    for kind_name, kind in ordered_kinds() do
        if kind.save_to_tagfile then
            local tags  = is_disabled and {} or kind:collect_tags(filepath, lines, check_reg_disabled)
            local stats = write_tagfile(kind_name, filepath, tags)
            total_added    = total_added    + stats.added
            total_removed  = total_removed  + stats.removed
            total_modified = total_modified + stats.modified

            if (stats.added + stats.removed + stats.modified) > 0 then
                table.insert(changed_kinds, {
                    name = kind_name,
                    added = stats.added,
                    removed = stats.removed,
                    modified = stats.modified,
                })
            end
        end
    end

    if not silent and (total_added + total_removed + total_modified) > 0 then
        table.sort(changed_kinds, function(a, b)
            return a.name < b.name
        end)

        local total_parts = format_change_parts(total_added, total_removed, total_modified)

        local per_kind_parts = {}
        for _, item in ipairs(changed_kinds) do
            local parts = format_change_parts(item.added, item.removed, item.modified)
            table.insert(per_kind_parts, string.format("%s(%s)", item.name, table.concat(parts, " ")))
        end

        vim.notify(
            string.format(
                "Tags changed: %s [%s]",
                table.concat(total_parts, " "),
                table.concat(per_kind_parts, ", ")
            ),
            vim.log.levels.INFO
        )
    end
end

--- Run on_enter hooks for all kinds that register one.
---
--- on_enter hooks are used for immediate side-effects that must fire before
--- highlighting (e.g. the `cfg` kind sets the filetype from `$$$ft(lua)` tags).
---
--- @param bufnr number
local function run_on_enter_hooks(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, kind in ordered_kinds() do
        if kind.on_enter then
            kind.on_enter(bufnr, lines)
        end
    end
end

--- Initialize a buffer for fluxtags: set conceal options, run on_enter hooks,
--- and apply extmarks.
---
--- Idempotent by default: sets `vim.b[bufnr].fluxtags_initialized` and skips
--- re-initialization on subsequent calls unless `force` is true.
---
--- @param bufnr? number Defaults to current buffer
--- @param force? boolean Re-initialize even if already done
function M.setup_buffer(bufnr, force)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not should_process_buf(bufnr) then return end

    if not force then
        if vim.b[bufnr].fluxtags_initialized then return end
        vim.b[bufnr].fluxtags_initialized = true
    end

    -- Reset disabled flag before running on_enter hooks
    vim.b[bufnr].fluxtags_disabled = false

    vim.opt_local.conceallevel  = 2
    vim.opt_local.concealcursor = "nc"

    run_on_enter_hooks(bufnr)
    redraw_extmarks(bufnr)
end

--- Schedule a debounced refresh for a buffer.
---
--- If a refresh is already pending for this buffer the new request is dropped,
--- ensuring at most one refresh fires per 80 ms burst of events (e.g. rapid
--- TextChanged events while typing). The refresh re-runs setup_buffer and
--- silently updates tagfiles when the buffer is not modified.
---
--- @param bufnr number
local function schedule_debounced_refresh(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if vim.b[bufnr].fluxtags_refresh_scheduled then return end
    vim.b[bufnr].fluxtags_refresh_scheduled = true

    vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        vim.b[bufnr].fluxtags_refresh_scheduled = false
        M.setup_buffer(bufnr, true)
        if not vim.bo[bufnr].modified then
            M.update_tags(true, bufnr)
        end
    end, 80)
end

-- Expose internals needed by sub-modules (commands, autocmds).
M.tag_kinds    = tag_kinds
M.load_tagfile = read_tagfile
M.prune_tagfile = remove_stale_tagfile_entries
M.setup_buffer = M.setup_buffer

--- Initialize the plugin: merge config, register all tag kinds, set up
--- autocmds and user commands, and bind Ctrl-].
---
--- @param opts? Config
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    _config.setup_default_highlights(M.config.highlights)

    require("tagkinds.mark").register(M)
    require("tagkinds.ref").register(M)
    require("tagkinds.refog").register(M)
    require("tagkinds.bib").register(M)
    require("tagkinds.og").register(M)
    require("tagkinds.hl").register(M)
    require("tagkinds.cfg").register(M)

    require("fluxtags.autocmds").setup(M, schedule_debounced_refresh)
    require("fluxtags.commands").setup(M)
end

return M
