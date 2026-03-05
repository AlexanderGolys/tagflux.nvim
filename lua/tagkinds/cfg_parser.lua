local M = {}

---@class CfgDirective
---@field s number
---@field e number
---@field key string
---@field value string
---@field tag_end number

---@param line string
---@param search_pattern string
---@param parse_args boolean
---@return CfgDirective[]
function M.parse_line(line, search_pattern, parse_args)
    local directives = {}
    local search_from = 1

    while true do
        local s, e, key = line:find(search_pattern, search_from)
        if not s then break end

        local value, tag_end = "", e
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

---@param lines string[]
---@param parse_line fun(line:string): CfgDirective[]
---@param directive_name string
---@return table[]
function M.disabled_intervals(lines, parse_line, directive_name)
    local intervals, is_off, start_pos = {}, false, nil

    for lnum0, line in ipairs(lines) do
        for _, item in ipairs(parse_line(line)) do
            if item.key == directive_name then
                if item.value == "off" and not is_off then
                    is_off = true
                    start_pos = { lnum0 - 1, item.tag_end }
                elseif item.value == "on" and is_off then
                    is_off = false
                    table.insert(intervals, { start_pos[1], start_pos[2], lnum0 - 1, item.s - 1 })
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

return M
