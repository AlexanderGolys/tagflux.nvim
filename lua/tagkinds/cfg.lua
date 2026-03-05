--- @brief [[
--- cfg — buffer configuration directives.
--- @brief ]]

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")
local parser = require("tagkinds.cfg_parser")
local registry = require("tagkinds.cfg_registry")
local diag = require("tagkinds.diagnostics")

local M = {}

---@return string[]
function M.known_keys()
    return registry.known_keys()
end

---@return {key: string, description: string}[]
function M.get_directives_info()
    return registry.info()
end

---@param key string
---@param handler fun(value: string, bufnr: number)
---@param description? string
function M.register_handler(key, handler, description)
    registry.register(key, handler, description)
end

---@param fluxtags table
function M.register(fluxtags)
    local cfg, opts = kind_common.resolve_kind_config(
        fluxtags,
        "cfg",
        { name = "cfg", hl_group = "FluxTagCfg", open = "$$$" },
        prefix_util.default_comment_prefix_patterns
    )

    local base_pattern = "%$%$%$([%w_]+)"
    local pattern = cfg.pattern
    local search_pattern = pattern or base_pattern
    local parse_args = not pattern
    local prefix_patterns = opts.comment_prefix_patterns
    local open = opts.open
    local kind_name = opts.name
    local cfg_diag_ns = fluxtags.utils.make_diag_ns("cfg")

    ---@param line string
    ---@return CfgDirective[]
    local function parse_line(line)
        return parser.parse_line(line, search_pattern, parse_args)
    end

    local kind = tag_kind.new({
        name = kind_name,
        pattern = pattern or base_pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
        save_to_tagfile = false,
        extract_name = function(match) return match end,
        on_jump = function() return false end,
        on_enter = function(bufnr, lines)
            for _, line in ipairs(lines) do
                for _, item in ipairs(parse_line(line)) do
                    local ok, err = registry.exec(item.key, item.value, bufnr)
                    if not ok and err and err ~= "unknown handler" then
                        vim.notify("fluxtags cfg: " .. item.key .. ": " .. err, vim.log.levels.WARN)
                    end
                end
            end
        end,
    })

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100
        local conceal_char = cfg.conceal_open or open:sub(1, 1)

        for _, item in ipairs(parse_line(line)) do
            local prefix_start, prefix_text = prefix_util.find_prefix(line, item.s, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open

            if not (is_disabled and is_disabled(lnum, col0)) then
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                    end_col = col0 + open_len,
                    conceal = conceal_char,
                    hl_group = self.hl_group,
                    priority = priority,
                })
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + open_len, {
                    end_col = item.tag_end,
                    hl_group = self.hl_group,
                    priority = priority,
                })
            end
        end
    end

    function kind:apply_diagnostics(bufnr, lines, is_disabled)
        local diags = {}
        local priority = (self.priority or 1100) + 10

        for lnum0, line in ipairs(lines) do
            for _, item in ipairs(parse_line(line)) do
                local prefix_start, prefix_text = prefix_util.find_prefix(line, item.s, prefix_patterns)
                local col0 = prefix_start - 1
                if not (is_disabled and is_disabled(lnum0 - 1, col0)) and not registry.has(item.key) then
                    local key_col0 = col0 + #prefix_text + #open
                    local key_end = key_col0 + #item.key
                    diag.error_extmark(bufnr, fluxtags.utils.ns, lnum0 - 1, col0, item.tag_end, priority)
                    diag.push(
                        diags,
                        bufnr,
                        lnum0 - 1,
                        key_col0,
                        key_end,
                        vim.diagnostic.severity.ERROR,
                        "fluxtags.cfg",
                        "Unknown cfg directive: " .. item.key
                    )
                end
            end
        end

        diag.publish(bufnr, cfg_diag_ns, diags, fluxtags.utils.set_diagnostics)
    end

    function kind:get_disabled_intervals(lines, directive_name)
        return parser.disabled_intervals(lines, parse_line, directive_name)
    end

    fluxtags.register_kind(kind)
end

return M
