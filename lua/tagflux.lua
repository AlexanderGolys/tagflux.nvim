


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
---@field tagfile string Path to the tagfile for persistent storage
---@field update_on_save boolean Whether to update tags on BufWritePost
---@field filetypes string[]|nil Filetypes to track (nil = all)
---
M.config = {
    tagfile = vim.fn.stdpath("data") .. "/tagflux.tags",
    update_on_save = true,
    filetypes = nil,
}

local ns = vim.api.nvim_create_namespace("tagflux")

---@type table<string, TagmarkProvider> Registered providers
local providers = {}

---Register a tag provider
---@param name string Unique provider name (used as section in tagfile)
---@param provider TagmarkProvider Provider implementation
function M.register(name, provider)
    providers[name] = provider
end

---Load tags from the tagfile
---@param section? string Filter by provider name (nil = all sections)
---@return table<string, TagmarkLoadedEntry[]> Map of tag names to their locations
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

---Save tags to the tagfile
---Removes existing tags for the given section+filepath, then appends new ones.
---@param section string Provider name
---@param filepath string Absolute path to the source file
---@param new_tags TagmarkEntry[] Tags to save
local function save_tagfile(section, filepath, new_tags)
    local lines = {}

    -- Keep tags from other files/sections
    if vim.fn.filereadable(M.config.tagfile) == 1 then
        for _, line in ipairs(vim.fn.readfile(M.config.tagfile)) do
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
    vim.fn.writefile(lines, M.config.tagfile)
end

---@class TagmarksUtils
---@field load_tagfile fun(section?: string): table<string, TagmarkLoadedEntry[]>
---@field save_tagfile fun(section: string, filepath: string, new_tags: TagmarkEntry[])
---@field ns number

---Utility functions exposed for providers
M.utils = {
    load_tagfile = load_tagfile,
    save_tagfile = save_tagfile,
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
---
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

---Setup default highlight groups
---Links tagmark groups to standard highlight groups for colorscheme compatibility.
---@private
local function setup_highlights()
    vim.api.nvim_set_hl(0, "TagmarkDefinition", { link = "Define" })
    vim.api.nvim_set_hl(0, "TagmarkReference", { link = "Tag" })
    vim.api.nvim_set_hl(0, "TagmarkBib", { link = "Underlined" })
    vim.api.nvim_set_hl(0, "TagmarkOg", { link = "Label" })
    vim.api.nvim_set_hl(0, "TagmarkCfg", { link = "Comment" })
end

---Setup tagflux with the given options
---@param opts? TagmarksConfig Configuration options (merged with defaults)
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    setup_highlights()

    -- Load built-in providers
    require("marks").setup(M)
    require("ref").setup(M)
    require("bib").setup(M)
    require("og").setup(M)
    require("hl").setup(M)
    require("cfg").setup(M)

    -- User commands
    vim.api.nvim_create_user_command("TagmarksUpdate", function()
        M.update_tags(false)
    end, { desc = "Update tagflux for current buffer" })

    vim.api.nvim_create_user_command("TagmarksList", function()
        local tags = load_tagfile()
        local lines = {}
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
        table.sort(lines)
        vim.notify(#lines > 0 and table.concat(lines, "\n") or "No tags", vim.log.levels.INFO)
    end, { desc = "List all tagflux" })

    -- Keymaps
    vim.keymap.set("n", "<C-]>", M.jump_to_tag, { desc = "Jump to tagmark under cursor" })

    -- Autocommands
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        callback = setup_buffer(),
        desc = "Initialize tagflux for buffer",
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        callback = function() apply_extmarks() end,
        desc = "Update tagflux extmarks on text change",
    })

    if M.config.update_on_save then
        vim.api.nvim_create_autocmd("BufWritePost", {
            pattern = M.config.filetypes and ("*." .. table.concat(M.config.filetypes, ",*.")) or "*",
            callback = function() M.update_tags(true) end,
            desc = "Update tagflux on save",
        })
    end
end

return M
