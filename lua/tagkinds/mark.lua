--- @brief [[
--- mark — named anchor tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed_kind")
local jump_util = require("fluxtags.jump")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local diag = require("tagkinds.diagnostics")

local M = {}

---@param fluxtags table
function M.register(fluxtags)
    -- Create a prefixed binder for mark tags with customizable pattern and display options
    -- Pattern matches "@@@name" where name contains word chars, dots, hyphens, plus, etc.
    -- Conceal mode shows "@" instead of "@@@" to save screen space
    local binder = prefixed.binder(fluxtags, "mark", {
        name = "mark",
        pattern = "@@@([%w_.%-%+%*%/%\\:]+)",
        hl_group = "FluxTagMarks",
        open = "@@@",
        conceal_open = "@",
    })
    local opts = binder.opts

    -- Create diagnostic namespace for mark-related errors (e.g., duplicate marks)
    local mark_diag_ns = fluxtags.utils.make_diag_ns("mark")
    
    -- Set up highlight group for concealed text (when tag is hidden/collapsed)
    -- Copy the base mark highlight but remove underline for cleaner appearance
    local conceal_hl_group = opts.hl_group .. "Conceal"
    local base_hl = vim.api.nvim_get_hl(0, { name = opts.hl_group })
    base_hl.underline = false
    vim.api.nvim_set_hl(0, conceal_hl_group, base_hl)

    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
        save_to_tagfile = true,
        is_valid = kind_common.is_valid_name,
        -- Define how to conceal the mark tag (e.g., "@@@foo" → "@foo")
        -- Returns two regions: the opening delimiter and the mark name
        -- The opening delimiter uses conceal_hl_group (typically dimmed)
        -- The mark name uses the standard hl_group (typically highlighted)
        conceal_pattern = function(name)
            return {
                -- Conceal opening "@@@" → "@" using dimmed style
                { offset = 0, length = #opts.open, char = opts.conceal_open, hl_group = conceal_hl_group },
                -- Highlight the mark name itself with standard highlighting
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
            }
        end,
        -- Handle jumping to a mark tag (e.g., <C-]> on "@@@foo" → jump to mark "foo")
        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(ctx.kind_name)
            local entries, resolved = jump_util.find_entries(tags, name)
            if entries and entries[1] then
                return jump_util.jump_to_entry(name, resolved, entries[1], ctx)
            end
            vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
            return true
        end,
    })

    -- Attach cursor-position lookup for finding marks at cursor (e.g., for diagnostics)
    binder:attach_find_at_cursor(kind, kind_common.INLINE_SUBTAG_PATTERN)
    
    -- Attach extmarks for visual display with prefix support and conceal mode
    binder:attach_prefixed_extmarks(kind, {
        open = opts.open,
        conceal_open = opts.conceal_open,
    })

    -- Scan buffer for duplicate mark definitions and emit diagnostics
    -- Fluxtags marks must be unique; duplicates are flagged as errors
    function kind:apply_diagnostics(bufnr, lines)
        ---@type table<string, {lnum:number, col:number, prefix_len:number}[]>
        local occurrences, diags = {}, {}

        -- First pass: collect all mark definitions and their locations
        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                if name:match("^[%w_.%-%+%*%/%\\:]+$") then
                    -- Find any comment prefix before the mark (e.g., "-- " in Lua)
                    local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, opts.comment_prefix_patterns)
                    occurrences[name] = occurrences[name] or {}
                    table.insert(occurrences[name], {
                        lnum = lnum - 1,
                        col = prefix_start - 1,
                        prefix_len = #prefix_text,
                    })
                end
            end
        end

        -- Second pass: flag duplicates as errors (marks appearing more than once)
        for name, locs in pairs(occurrences) do
            if #locs > 1 then
                for _, loc in ipairs(locs) do
                    -- Calculate exact column range of the mark name for highlighting
                    local name_col0 = loc.col + loc.prefix_len + #opts.open
                    local name_end = name_col0 + #name
                    -- Add visual extmark error indicator
                    diag.error_extmark(bufnr, fluxtags.utils.ns, loc.lnum, loc.col, name_end, (self.priority or 1100) + 10)
                    -- Add diagnostic entry for error reporting
                    diag.push(
                        diags,
                        bufnr,
                        loc.lnum,
                        name_col0,
                        name_end,
                        vim.diagnostic.severity.ERROR,
                        "fluxtags.mark",
                        "Duplicate mark: " .. name
                    )
                end
            end
        end

        -- Publish all collected diagnostics to the diagnostic namespace
        diag.publish(bufnr, mark_diag_ns, diags, fluxtags.utils.set_diagnostics)
    end

    fluxtags.register_kind(kind)
end

return M
