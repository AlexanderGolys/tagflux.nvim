local M = {}

local cmd_common = require("fluxtags.commands.kind_help")
local cmd_picker = require("fluxtags.commands.tags_picker")
local cmd_debug = require("fluxtags.commands.debug")
local cmd_tree = require("fluxtags.commands.tree")

---@param fluxtags table
function M.setup(fluxtags)
    local ns = fluxtags.utils.ns
    local tag_kinds = fluxtags.tag_kinds
    local load_tagfile = fluxtags.load_tagfile
    local prune_tagfile = fluxtags.prune_tagfile
    local setup_buffer = fluxtags.setup_buffer
    local _config = require("fluxtags_config")

    local function update_tags()
        fluxtags.update_tags(false)
    end

    vim.api.nvim_create_user_command("FTagsUpdate", update_tags, { desc = "Scan buffer and persist tags to tagfiles" })
    vim.api.nvim_create_user_command("FTagsSave", update_tags, { desc = "Alias for FTagsUpdate" })

    vim.api.nvim_create_user_command("FTagsLoad", function()
        local total = fluxtags.load_all_tags()
        vim.notify(total > 0 and ("Loaded %d tags"):format(total) or "No tags", vim.log.levels.INFO)
    end, { desc = "Load all tagfiles into memory" })

    vim.api.nvim_create_user_command("FTagsHL", function() setup_buffer(nil, true) end, {
        desc = "Re-apply extmarks to current buffer",
    })

    vim.api.nvim_create_user_command("FTagsHi", function()
        _config.setup_default_highlights(fluxtags.config.highlights)
    end, { desc = "Re-link default FluxTag highlight groups" })

    cmd_debug.setup(ns, tag_kinds)

    vim.api.nvim_create_user_command("FTagsList", function(opts)
        local kind_filter = opts.args ~= "" and opts.args or nil
        if kind_filter and not tag_kinds[kind_filter] then
            vim.notify("Unknown tag kind: " .. kind_filter, vim.log.levels.ERROR)
            return
        end

        local entries = cmd_picker.collect_entries(tag_kinds, load_tagfile, kind_filter)
        if #entries == 0 then
            vim.notify("No tags", vim.log.levels.INFO)
            return
        end

        local title = kind_filter and ("Tags (" .. kind_filter .. ")") or "Tags"
        cmd_picker.pick_tag_entries(title, entries, function(entry)
            cmd_picker.jump_to_picker_entry(fluxtags, tag_kinds, entry)
        end)
    end, {
        nargs = "?",
        desc = "Open a picker of saved tags; optional kind argument filters results",
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
        local directives = require("tagkinds.cfg").get_directives_info()
        if #directives == 0 then
            vim.notify("No cfg directives registered", vim.log.levels.INFO)
            return
        end

        local items = {}
        for _, item in ipairs(directives) do
            table.insert(items, {
                text = ("%-16s %s"):format(item.key, item.description),
                ordinal = item.key,
            })
        end

        if cmd_picker.pick_static_items("Cfg Directives", items) then return end

        local lines = { "Cfg Directives:" }
        for _, item in ipairs(items) do table.insert(lines, "  " .. item.text) end
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, { desc = "List all registered cfg directives with descriptions" })

    vim.api.nvim_create_user_command("FTagsPreview", function(opts)
        local kind = opts.args ~= "" and opts.args or nil
        if kind then
            if not cmd_common.notify_kind_help(kind) then
                vim.notify("Unknown tag kind: " .. kind, vim.log.levels.ERROR)
            end
            return
        end

        local lines = { "Tag kinds:" }
        local help = cmd_common.kind_help()
        for _, key in ipairs(cmd_common.preview_kinds()) do
            table.insert(lines, ("  %-5s %s"):format(key .. ":", help[key].syntax))
        end
        table.insert(lines, "")
        table.insert(lines, "Use :FTagsPreview <kind> for details.")
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, {
        nargs = "?",
        desc = "Show syntax and quick help for tag kinds",
        complete = function() return cmd_common.preview_kinds() end,
    })

    vim.api.nvim_create_user_command("FTagsTree", function(opts)
        cmd_tree.generate(load_tagfile, opts.args ~= "" and opts.args or nil)
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
        vim.notify(("Cleared %d tagfiles"):format(cleared), vim.log.levels.INFO)
    end, { desc = "Truncate all tagfiles" })

    vim.api.nvim_create_user_command("FTagsPrune", function()
        local removed = 0
        for kind_name, kind in pairs(tag_kinds) do
            if kind.save_to_tagfile then
                removed = removed + prune_tagfile(kind_name)
            end
        end
        vim.notify(("Removed %d stale tag entries"):format(removed), vim.log.levels.INFO)
    end, { desc = "Remove stale entries from all tagfiles" })

    vim.keymap.set("n", "<C-]>", fluxtags.jump_to_tag, { desc = "Jump to fluxtag under cursor" })
end

return M
