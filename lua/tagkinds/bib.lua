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
local kind_common = require("tagkinds.common")

local M = {}

--- Register the `bib` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local _, opts = kind_common.resolve_kind_config(
        fluxtags,
        "bib",
        {
            name = "bib",
            pattern = "///(%S+)",
            hl_group = "FluxTagBib",
            open = "///",
            conceal_open = "/",
        },
        prefix_util.default_comment_prefix_patterns
    )
    local kind_name = opts.name
    local pattern = opts.pattern
    local hl_group = opts.hl_group
    local open = opts.open
    local conceal_open = opts.conceal_open
    local prefix_patterns = opts.comment_prefix_patterns

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = opts.priority,
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
        return prefix_util.find_tag_at_cursor(line, col, self.pattern, prefix_patterns)
    end

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        prefix_util.apply_prefixed_extmarks(bufnr, ns, lnum, line, self.pattern, prefix_patterns, {
            open = open,
            conceal_open = conceal_open,
            hl_group = self.hl_group,
            priority = self.priority,
        }, is_disabled)
    end

    fluxtags.register_kind(kind)
end

return M
