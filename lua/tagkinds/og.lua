local tag_kind = require("tag_kind")

local M = {}

function M.register(fluxtags)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.og) or {}
    local kind_name = cfg.name or "og"
    local pattern = cfg.pattern or "#(%S+)"
    local hl_group = cfg.hl_group or "FluxTagOg"

    local kind = tag_kind.new({
        name = kind_name,
        pattern = pattern,
        hl_group = hl_group,
        priority = cfg.priority,
        save_to_tagfile = true,
        
        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(ctx.kind_name)
            local entries = tags[name]
            
            if not entries or #entries == 0 then
                vim.notify("No tags found: #" .. name, vim.log.levels.WARN)
                return true
            end

            if #entries == 1 then
                local t = entries[1]
                vim.cmd("edit " .. vim.fn.fnameescape(t.file))
                vim.fn.cursor(t.lnum, 1)
                return true
            end

            local ok, telescope = pcall(require, "telescope.pickers")
            if ok then
                local finders = require("telescope.finders")
                local conf = require("telescope.config").values
                local actions = require("telescope.actions")
                local action_state = require("telescope.actions.state")

                telescope.new({}, {
                    prompt_title = "#" .. name,
                    finder = finders.new_table({
                        results = entries,
                        entry_maker = function(entry)
                            return {
                                value = entry,
                                display = string.format("%s:%d", vim.fn.fnamemodify(entry.file, ":~:."), entry.lnum),
                                ordinal = entry.file .. entry.lnum,
                            }
                        end,
                    }),
                    sorter = conf.generic_sorter({}),
                    attach_mappings = function(prompt_bufnr)
                        actions.select_default:replace(function()
                            actions.close(prompt_bufnr)
                            local selection = action_state.get_selected_entry()
                            vim.cmd("edit " .. vim.fn.fnameescape(selection.value.file))
                            vim.fn.cursor(selection.value.lnum, 1)
                        end)
                        return true
                    end,
                }):find()
            else
                vim.ui.select(entries, {
                    prompt = "#" .. name,
                    format_item = function(entry)
                        return string.format("%s:%d", vim.fn.fnamemodify(entry.file, ":~:."), entry.lnum)
                    end,
                }, function(choice)
                    if choice then
                        vim.cmd("edit " .. vim.fn.fnameescape(choice.file))
                        vim.fn.cursor(choice.lnum, 1)
                    end
                end)
            end
            return true
        end,
    })
    
    fluxtags.register_kind(kind)
end

return M
