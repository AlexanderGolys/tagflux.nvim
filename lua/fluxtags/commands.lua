local M = {}

local cmd_common = require("fluxtags.commands.kind_help")
local cmd_picker = require("fluxtags.commands.tags_picker")
local cmd_debug = require("fluxtags.commands.debug")
local cmd_tree = require("fluxtags.commands.tree")

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

    local entries = cmd_picker.collect_entries(self.tag_kinds, self.load_tagfile, kind_filter)
    if #entries == 0 then
        self:_notify_info("No tags")
        return
    end

    local title = kind_filter and ("Tags (" .. kind_filter .. ")") or "Tags"
    cmd_picker.pick_tag_entries(title, entries, function(entry)
        cmd_picker.jump_to_picker_entry(self.fluxtags, self.tag_kinds, entry)
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

    if cmd_picker.pick_static_items("Cfg Directives", items) then return end

    local lines = { "Cfg Directives:" }
    for _, item in ipairs(items) do table.insert(lines, "  " .. item.text) end
    self:_notify_info(table.concat(lines, "\n"))
end

function Commands:_preview(opts)
    local kind = opts.args ~= "" and opts.args or nil
    if kind then
        if not cmd_common.notify_kind_help(kind) then
            self:_notify_error("Unknown tag kind: " .. kind)
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
    self:_notify_info(table.concat(lines, "\n"))
end

function Commands:_tree(opts)
    if not self.load_tagfile then
        return
    end
    cmd_tree.generate(self.load_tagfile, opts.args ~= "" and opts.args or nil)
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
    cmd_debug.setup(self.ns, self.tag_kinds)
end

function Commands:setup_keymap()
    vim.keymap.set("n", "<C-]>", self.fluxtags.jump_to_tag, { desc = "Jump to fluxtag under cursor" })
end

---@param fluxtags table
function Commands:setup()
    self:_register("FTagsUpdate", function() self:_update_tags() end, {
        desc = "Scan buffer and persist tags to tagfiles",
    })
    self:_register("FTagsSave", function() self:_update_tags() end, {
        desc = "Alias for FTagsUpdate",
    })
    self:_register("FTagsLoad", function() self:_load_all() end, {
        desc = "Load all tagfiles into memory",
    })
    self:_register("FTagsHL", function() self:_reapply_buffer_highlights() end, {
        desc = "Re-apply extmarks to current buffer",
    })
    self:_register("FTagsHi", function() self:_relink_highlights() end, {
        desc = "Re-link default FluxTag highlight groups",
    })
    self:_register("FTagsList", function(opts) self:_list_tags(opts) end, {
        nargs = "?",
        desc = "Open a picker of saved tags; optional kind argument filters results",
        complete = function() return self:_pickable_kinds() end,
    })
    self:_register("FTagsCfgList", function() self:_cfg_list() end, {
        desc = "List all registered cfg directives with descriptions",
    })
    self:_register("FTagsPreview", function(opts) self:_preview(opts) end, {
        nargs = "?",
        desc = "Show syntax and quick help for tag kinds",
        complete = function() return cmd_common.preview_kinds() end,
    })
    self:_register("FTagsTree", function(opts) self:_tree(opts) end, {
        nargs = "?",
        desc = "Generate project tree of marks and og tags (optional output file path)",
    })
    self:_register("FTagsClear", function() self:_clear() end, {
        desc = "Truncate all tagfiles",
    })
    self:_register("FTagsPrune", function() self:_prune() end, {
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
