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
-- ###tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")

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
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.cfg) or {}

    local kind_name = cfg.name or "cfg"
    -- Two internal patterns: base_pattern matches the key alone (used for
    -- scanning); args_pattern additionally captures parenthesised arguments
    -- (kept for reference — argument extraction is done via sub-string matching).
    local base_pattern = "%$%$%$([%w_]+)"
    local args_pattern = "%$%$%$([%w_]+)%b()"  -- luacheck: ignore (kept for docs)
    local pattern      = cfg.pattern  -- nil = use built-in two-step extraction
    local prefix_patterns = cfg.comment_prefix_patterns or prefix_util.default_comment_prefix_patterns

    local cfg_diag_ns = fluxtags.utils.make_diag_ns("cfg")

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern or base_pattern,
        hl_group        = cfg.hl_group or "FluxTagCfg",
        priority        = cfg.priority,
        save_to_tagfile = false,

        extract_name = function(match) return match end,

        on_jump = function(name, ctx) return false end,

        --- Parse every directive on every line and apply the matching handler.
        --- Runs once on buffer enter before extmarks are drawn.
        on_enter = function(bufnr, lines)
            for _, line in ipairs(lines) do
                local search_from = 1
                while true do
                    local s, e, key = line:find(pattern or base_pattern, search_from)
                    if not s then break end

                    -- Extract the parenthesised value (e.g. `(lua)` -> `lua`).
                    local value = ""
                    if not pattern then
                        local args = line:sub(e + 1):match("^%b()")
                        if args then value = args:sub(2, -2) end
                    end

                    if directive_handlers[key] then
                        local ok, err = pcall(directive_handlers[key], value, bufnr)
                        if not ok then
                            vim.notify("fluxtags cfg: " .. key .. ": " .. tostring(err), vim.log.levels.WARN)
                        end
                    end
                    search_from = e + 1
                end
            end
        end,
    })

    --- Custom extmark logic: the args pattern is wider than base_pattern, so we
    --- extend the highlight to cover the parenthesised argument as well.
    --- @param is_disabled? fun(lnum: number, col: number): boolean
    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority    = self.priority or 1100
        local open        = cfg.open or "$$$"
        local conceal_char = cfg.conceal_open or open:sub(1, 1)
        local search_from = 1

        while true do
            local s, e = line:find(pattern or base_pattern, search_from)
            if not s then break end

            local prefix_start, prefix_text = prefix_util.find_prefix(line, s, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open

            if is_disabled and is_disabled(lnum, col0) then
                search_from = e + 1
            else
                -- Conceal `$$$` to a single `$`.
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                    end_col  = col0 + open_len,
                    conceal  = conceal_char,
                    hl_group = self.hl_group,
                    priority = priority,
                })

                -- Extend highlight to include the `(value)` argument when present.
                local highlight_end = e
                if not pattern then
                    local args = line:sub(e + 1):match("^%b()")
                    if args then highlight_end = e + #args end
                end

                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + open_len, {
                    end_col  = highlight_end,
                    hl_group = self.hl_group,
                    priority = priority,
                })

                search_from = e + 1
            end
        end
    end

    --- Scan all lines for cfg tags; emit error extmarks and diagnostics for
    --- unknown directive keys.
    --- @param is_disabled? fun(lnum: number, col: number): boolean
    function kind:apply_diagnostics(bufnr, lines, is_disabled)
        local open     = cfg.open or "$$$"
        local priority = (self.priority or 1100) + 10
        local diags    = {}

        for lnum0, line in ipairs(lines) do
            local search_from = 1
            while true do
                local s, e, key = line:find(pattern or base_pattern, search_from)
                if not s then break end

                local prefix_start, prefix_text = prefix_util.find_prefix(line, s, prefix_patterns)
                local col0 = prefix_start - 1
                local open_len = #prefix_text + #open
                if is_disabled and is_disabled(lnum0 - 1, col0) then
                    search_from = e + 1
                else
                    if not directive_handlers[key] then
                        local key_col0  = col0 + open_len
                        local key_end   = key_col0 + #key
                        local arg_end   = e
                        if not pattern then
                            local args = line:sub(e + 1):match("^%b()")
                            if args then arg_end = e + #args end
                        end

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

                    search_from = e + 1
                end
            end
        end

        fluxtags.utils.set_diagnostics(bufnr, cfg_diag_ns, diags)
    end

    --- Get disabled intervals for a specific directive (e.g. "fluxtags_hl")
    --- Returns an array of { start_lnum, start_col, end_lnum, end_col }
    function kind:get_disabled_intervals(lines, directive)
        local intervals = {}
        local is_off = false
        local start_pos = nil

        local search_pattern = pattern or base_pattern

        for lnum0, line in ipairs(lines) do
            local search_from = 1
            while true do
                local s, e, key = line:find(search_pattern, search_from)
                if not s then break end

                if key == directive then
                    local value = ""
                    local tag_end = e
                    if not pattern then
                        local args = line:sub(e + 1):match("^%b()")
                        if args then
                            value = args:sub(2, -2)
                            tag_end = e + #args
                        end
                    end

                    if value == "off" and not is_off then
                        is_off = true
                        start_pos = { lnum0 - 1, tag_end }
                    elseif value == "on" and is_off then
                        is_off = false
                        table.insert(intervals, { start_pos[1], start_pos[2], lnum0 - 1, s - 1 })
                        start_pos = nil
                    end
                end
                search_from = e + 1
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
