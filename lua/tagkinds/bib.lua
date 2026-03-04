--- @brief [[
---     bib — external link tags.
---
---     Syntax: `-- ///<target>`
---     Pressing Ctrl-] opens the target with the appropriate handler:
---       - URLs (http/https/www)  -> vim.ui.open (browser)
---       - Readable file paths    -> vim.ui.open (system default)
---       - Anything else          -> :help <target> (Vim help)
---
---     Bibs are not saved to a tagfile and cannot be listed via :FTagsList.
---     The `-- ///` prefix is concealed to `/` when conceallevel >= 1.
--- @brief ]]

-- @@@fluxtags.bib
-- ###tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")

local M = {}

--- Register the `bib` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local cfg       = (fluxtags.config.kinds and fluxtags.config.kinds.bib) or {}
    local kind_name = cfg.name     or "bib"
    local pattern   = cfg.pattern  or "///(%S+)"
    local hl_group  = cfg.hl_group or "FluxTagBib"
    local open      = cfg.open     or "///"
    local conceal_open = cfg.conceal_open or "/"
    local prefix_patterns = cfg.comment_prefix_patterns or prefix_util.default_comment_prefix_patterns

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = cfg.priority,
        save_to_tagfile = false,

        --- Conceal optional comment prefix + `///` to `/`.
        conceal_pattern = function(target)
            return {
                { offset = 0,     length = #open,   char = conceal_open },
                { offset = #open, length = #target,  hl_group = hl_group },
            }
        end,

        --- Open the target using the most appropriate handler.
        on_jump = function(target, ctx)
            if target:match("^https?://") or target:match("^www%.") then
                vim.ui.open(target)
                return true
            end

            local expanded = vim.fn.expand(target)
            if vim.fn.filereadable(expanded) == 1 then
                vim.ui.open(expanded)
                return true
            end

            -- Treat anything unrecognised as a Vim help topic.
            local ok = pcall(vim.cmd, "help " .. target)
            if ok then return true end

            vim.notify("Cannot open: " .. target, vim.log.levels.WARN)
            return true
        end,
    })

    function kind:find_at_cursor(line, col)
        local search_from = 1
        while true do
            local s, e, target = line:find(self.pattern, search_from)
            if not s then return nil end
            local prefix_start = prefix_util.find_prefix(line, s, prefix_patterns)
            if col >= prefix_start and col <= e then return target, prefix_start, e end
            search_from = e + 1
        end
    end

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100
        for match_start, target in line:gmatch("()" .. self.pattern) do
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
                    end_col  = col0 + open_len + #target,
                    hl_group = self.hl_group,
                    priority = priority,
                })
            end
        end
    end

    fluxtags.register_kind(kind)
end

return M
