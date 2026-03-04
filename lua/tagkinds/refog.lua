--- @brief [[
---     refog — references to og hashtag tags.
---
---     Syntax: `#|#||<name>||`
---     Unlike `og` tags, refog entries are not persisted to a tagfile and do
---     not create additional hashtag occurrences. They only resolve and jump to
---     existing saved `og` entries.
--- @brief ]]

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")

local M = {}

--- Register the `refog` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local cfg      = (fluxtags.config.kinds and fluxtags.config.kinds.refog) or {}
    local og_cfg   = (fluxtags.config.kinds and fluxtags.config.kinds.og) or {}
    local kind_name = cfg.name     or "refog"
    local pattern   = cfg.pattern  or "#|#||([%w_.%-%+%*%/%\\:]+)||"
    local hl_group  = cfg.hl_group or "FluxTagRef"
    local open      = cfg.open     or "#|#||"
    local close     = cfg.close    or "||"
    local conceal_open  = cfg.conceal_open  or "#"
    local conceal_close = cfg.conceal_close or ""
    local prefix_patterns = cfg.comment_prefix_patterns or prefix_util.default_comment_prefix_patterns
    local og_kind_name  = og_cfg.name or "og"

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = cfg.priority,
        save_to_tagfile = false,

        is_valid = function(name)
            return name:match("^[%w_.%-%+%*%/%\\:]+$") ~= nil
        end,

        conceal_pattern = function(name)
            return {
                { offset = 0,             length = #open,  char = conceal_open },
                { offset = #open,         length = #name,  hl_group = hl_group },
                { offset = #open + #name, length = #close, char = conceal_close },
            }
        end,

        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(og_kind_name)
            local entries = tags[name]
            if not entries or #entries == 0 then
                vim.notify("No og tags found: #" .. name, vim.log.levels.WARN)
                return true
            end

            local ok_telescope, telescope = pcall(require, "telescope.pickers")
            if ok_telescope then
                local finders      = require("telescope.finders")
                local conf         = require("telescope.config").values
                local actions      = require("telescope.actions")
                local action_state = require("telescope.actions.state")
                local previewers   = require("telescope.previewers")

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
                    previewer = previewers.new_buffer_previewer({
                        define_preview = function(self, entry)
                            conf.buffer_previewer_maker(entry.value.file, self.state.bufnr, {
                                bufname = self.state.bufname,
                            })
                            vim.api.nvim_buf_call(self.state.bufnr, function()
                                vim.fn.cursor(entry.value.lnum, entry.value.col or 1)
                            end)
                        end,
                    }),
                    sorter = conf.generic_sorter({}),
                    attach_mappings = function(prompt_bufnr)
                        actions.select_default:replace(function()
                            actions.close(prompt_bufnr)
                            local selection = action_state.get_selected_entry()
                            ctx.utils.open_file(selection.value.file, ctx)
                            vim.fn.cursor(selection.value.lnum, selection.value.col or 1)
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
                        ctx.utils.open_file(choice.file, ctx)
                        vim.fn.cursor(choice.lnum, choice.col or 1)
                    end
                end)
            end

            return true
        end,
    })

    function kind:find_at_cursor(line, col)
        local search_from = 1
        while true do
            local s, e, name = line:find(self.pattern, search_from)
            if not s then return nil end
            local prefix_start = prefix_util.find_prefix(line, s, prefix_patterns)
            if col >= prefix_start and col <= e then return name, prefix_start, e end
            search_from = e + 1
        end
    end

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100
        for match_start, name in line:gmatch("()" .. pattern) do
            local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open

            local is_disabled_tag = is_disabled and is_disabled(lnum, col0)

            if not is_disabled_tag then
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                    end_col  = col0 + open_len,
                    conceal  = conceal_open,
                    hl_group = self.hl_group,
                    priority = priority,
                })
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0 + open_len, {
                    end_col  = col0 + open_len + #name,
                    hl_group = self.hl_group,
                    priority = priority,
                })
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0 + open_len + #name, {
                    end_col  = col0 + open_len + #name + #close,
                    conceal  = conceal_close,
                    hl_group = self.hl_group,
                    priority = priority,
                })
            end
        end
    end

    fluxtags.register_kind(kind)
end

return M
