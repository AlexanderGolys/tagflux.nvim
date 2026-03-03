local M = {}


local function kind_symbol(kind)
    local symbols = {
        mark = "@",
        ref  = "&",
        refog = "#",
        og   = "#",
        cfg  = "$",
        hl   = "%",
        bib  = "/",
    }
    return symbols[kind] or "?"
end

local kind_help = {
    mark = {
        syntax = "-- @@@<name>",
        info = "Named anchors persisted to tagfiles; refs jump to these.",
    },
    ref = {
        syntax = "-- |||<name>||| or @<base>.<subtag>",
        info = "References to marks; resolves base name on Ctrl-].",
    },
    refog = {
        syntax = "#|#||<name>||",
        info = "Reference-only OG jump tag; does not create saved hashtag entries.",
    },
    bib = {
        syntax = "-- ///<target>",
        info = "External links (URL/file/help topic); opens target on Ctrl-].",
    },
    og = {
        syntax = "@##<name>",
        info = "Topic hashtags across files; Ctrl-] opens a picker of occurrences.",
    },
    hl = {
        syntax = "&&&<HlGroup>&&&<text>&&&",
        info = "Inline styled text using any Neovim highlight group.",
    },
    cfg = {
        syntax = "$$$<key>(<value>)",
        info = "Buffer-local config directives applied on enter.",
    },
}

local function notify_kind_help(kind)
    local item = kind_help[kind]
    if not item then return false end
    vim.notify(string.format("[%s] %s\n%s", kind, item.syntax, item.info), vim.log.levels.INFO)
    return true
end

--- Format a tag entry as a single human-readable string for display in pickers.
--- Pattern: `[kind] name -> relative/path:lnum`
---
--- @param entry {kind:string, name:string, file:string, lnum:number}
--- @return string
local function format_tag_entry(entry)
    return string.format(
        "[%s] %s",
        kind_symbol(entry.kind),
        entry.name
    )
end

--- Read tagfiles for all persisting kinds and return a flat, sorted list of
--- entries ready for display in a picker.
---
--- When `kind_filter` is given only that kind's entries are included.
---
--- @param tag_kinds table<string, TagKind>
--- @param load_tagfile fun(kind_name: string): table
--- @param kind_filter? string
--- @return table[]
local function collect_picker_entries(tag_kinds, load_tagfile, kind_filter)
    local entries = {}
    for kind_name, kind in pairs(tag_kinds) do
        if kind.save_to_tagfile and (not kind_filter or kind_name == kind_filter) then
            for name, tag_entries in pairs(load_tagfile(kind_name)) do
                for _, e in ipairs(tag_entries) do
                    local item = {
                        kind = kind_name,
                        name = name,
                        file = e.file,
                        lnum = e.lnum,
                        col  = e.col,
                        pos  = { e.lnum, e.col or 1 },
                    }
                    item.text = format_tag_entry(item)
                    table.insert(entries, item)
                end
            end
        end
    end

    table.sort(entries, function(a, b) return a.text < b.text end)
    return entries
end

--- Navigate to a tag entry, placing the cursor on the tag name when possible.
---
--- Uses the kind's `open` prefix to locate the exact column; falls back to
--- column 1 when the prefix is not found on the line.
---
--- @param fluxtags table
--- @param tag_kinds table<string, TagKind>
--- @param entry {kind:string, name:string, file:string, lnum:number}
local function jump_to_picker_entry(fluxtags, tag_kinds, entry)
    local kind   = tag_kinds[entry.kind]
    local prefix = kind and kind.open or ""
    fluxtags.utils.open_file(entry.file, { bufnr = vim.api.nvim_get_current_buf() })
    local line = vim.api.nvim_buf_get_lines(0, entry.lnum - 1, entry.lnum, false)[1] or ""
    local col  = line:find(prefix .. entry.name, 1, true)
    vim.fn.cursor(entry.lnum, col or 1)
end

--- Register all :FTags* user commands and the Ctrl-] keymap.
---
--- @param fluxtags table The main fluxtags module table
function M.setup(fluxtags)
    local ns           = fluxtags.utils.ns
    local tag_kinds    = fluxtags.tag_kinds
    local load_tagfile = fluxtags.load_tagfile
    local prune_tagfile = fluxtags.prune_tagfile
    local setup_buffer  = fluxtags.setup_buffer
    local _config       = require("fluxtags_config")

    vim.api.nvim_create_user_command("FTagsUpdate", function()
        fluxtags.update_tags(false)
    end, { desc = "Scan buffer and persist tags to tagfiles" })

    -- FTagsSave is an alias kept for muscle-memory compatibility.
    vim.api.nvim_create_user_command("FTagsSave", function()
        fluxtags.update_tags(false)
    end, { desc = "Alias for FTagsUpdate" })

    vim.api.nvim_create_user_command("FTagsLoad", function()
        local total = fluxtags.load_all_tags()
        vim.notify(
            total > 0 and string.format("Loaded %d tags", total) or "No tags",
            vim.log.levels.INFO
        )
    end, { desc = "Load all tagfiles into memory" })

    vim.api.nvim_create_user_command("FTagsHL", function()
        setup_buffer(nil, true)
    end, { desc = "Re-apply extmarks to current buffer" })

    vim.api.nvim_create_user_command("FTagsHi", function()
        _config.setup_default_highlights(fluxtags.config.highlights)
    end, { desc = "Re-link default FluxTag highlight groups" })

    -- Debug: show pattern matches and extmark state for the current line.
    vim.api.nvim_create_user_command("FTagsDebug", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local line  = vim.api.nvim_get_current_line()
        local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

        local info = {
            buffer        = bufnr,
            conceallevel  = vim.opt_local.conceallevel:get(),
            concealcursor = vim.opt_local.concealcursor:get(),
            extmarks      = #all_extmarks,
            kinds         = {},
        }
        for name, kind in pairs(tag_kinds) do
            local matches = {}
            for m in line:gmatch(kind.pattern) do table.insert(matches, m) end
            table.insert(info.kinds, {
                name     = name,
                pattern  = kind.pattern,
                hl_group = kind.hl_group,
                hl       = kind.hl_group and vim.api.nvim_get_hl(0, { name = kind.hl_group }) or nil,
                priority = kind.priority,
                matches  = matches,
            })
        end
        vim.notify(vim.inspect(info), vim.log.levels.INFO)
    end, { desc = "Dump fluxtags debug info for current line" })

    -- Debug: dump every extmark in the fluxtags namespace for the buffer.
    vim.api.nvim_create_user_command("FTagsDebugMarks", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
        vim.notify(vim.inspect(marks), vim.log.levels.INFO)
    end, { desc = "Dump all fluxtags extmarks in current buffer" })

    -- Debug: dump extmarks that cover the cursor position.
    vim.api.nvim_create_user_command("FTagsDebugAtCursor", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local row   = vim.fn.line(".") - 1
        local col   = vim.fn.col(".") - 1
        local line_marks = vim.api.nvim_buf_get_extmarks(
            bufnr, ns, { row, 0 }, { row, -1 }, { details = true }
        )
        local at_cursor = {}
        for _, mark in ipairs(line_marks) do
            local start_col = mark[3]
            local details   = mark[4] or {}
            local end_col   = details.end_col or start_col
            local end_row   = details.end_row or row
            if end_row == row and col >= start_col and col < end_col then
                table.insert(at_cursor, mark)
            end
        end
        vim.notify(vim.inspect({ row = row, col = col, marks = at_cursor }), vim.log.levels.INFO)
    end, { desc = "Dump fluxtags extmarks covering the cursor" })

    vim.api.nvim_create_user_command("FTagsList", function(opts)
        local kind_filter = opts.args ~= "" and opts.args or nil
        if kind_filter and not tag_kinds[kind_filter] then
            vim.notify("Unknown tag kind: " .. kind_filter, vim.log.levels.ERROR)
            return
        end

        local entries = collect_picker_entries(tag_kinds, load_tagfile, kind_filter)
        if #entries == 0 then
            vim.notify("No tags", vim.log.levels.INFO)
            return
        end

        local title = kind_filter and ("Tags (" .. kind_filter .. ")") or "Tags"

        -- Picker priority: snacks.nvim > telescope > vim.notify fallback.
        local ok_snacks, snacks = pcall(require, "snacks")
        if ok_snacks and snacks.picker then
            snacks.picker.pick({
                title   = title,
                items   = entries,
                format  = "text",
                preview = "file",
                confirm = function(picker, item)
                    picker:close()
                    if item then jump_to_picker_entry(fluxtags, tag_kinds, item) end
                end,
            })
            return
        end

        local ok_telescope, telescope = pcall(require, "telescope.pickers")
        if ok_telescope then
            local finders     = require("telescope.finders")
            local conf        = require("telescope.config").values
            local actions     = require("telescope.actions")
            local action_state = require("telescope.actions.state")
            local previewers  = require("telescope.previewers")

            telescope.new({}, {
                prompt_title = title,
                finder = finders.new_table({
                    results = entries,
                    entry_maker = function(entry)
                        return {
                            value    = entry,
                            display  = entry.text,
                            ordinal  = entry.kind .. entry.name .. entry.file .. entry.lnum,
                        }
                    end,
                }),
                previewer = previewers.new_buffer_previewer({
                    define_preview = function(self, entry)
                        conf.buffer_previewer_maker(entry.value.file, self.state.bufnr, {
                            bufname = self.state.bufname,
                        })
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
                        jump_to_picker_entry(fluxtags, tag_kinds, selection.value)
                    end)
                    return true
                end,
            }):find()
            return
        end

        -- Last resort: dump all entries as a notification.
        local lines = {}
        for _, e in ipairs(entries) do table.insert(lines, e.text) end
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, {
        nargs    = "?",
        desc     = "Open a picker of saved tags; optional kind argument filters results",
        complete = function()
            local kinds = {}
            for name, kind in pairs(tag_kinds) do
                if kind.save_to_tagfile then table.insert(kinds, name) end
            end
            table.sort(kinds)
            return kinds
        end,
    })

    vim.api.nvim_create_user_command("FTagsCfgList", function()
        local cfg_mod = require("tagkinds.cfg")
        local directives = cfg_mod.get_directives_info()
        
        if #directives == 0 then
            vim.notify("No cfg directives registered", vim.log.levels.INFO)
            return
        end
        
        -- Try to use snacks picker if available
        local ok, snacks = pcall(require, "snacks")
        if ok and snacks.picker then
            local items = {}
            for _, dir in ipairs(directives) do
                table.insert(items, {
                    text = string.format("%-16s %s", dir.key, dir.description),
                    title = dir.key,
                    key = dir.key,
                    desc = dir.description,
                })
            end
            snacks.picker.pick({
                items = items,
                title = "Cfg Directives",
                format = "text",
                confirm = function(picker) end,
            })
            return
        end
        
        -- Try to use telescope if available
        local ok_tel, telescope = pcall(require, "telescope.builtin")
        if ok_tel then
            local make_entry = require("telescope.make_entry")
            local finders = require("telescope.finders")
            local pickers = require("telescope.pickers")
            local conf = require("telescope.config").values
            
            local finder = finders.new_table({
                results = directives,
                entry_maker = function(entry)
                    return {
                        value = entry.key,
                        display = string.format("%-16s %s", entry.key, entry.description),
                        ordinal = entry.key,
                    }
                end,
            })
            
            pickers.new({}, {
                prompt_title = "Cfg Directives",
                finder = finder,
                sorter = conf.generic_sorter({}),
                attach_mappings = function(prompt_bufnr, map)
                    local actions = require("telescope.actions")
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)
                    end)
                    return true
                end,
            }):find()
            return
        end
        
        -- Fallback: show in notification
        local lines = { "Cfg Directives:" }
        for _, dir in ipairs(directives) do
            table.insert(lines, string.format("  %-16s %s", dir.key, dir.description))
        end
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, { desc = "List all registered cfg directives with descriptions" })

    vim.api.nvim_create_user_command("FTagsPreview", function(opts)
        local kind = opts.args ~= "" and opts.args or nil
        if kind then
            if not notify_kind_help(kind) then
                vim.notify("Unknown tag kind: " .. kind, vim.log.levels.ERROR)
            end
            return
        end

        local lines = {
            "Tag kinds:",
            "  mark: " .. kind_help.mark.syntax,
            "  ref:  " .. kind_help.ref.syntax,
            "  refog:" .. kind_help.refog.syntax,
            "  bib:  " .. kind_help.bib.syntax,
            "  og:   " .. kind_help.og.syntax,
            "  hl:   " .. kind_help.hl.syntax,
            "  cfg:  " .. kind_help.cfg.syntax,
            "",
            "Use :FTagsPreview <kind> for details.",
        }
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, {
        nargs = "?",
        desc = "Show syntax and quick help for tag kinds",
        complete = function()
            return { "mark", "ref", "refog", "bib", "og", "hl", "cfg" }
        end,
    })

    vim.api.nvim_create_user_command("FTagsTree", function(opts)
        local output_file = opts.args and opts.args ~= "" and opts.args or nil
        
        -- Load mark and og tags from tagfiles
        local marks = load_tagfile("mark") or {}
        local ogs = load_tagfile("og") or {}
        
        local lines = {}
        table.insert(lines, "# Fluxtags Project Tree")
        table.insert(lines, "")
        table.insert(lines, "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
        table.insert(lines, "")
        
        -- Marks section
        if next(marks) then
            table.insert(lines, "## Marks (@@@name)")
            table.insert(lines, "")
            local sorted_marks = {}
            for name, entries in pairs(marks) do
                table.insert(sorted_marks, { name = name, entry = entries[1] })
            end
            table.sort(sorted_marks, function(a, b) return a.name < b.name end)
            
            for _, item in ipairs(sorted_marks) do
                local entry = item.entry
                local file = entry.file:gsub("^" .. vim.loop.cwd() .. "/", "")
                table.insert(lines, string.format("- `@@@%s` — %s:%d", item.name, file, entry.lnum))
            end
            table.insert(lines, "")
        end
        
        -- OG tags section
        if next(ogs) then
            table.insert(lines, "## Topics (@##name)")
            table.insert(lines, "")
            local sorted_ogs = {}
            for name, entries in pairs(ogs) do
                table.insert(sorted_ogs, { name = name, entries = entries })
            end
            table.sort(sorted_ogs, function(a, b) return a.name < b.name end)
            
            for _, item in ipairs(sorted_ogs) do
                table.insert(lines, string.format("### @##%s (%d occurrences)", item.name, #item.entries))
                for _, entry in ipairs(item.entries) do
                    local file = entry.file:gsub("^" .. vim.loop.cwd() .. "/", "")
                    table.insert(lines, string.format("  - %s:%d", file, entry.lnum))
                end
                table.insert(lines, "")
            end
        end
        
        -- Output
        if output_file then
            vim.fn.writefile(lines, output_file)
            vim.notify(
                string.format("Project tree written to %s (%d lines)", output_file, #lines),
                vim.log.levels.INFO
            )
        else
            vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
        end
    end, {
        nargs = "?",
        desc = "Generate project tree of marks and og tags (optional output file path)",
    })

    vim.api.nvim_create_user_command("FTagsClear", function()
        local cleared = 0
        for _, kind in pairs(tag_kinds) do
            if kind.save_to_tagfile and kind.tagfile then
                vim.fn.writefile({}, kind.tagfile)
                cleared = cleared + 1
            end
        end
        vim.notify(string.format("Cleared %d tagfiles", cleared), vim.log.levels.INFO)
    end, { desc = "Truncate all tagfiles" })

    vim.api.nvim_create_user_command("FTagsPrune", function()
        local removed = 0
        for kind_name, kind in pairs(tag_kinds) do
            if kind.save_to_tagfile then
                removed = removed + prune_tagfile(kind_name)
            end
        end
        vim.notify(string.format("Removed %d stale tag entries", removed), vim.log.levels.INFO)
    end, { desc = "Remove stale entries from all tagfiles" })

    vim.keymap.set("n", "<C-]>", fluxtags.jump_to_tag, { desc = "Jump to fluxtag under cursor" })
end

return M
