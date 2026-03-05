local common = require("fluxtags.commands.common")

local M = {}

---@param title string
---@param items {text:string, ordinal?:string}[]
---@return boolean
function M.pick_static_items(title, items)
    local ok_telescope, pickers = pcall(require, "telescope.pickers")
    if not ok_telescope then return false end

    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")

    pickers.new({}, {
        prompt_title = title,
        finder = finders.new_table({
            results = items,
            entry_maker = function(entry)
                return { value = entry, display = entry.text, ordinal = entry.ordinal or entry.text }
            end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function() actions.close(prompt_bufnr) end)
            return true
        end,
    }):find()

    return true
end

---@param tag_kinds table<string, TagKind>
---@param load_tagfile fun(kind_name: string): table
---@param kind_filter? string
---@return table[]
function M.collect_entries(tag_kinds, load_tagfile, kind_filter)
    local entries = {}
    for kind_name, kind in pairs(tag_kinds) do
        if kind.save_to_tagfile and (not kind_filter or kind_name == kind_filter) then
            for name, tag_entries in pairs(load_tagfile(kind_name)) do
                for _, e in ipairs(tag_entries) do
                    table.insert(entries, {
                        kind = kind_name,
                        name = name,
                        file = e.file,
                        lnum = e.lnum,
                        col = e.col,
                        text = ("[%s] %s"):format(common.kind_symbol(kind_name), name),
                    })
                end
            end
        end
    end

    table.sort(entries, function(a, b) return a.text < b.text end)
    return entries
end

---@param title string
---@param entries table[]
---@param on_confirm fun(entry: table)
function M.pick_tag_entries(title, entries, on_confirm)
    local ok_telescope, telescope = pcall(require, "telescope.pickers")
    if ok_telescope then
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local previewers = require("telescope.previewers")

        telescope.new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = entries,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.text,
                        ordinal = entry.kind .. entry.name .. entry.file .. entry.lnum,
                    }
                end,
            }),
            previewer = previewers.new_buffer_previewer({
                define_preview = function(self, entry)
                    conf.buffer_previewer_maker(entry.value.file, self.state.bufnr, { bufname = self.state.bufname })
                    vim.api.nvim_buf_call(self.state.bufnr, function() vim.fn.cursor(entry.value.lnum, 1) end)
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    if selection and selection.value then on_confirm(selection.value) end
                end)
                return true
            end,
        }):find()
        return
    end

    local lines = {}
    for _, entry in ipairs(entries) do table.insert(lines, entry.text) end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param fluxtags table
---@param tag_kinds table<string, TagKind>
---@param entry {kind:string,name:string,file:string,lnum:number}
function M.jump_to_picker_entry(fluxtags, tag_kinds, entry)
    local kind = tag_kinds[entry.kind]
    local prefix = kind and kind.open or ""
    fluxtags.utils.open_file(entry.file, { bufnr = vim.api.nvim_get_current_buf() })
    local line = vim.api.nvim_buf_get_lines(0, entry.lnum - 1, entry.lnum, false)[1] or ""
    local col = line:find(prefix .. entry.name, 1, true)
    vim.fn.cursor(entry.lnum, col or 1)
end

return M
