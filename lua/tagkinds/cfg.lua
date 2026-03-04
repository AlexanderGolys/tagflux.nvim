--- @brief [[
---     cfg — buffer configuration directives.
---
---     Syntax: `$$$<key>(<value>)`
---     Directives are applied once when the buffer is first entered (via the
---     on_enter hook), before any highlighting. They let files carry their own
---     Neovim settings without relying on modelines or per-directory configs.
---
---     Built-in keys:
---       ft(<name>)           Set the buffer filetype
---       conceallevel(<0-3>)  Set conceallevel for this buffer
---       fluxtags(off)        Disable all fluxtags processing in this buffer
---       modeline(<cmd>)      Execute an arbitrary Ex command in this buffer
---
---     Unknown keys are highlighted with FluxTagError and emitted as ERROR
---     diagnostics. Use M.register_handler to add known keys at runtime.
---
---     No jump target. Nothing is saved to a tagfile.
---     The `$$$` prefix is concealed to `$` when conceallevel >= 1.
--- @brief ]]

-- @@@fluxtags.cfg
-- @##tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")

local M = {}

--- Descriptions for each supported directive key.
--- @type table<string, string>
local directive_descriptions = {
    ft = "Set the buffer filetype (e.g., ft(lua))",
    conceallevel = "Set conceallevel for this buffer (0-3)",
    fluxtags = "Disable all fluxtags processing (off)",
    fluxtags_hl = "Disable highlighting in regions (e.g., fluxtags_hl(start,end))",
    fluxtags_reg = "Disable tag registration in regions (e.g., fluxtags_reg(start,end))",
    modeline = "Execute an arbitrary Ex command",
}

--- Handlers for each supported directive key.
--- Each handler receives the parenthesised value string and the target bufnr.
--- @type table<string, fun(value: string, bufnr: number)>
local directive_handlers = {
    ft = function(value, bufnr)
        vim.bo[bufnr].filetype = value
    end,
    conceallevel = function(value, bufnr)
        local level = tonumber(value) or 0
        for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
            if vim.api.nvim_win_is_valid(winid) then
                vim.wo[winid].conceallevel = level
            end
        end
    end,
    fluxtags = function(value, bufnr)
        if value == "off" then
            vim.b[bufnr].fluxtags_disabled = true
        end
    end,
    fluxtags_hl = function(value, bufnr)
        -- Handled dynamically via get_disabled_intervals
    end,
    fluxtags_reg = function(value, bufnr)
        -- Handled dynamically via get_disabled_intervals
    end,
    modeline = function(value, bufnr)
        vim.api.nvim_buf_call(bufnr, function()
            pcall(vim.cmd, value)
        end)
    end,
}

--- Return the sorted list of currently registered directive keys.
---
--- @return string[]
function M.known_keys()
    local keys = {}
    for k in pairs(directive_handlers) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

--- Get all registered directives with their descriptions as a list of tables.
---
--- @return {key: string, description: string}[]
function M.get_directives_info()
    local directives = {}
    for key in pairs(directive_handlers) do
        table.insert(directives, {
            key = key,
            description = directive_descriptions[key] or "No description available",
        })
    end
    table.sort(directives, function(a, b) return a.key < b.key end)
    return directives
end

--- Register a custom directive handler at runtime.
--- Allows other plugins or user config to extend cfg without forking the module.
---
--- @param key string Directive name (e.g. "mykey")
--- @param handler fun(value: string, bufnr: number)
--- @param description? string Optional description for the directive
function M.register_handler(key, handler, description)
    directive_handlers[key] = handler
    if description then
        directive_descriptions[key] = description
    end
end

--- Register the `cfg` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local cfg, opts = kind_common.resolve_kind_config(
        fluxtags,
        "cfg",
        {
            name = "cfg",
            hl_group = "FluxTagCfg",
            open = "$$$",
        },
        prefix_util.default_comment_prefix_patterns
    )

    local kind_name = opts.name
    -- base_pattern matches the key. Arguments are extracted from the suffix.
    local base_pattern = "%$%$%$([%w_]+)"
    local pattern      = cfg.pattern  -- nil = use built-in two-step extraction
    local prefix_patterns = opts.comment_prefix_patterns
    local search_pattern = pattern or base_pattern
    local parse_args = not pattern

    ---@param line string
    ---@return {s:number, e:number, key:string, value:string, tag_end:number}[]
    local function parse_line_directives(line)
        local directives = {}
        local search_from = 1

        while true do
            local s, e, key = line:find(search_pattern, search_from)
            if not s then break end

            local value = ""
            local tag_end = e
            if parse_args then
                local args = line:sub(e + 1):match("^%b()")
                if args then
                    value = args:sub(2, -2)
                    tag_end = e + #args
                end
            end

            table.insert(directives, {
                s = s,
                e = e,
                key = key,
                value = value,
                tag_end = tag_end,
            })
            search_from = e + 1
        end

        return directives
    end

    local cfg_diag_ns = fluxtags.utils.make_diag_ns("cfg")

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern or base_pattern,
        hl_group        = opts.hl_group,
        priority        = opts.priority,
        save_to_tagfile = false,

        extract_name = function(match) return match end,

        on_jump = function(name, ctx) return false end,

        --- Parse every directive on every line and apply the matching handler.
        --- Runs once on buffer enter before extmarks are drawn.
        on_enter = function(bufnr, lines)
            for _, line in ipairs(lines) do
                for _, directive in ipairs(parse_line_directives(line)) do
                    local key = directive.key
                    if directive_handlers[key] then
                        local ok, err = pcall(directive_handlers[key], directive.value, bufnr)
                        if not ok then
                            vim.notify("fluxtags cfg: " .. key .. ": " .. tostring(err), vim.log.levels.WARN)
                        end
                    end
                end
            end
        end,
    })

    --- Custom extmark logic: the args pattern is wider than base_pattern, so we
    --- extend the highlight to cover the parenthesised argument as well.
    --- @param is_disabled? fun(lnum: number, col: number): boolean
    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority    = self.priority or 1100
        local open        = opts.open
        local conceal_char = cfg.conceal_open or open:sub(1, 1)

        for _, directive in ipairs(parse_line_directives(line)) do
            local s = directive.s
            local highlight_end = directive.tag_end

            local prefix_start, prefix_text = prefix_util.find_prefix(line, s, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open

            if not (is_disabled and is_disabled(lnum, col0)) then
                -- Conceal `$$$` to a single `$`.
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                    end_col  = col0 + open_len,
                    conceal  = conceal_char,
                    hl_group = self.hl_group,
                    priority = priority,
                })

                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + open_len, {
                    end_col  = highlight_end,
                    hl_group = self.hl_group,
                    priority = priority,
                })
            end
        end
    end

    --- Scan all lines for cfg tags; emit error extmarks and diagnostics for
    --- unknown directive keys.
    --- @param is_disabled? fun(lnum: number, col: number): boolean
    function kind:apply_diagnostics(bufnr, lines, is_disabled)
        local open     = opts.open
        local priority = (self.priority or 1100) + 10
        local diags    = {}

        for lnum0, line in ipairs(lines) do
            for _, directive in ipairs(parse_line_directives(line)) do
                local s = directive.s
                local key = directive.key
                local arg_end = directive.tag_end

                local prefix_start, prefix_text = prefix_util.find_prefix(line, s, prefix_patterns)
                local col0 = prefix_start - 1
                local open_len = #prefix_text + #open
                if not (is_disabled and is_disabled(lnum0 - 1, col0)) then
                    if not directive_handlers[key] then
                        local key_col0  = col0 + open_len
                        local key_end   = key_col0 + #key

                        -- Error highlight over prefix + key + args.
                        pcall(vim.api.nvim_buf_set_extmark, bufnr, fluxtags.utils.ns, lnum0 - 1, col0, {
                            end_col  = arg_end,
                            hl_group = "FluxTagError",
                            priority = priority,
                        })

                        table.insert(diags, {
                            bufnr    = bufnr,
                            lnum     = lnum0 - 1,
                            col      = key_col0,
                            end_col  = key_end,
                            severity = vim.diagnostic.severity.ERROR,
                            message  = "Unknown cfg directive: " .. key,
                            source   = "fluxtags.cfg",
                        })
                    end
                end
            end
        end

        fluxtags.utils.set_diagnostics(bufnr, cfg_diag_ns, diags)
    end

    --- Get disabled intervals for a specific directive (e.g. "fluxtags_hl")
    --- Returns an array of { start_lnum, start_col, end_lnum, end_col }
    function kind:get_disabled_intervals(lines, directive_name)
        local intervals = {}
        local is_off = false
        local start_pos = nil

        for lnum0, line in ipairs(lines) do
            for _, item in ipairs(parse_line_directives(line)) do
                local s = item.s
                local key = item.key

                if key == directive_name then
                    local value = item.value
                    local tag_end = item.tag_end

                    if value == "off" and not is_off then
                        is_off = true
                        start_pos = { lnum0 - 1, tag_end }
                    elseif value == "on" and is_off then
                        is_off = false
                        table.insert(intervals, { start_pos[1], start_pos[2], lnum0 - 1, s - 1 })
                        start_pos = nil
                    end
                end
            end
        end

        if is_off then
            table.insert(intervals, { start_pos[1], start_pos[2], math.huge, math.huge })
        end

        return intervals
    end

    fluxtags.register_kind(kind)
end

return M
