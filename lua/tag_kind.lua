--- @brief [[
---     TagKind class for defining tag types in fluxtags
---     
---     Each TagKind instance represents a type of tag (marks, ref, bib, etc.)
---     and defines its behavior: pattern matching, highlighting, jumping, etc.
--- @brief ]]

local M = {}

--- @class TagKind
--- @field name string Unique identifier for this tag kind
--- @field pattern string Lua pattern to find tags in text
--- @field hl_group string Highlight group for this tag kind
--- @field conceal_pattern? function(match: string) -> table[] Extmark conceal definitions
--- @field save_to_tagfile boolean Whether tags should be saved to tagfile
--- @field tagfile? string Path to tagfile (nil if save_to_tagfile = false)
--- @field on_jump function(tag_name: string, context: table) -> boolean Jump handler
--- @field on_enter? function(bufnr: number, lines: string[]) Buffer enter handler
--- @field extract_name? function(match: string) -> string Extract tag name from match
local TagKind = {}
TagKind.__index = TagKind

--- Create a new TagKind
--- @param opts table Configuration table
--- @return TagKind
function M.new(opts)
    local self = setmetatable({}, TagKind)
    
    self.name = opts.name or error("TagKind requires name")
    self.pattern = opts.pattern or error("TagKind requires pattern")
    self.hl_group = opts.hl_group or ("FluxTag" .. self.name:gsub("^%l", string.upper))
    self.conceal_pattern = opts.conceal_pattern
    self.save_to_tagfile = opts.save_to_tagfile ~= false
    self.priority = opts.priority or 1100
    self.on_jump = opts.on_jump or function() return false end
    self.on_enter = opts.on_enter
    self.extract_name = opts.extract_name or function(match) return match end
    
    if self.save_to_tagfile then
        self.tagfile = opts.tagfile or (vim.fn.stdpath("data") .. "/fluxtags." .. self.name .. ".tags")
    end
    
    return self
end

--- Find tag at cursor position
--- @param line string Line content
--- @param col number Cursor column (1-indexed)
--- @return string? tag_name Tag name if found
--- @return number? start_col Start column (1-indexed)
--- @return number? end_col End column (1-indexed)
function TagKind:find_at_cursor(line, col)
    local start_pos = 1
    while true do
        local s, e, capture = line:find(self.pattern, start_pos)
        if not s then return nil end
        if col >= s and col <= e then
            local name = self.extract_name(capture)
            return name, s, e
        end
        start_pos = e + 1
    end
end

--- Apply extmarks for highlighting and concealing
--- @param bufnr number Buffer number
--- @param lnum number Line number (0-indexed)
--- @param line string Line content
--- @param ns number Namespace ID
function TagKind:apply_extmarks(bufnr, lnum, line, ns)
    for start_col, capture in line:gmatch("()" .. self.pattern) do
        local col0 = start_col - 1
        local priority = self.priority
        
        if self.conceal_pattern then
            local conceals = self.conceal_pattern(capture)
            for _, conceal in ipairs(conceals) do
                local opts = {
                    end_col = col0 + conceal.offset + conceal.length,
                    hl_group = conceal.hl_group,
                    priority = conceal.priority or priority,
                }
                if conceal.char ~= nil then
                    opts.conceal = conceal.char
                end
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + conceal.offset, opts)
            end
        else
            local match_len = #capture + (self.pattern:match("^(.-)%(") or ""):len()
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                end_col = col0 + match_len,
                hl_group = self.hl_group,
                priority = priority,
            })
        end
    end
end

--- Collect tags from file lines
--- @param filepath string File path
--- @param lines string[] File lines
--- @return table[] tags List of {name, file, lnum}
function TagKind:collect_tags(filepath, lines)
    if not self.save_to_tagfile then
        return {}
    end
    
    local tags = {}
    for lnum, line in ipairs(lines) do
        for capture in line:gmatch(self.pattern) do
            local name = self.extract_name(capture)
            table.insert(tags, {
                name = name,
                file = filepath,
                lnum = lnum,
            })
        end
    end
    return tags
end

M.TagKind = TagKind
return M
