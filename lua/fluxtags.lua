-- @@@fluxtags
-- ###nvim-plugin

-- |||fluxtags.bib|||
-- |||fluxtags.cfg|||
-- |||fluxtags.hl|||
-- |||fluxtags.og|||
-- |||fluxtags.marks|||

local M = {}

M.config = {
    tagfile = vim.fn.stdpath("data") .. "/fluxtags.tags",
    update_on_save = true,
    filetypes = nil,
    kinds = {},
}

local ns = vim.api.nvim_create_namespace("fluxtags")
local tag_kinds = {}
M.tag_cache = {}

--- Register a TagKind instance
--- @param kind TagKind The tag kind to register
function M.register_kind(kind)
    tag_kinds[kind.name] = kind
    if kind.hl_group then
        vim.api.nvim_set_hl(0, kind.hl_group, {})
    end
end

local function load_tagfile(kind_name)
    local kind = tag_kinds[kind_name]
    if not kind or not kind.tagfile then
        return {}
    end

    local tags = {}
    if vim.fn.filereadable(kind.tagfile) == 1 then
        for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
            local name, file, lnum = line:match("^([^\t]+)\t([^\t]+)\t(%d+)")
            if name then
                tags[name] = tags[name] or {}
                table.insert(tags[name], { file = file, lnum = tonumber(lnum) })
            end
        end
    end
    return tags
end

local function save_tagfile(kind_name, filepath, new_tags)
    local kind = tag_kinds[kind_name]
    if not kind or not kind.tagfile then
        return
    end

    local lines = {}
    if vim.fn.filereadable(kind.tagfile) == 1 then
        for _, line in ipairs(vim.fn.readfile(kind.tagfile)) do
            local _, file = line:match("^([^\t]+)\t([^\t]+)")
            if file ~= filepath then
                table.insert(lines, line)
            end
        end
    end

    for _, tag in ipairs(new_tags) do
        table.insert(lines, string.format("%s\t%s\t%d", tag.name, tag.file, tag.lnum))
    end

    table.sort(lines)
    vim.fn.writefile(lines, kind.tagfile)
end

M.utils = {
    load_tagfile = load_tagfile,
    save_tagfile = save_tagfile,
    ns = ns,
}

function M.load_tags(kind_name)
    local tags = load_tagfile(kind_name)
    M.tag_cache[kind_name] = tags
    return tags
end

function M.load_all_tags()
    local total = 0
    for kind_name, kind in pairs(tag_kinds) do
        if kind.save_to_tagfile then
            local tags = M.load_tags(kind_name)
            for _, entries in pairs(tags) do
                total = total + #entries
            end
        end
    end
    return total
end

local function apply_extmarks(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if vim.b[bufnr].fluxtags_disabled then return end

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for lnum, line in ipairs(lines) do
        for _, kind in pairs(tag_kinds) do
            kind:apply_extmarks(bufnr, lnum - 1, line, ns)
        end
    end
end

function M.jump_to_tag()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")

    for name, kind in pairs(tag_kinds) do
        local tag_name, s, e = kind:find_at_cursor(line, col)
        if tag_name and s and col >= s and col <= e then
            if kind.on_jump(tag_name, {
                    line = line,
                    col = col,
                    bufnr = vim.api.nvim_get_current_buf(),
                    kind_name = name,
                    utils = M.utils,
                }) then
                return
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

    for name, kind in pairs(tag_kinds) do
        if kind.save_to_tagfile then
            local tags = kind:collect_tags(filepath, lines)
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

    for _, kind in pairs(tag_kinds) do
        if kind.on_enter then
            kind.on_enter(bufnr, lines)
        end
    end
end

local function setup_buffer(bufnr, force)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not force then
        if vim.b[bufnr].fluxtags_initialized then
            return
        end
        vim.b[bufnr].fluxtags_initialized = true
    end

    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"

    process_on_enter(bufnr)
    apply_extmarks(bufnr)
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    require("tagkinds.marks").register(M)
    require("tagkinds.ref").register(M)
    require("tagkinds.bib").register(M)
    require("tagkinds.og").register(M)
    require("tagkinds.hl").register(M)
    require("tagkinds.cfg").register(M)

    local augroup = vim.api.nvim_create_augroup("Fluxtags", { clear = true })

    vim.api.nvim_create_user_command("FTagsUpdate", function()
        M.update_tags(false)
    end, {})

    vim.api.nvim_create_user_command("FTagsSave", function()
        M.update_tags(false)
    end, {})

    vim.api.nvim_create_user_command("FTagsLoad", function()
        local total = M.load_all_tags()
        vim.notify(total > 0 and string.format("Loaded %d tags", total) or "No tags", vim.log.levels.INFO)
    end, {})

    vim.api.nvim_create_user_command("FTagsHL", function()
        setup_buffer(nil, true)
    end, {})

    vim.api.nvim_create_user_command("FTagsList", function()
        local all_lines = {}
        for kind_name, kind in pairs(tag_kinds) do
            if kind.save_to_tagfile then
                local tags = load_tagfile(kind_name)
                for name, entries in pairs(tags) do
                    for _, entry in ipairs(entries) do
                        table.insert(all_lines, string.format("[%s] %s -> %s:%d",
                            kind_name, name, vim.fn.fnamemodify(entry.file, ":~:."), entry.lnum))
                    end
                end
            end
        end
        table.sort(all_lines)
        vim.notify(#all_lines > 0 and table.concat(all_lines, "\n") or "No tags", vim.log.levels.INFO)
    end, {})

    vim.keymap.set("n", "<C-]>", M.jump_to_tag, { desc = "Jump to tag" })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = augroup,
        callback = function()
            M.load_all_tags()
            setup_buffer(nil, true)
        end,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        pattern = M.config.filetypes and ("*." .. table.concat(M.config.filetypes, ",*.")) or "*",
        callback = function()
            M.update_tags(true)
        end,
    })
end

return M
