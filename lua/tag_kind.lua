--- @brief [[
---     Base class for all tag kinds in fluxtags.
---
---     A TagKind defines how a particular tag syntax is matched, highlighted,
---     concealed, and navigated. Each tag kind (mark, ref, bib, og, hl, cfg)
---     is created via `tag_kind.new()` or the fluent `tag_kind.builder()` API.
--- @brief ]]

local M = {}
local Extmark = require("fluxtags.extmark")

--- @class ConcealSpec
--- @field offset number Byte offset from the start of the full match
--- @field length number Number of bytes to cover with this extmark
--- @field char? string Conceal character (nil = no conceal, just highlight)
--- @field hl_group? string Override highlight group for this segment
--- @field priority? number Optional priority override for this segment

--- @class TagKind
--- @field name string Unique identifier used as the kind key and in tagfile names
--- @field pattern string Lua pattern; must capture the tag name as the first capture group
--- @field hl_group string Highlight group applied to tag text
--- @field conceal_pattern? fun(name: string): ConcealSpec[] Returns per-segment extmark specs
--- @field save_to_tagfile boolean True when found tags should be persisted to disk
--- @field tagfile? string Absolute path to the tagfile (nil when save_to_tagfile is false)
--- @field priority number Extmark priority; higher wins on overlapping ranges
--- @field on_jump fun(name: string, ctx: table): boolean Called on Ctrl-]; return true to suppress fallback
--- @field on_enter? fun(bufnr: number, lines: string[]) Called once when a buffer is first initialized
--- @field extract_name? fun(capture: string): string Transforms the raw pattern capture into the canonical tag name
--- @field is_valid? fun(name: string): boolean Optional guard; extmarks are skipped when this returns false
--- @field apply_diagnostics? fun(self: TagKind, bufnr: number, lines: string[], is_disabled?: fun(lnum: number, col: number): boolean)

--- @alias TagKindName string
--- @alias TagKindPattern string

---@class TagKindOptions
--- @field name TagKindName
--- @field pattern TagKindPattern
--- @field hl_group? string
--- @field conceal_pattern? fun(name: string): ConcealSpec[]
--- @field save_to_tagfile? boolean
--- @field tagfile? string
--- @field priority? number
--- @field on_jump? fun(name: string, ctx: table): boolean
--- @field on_enter? fun(bufnr: number, lines: string[])
--- @field extract_name? fun(capture: string): string
--- @field is_valid? fun(name: string): boolean

---@class TagKindMethods
---@field apply_extmarks? fun(self: TagKind, bufnr: number, lnum: number, line: string, ns: number, is_disabled?: fun(lnum: number, col: number): boolean)
---@field apply_diagnostics? fun(self: TagKind, bufnr: number, lines: string[], is_disabled?: fun(lnum: number, col: number): boolean)
---@field collect_tags? fun(self: TagKind, filepath: string, lines: string[], is_disabled?: fun(lnum: number, col: number): boolean): table[]
---@field find_at_cursor? fun(self: TagKind, line: string, col: number): string?, number?, number?
---@field get_disabled_intervals? fun(self: TagKind, lines: string[], directive_name: string): table[]

--- @class TagKindBuilder
--- @field _opts TagKindOptions

local TagKind = {}
TagKind.__index = TagKind

local Builder = {}
Builder.__index = Builder

local DEFAULT_PRIORITY = 1100
local DEFAULT_TAGFILE_FORMAT = "/fluxtags.%s.tags"

local OPTION_KEYS = {
    name = true,
    pattern = true,
    hl_group = true,
    conceal_pattern = true,
    save_to_tagfile = true,
    tagfile = true,
    priority = true,
    on_jump = true,
    on_enter = true,
    extract_name = true,
    is_valid = true,
    apply_extmarks = true,
    apply_diagnostics = true,
    collect_tags = true,
    find_at_cursor = true,
    get_disabled_intervals = true,
}

local OPTION_TYPES = {
    name = "string",
    pattern = "string",
    hl_group = "string",
    conceal_pattern = "function",
    save_to_tagfile = "boolean",
    tagfile = "string",
    priority = "number",
    on_jump = "function",
    on_enter = "function",
    extract_name = "function",
    is_valid = "function",
    apply_extmarks = "function",
    apply_diagnostics = "function",
    collect_tags = "function",
    find_at_cursor = "function",
    get_disabled_intervals = "function",
}

---@param value any
---@param label string
---@return table
local function assert_table(value, label)
    if type(value) ~= "table" then
        error((label or "value") .. " must be a table")
    end
    return value
end

---@param value any
---@param label string
---@param expected string
local function assert_type(value, label, expected)
    if value ~= nil and type(value) ~= expected then
        error(("%s must be a %s"):format(label, expected))
    end
end

---@param name TagKindName
---@return TagKindName
local function normalize_name(name)
    if type(name) ~= "string" or name == "" then
        error("TagKind requires name")
    end
    return name
end

---@param pattern TagKindPattern
---@return TagKindPattern
local function normalize_pattern(pattern)
    if type(pattern) ~= "string" or pattern == "" then
        error("TagKind requires pattern")
    end
    return pattern
end

---@param opts TagKindOptions
---@return TagKindOptions
local function sanitize_opts(opts)
    assert_table(opts, "TagKind options")
    local normalized = {}

    for key, value in pairs(opts) do
        if not OPTION_KEYS[key] then
            error(("unknown TagKind option: %s"):format(key))
        end
        if OPTION_TYPES[key] then
            if key == "tagfile" and value == "" then
                value = nil
            end
            assert_type(value, ("TagKind option " .. key), OPTION_TYPES[key])
        end
        normalized[key] = value
    end

    normalized.name = normalize_name(normalized.name)
    normalized.pattern = normalize_pattern(normalized.pattern)
    normalized.save_to_tagfile = normalized.save_to_tagfile ~= false
    if normalized.priority ~= nil and normalized.priority < 0 then
        error("TagKind priority must be >= 0")
    end

    return normalized
end

---@param key string
---@param value any
---@return TagKindBuilder
function Builder:with(key, value)
    if not OPTION_KEYS[key] then
        error(("unknown TagKind option: %s"):format(key))
    end
    if OPTION_TYPES[key] then
        assert_type(value, ("TagKind option " .. key), OPTION_TYPES[key])
        if key == "tagfile" and value == "" then
            value = nil
        end
    end
    self._opts[key] = value
    return self
end

---@param name TagKindName
---@return TagKindBuilder
function Builder:with_name(name)
    return self:with("name", normalize_name(name))
end

---@param pattern TagKindPattern
---@return TagKindBuilder
function Builder:with_pattern(pattern)
    return self:with("pattern", normalize_pattern(pattern))
end

---@param hl_group string
---@return TagKindBuilder
function Builder:with_hl_group(hl_group)
    return self:with("hl_group", hl_group)
end

---@param priority number|nil
---@return TagKindBuilder
function Builder:with_priority(priority)
    if priority ~= nil and type(priority) ~= "number" then
        error("TagKind priority must be a number")
    end
    if priority ~= nil and priority < 0 then
        error("TagKind priority must be >= 0")
    end
    return self:with("priority", priority)
end

---@param tagfile string|nil
---@return TagKindBuilder
function Builder:with_tagfile(tagfile)
    return self:with("tagfile", tagfile)
end

---@param enabled boolean|nil
---@return TagKindBuilder
function Builder:save_to_tagfile(enabled)
    if enabled ~= nil and type(enabled) ~= "boolean" then
        error("TagKind save_to_tagfile must be boolean")
    end
    return self:with("save_to_tagfile", enabled)
end

---@param fn fun(capture: string): string
---@return TagKindBuilder
function Builder:with_extract_name(fn)
    return self:with("extract_name", fn)
end

---@param fn fun(name: string, ctx: table): boolean
---@return TagKindBuilder
function Builder:with_on_jump(fn)
    return self:with("on_jump", fn)
end

---@param fn fun(bufnr: number, lines: string[])
---@return TagKindBuilder
function Builder:with_on_enter(fn)
    return self:with("on_enter", fn)
end

---@param fn fun(name: string): boolean
---@return TagKindBuilder
function Builder:with_is_valid(fn)
    return self:with("is_valid", fn)
end

---@param fn fun(name: string): ConcealSpec[]
---@return TagKindBuilder
function Builder:with_conceal_pattern(fn)
    return self:with("conceal_pattern", fn)
end

---@param methods TagKindMethods
---@return TagKindBuilder
function Builder:with_methods(methods)
    assert_table(methods, "methods")
    for key, value in pairs(methods) do
        self:with(key, value)
    end
    return self
end

---@return TagKind
function Builder:build()
    return M.new(self._opts)
end

---@param opts TagKindOptions
---@return TagKindBuilder
function Builder.new(opts)
    local raw = sanitize_opts(assert_table(opts, "TagKindBuilder opts"))
    return setmetatable({ _opts = raw }, Builder)
end

--- Create a fluent `TagKindBuilder`.
---
---@param opts TagKindOptions
---@return TagKindBuilder
function M.builder(opts)
    return Builder.new(opts)
end

--- Construct a new TagKind with the given options.
---
--- Required fields: `name`, `pattern`.
--- All callbacks default to no-ops when omitted.
--- `tagfile` is derived from `name` when `save_to_tagfile` is true and no explicit path is given.
---
---@param opts TagKindOptions|TagKindBuilder
---@return TagKind
function M.new(opts)
    if getmetatable(opts) == Builder then
        return opts:build()
    end

    local normalized = sanitize_opts(opts)
    local self = setmetatable({}, TagKind)
    self.name = normalized.name
    self.pattern = normalized.pattern
    self.hl_group = normalized.hl_group or ("FluxTag" .. normalized.name:gsub("^%l", string.upper))
    self.conceal_pattern = normalized.conceal_pattern
    self.save_to_tagfile = normalized.save_to_tagfile
    self.priority = normalized.priority or DEFAULT_PRIORITY
    self.on_jump = normalized.on_jump or function() return false end
    self.on_enter = normalized.on_enter
    self.extract_name = normalized.extract_name or function(capture) return capture end
    self.is_valid = normalized.is_valid

    if self.save_to_tagfile then
        self.tagfile = normalized.tagfile
            or (vim.fn.stdpath("data") .. DEFAULT_TAGFILE_FORMAT:format(self.name))
    end

    self.apply_extmarks = normalized.apply_extmarks or TagKind.apply_extmarks
    self.apply_diagnostics = normalized.apply_diagnostics or TagKind.apply_diagnostics
    self.collect_tags = normalized.collect_tags or TagKind.collect_tags
    self.find_at_cursor = normalized.find_at_cursor or TagKind.find_at_cursor
    self.get_disabled_intervals = normalized.get_disabled_intervals or TagKind.get_disabled_intervals

    return self
end

--- Return the tag name and byte range of the first tag that overlaps the cursor column.
---
--- Both `col` and the returned columns are 1-indexed to match `vim.fn.col(".")`.
--- Returns nil when no tag covers the cursor.
---
---@param line string Full line text
---@param col number Cursor column (1-indexed)
---@return string? name Canonical tag name
---@return number? s Match start column (1-indexed)
---@return number? e Match end column (1-indexed)
function TagKind:find_at_cursor(line, col)
    local search_from = 1
    while true do
        local s, e, capture = line:find(self.pattern, search_from)
        if not s then
            return nil
        end
        if col >= s and col <= e then
            return self.extract_name(capture), s, e
        end
        search_from = e + 1
    end
end

--- Place extmarks on every tag occurrence in a single line.
---
--- When the kind provides `conceal_pattern`, each returned ConcealSpec is applied
--- as a separate extmark (allowing mixed conceal + highlight segments).
--- Otherwise a single plain-highlight extmark covers the captured name.
---
--- `lnum` is 0-indexed to match the nvim_buf_set_extmark API.
---
---@param bufnr number
---@param lnum number Line index (0-indexed)
---@param line string Full line text
---@param ns number Extmark namespace id
---@param is_disabled? fun(lnum: number, col: number): boolean
function TagKind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
    for match_start, capture in line:gmatch("()" .. self.pattern) do
        local col0 = match_start - 1
        local is_disabled_tag = is_disabled and is_disabled(lnum, col0)
        local is_invalid_tag = self.is_valid and not self.is_valid(capture)

        if not is_disabled_tag and not is_invalid_tag then
            if self.conceal_pattern then
                for _, spec in ipairs(self.conceal_pattern(capture)) do
                    local seg_start = col0 + spec.offset
                    local seg_end = col0 + spec.offset + spec.length
                    if seg_start >= 0 and seg_end >= seg_start then
                        local extmark_opts = {
                            end_col = seg_end,
                            hl_group = spec.hl_group or self.hl_group,
                            priority = spec.priority or self.priority,
                        }
                        if spec.char ~= nil then
                            extmark_opts.conceal = spec.char
                        end
                        Extmark.place(bufnr, ns, lnum, seg_start, extmark_opts)
                    end
                end
            else
                local prefix_len = #(self.pattern:match("^(.-)%(") or "")
                local seg_end = col0 + prefix_len + #capture
                if seg_end >= col0 then
                    Extmark.place(bufnr, ns, lnum, col0, {
                        end_col = seg_end,
                        hl_group = self.hl_group,
                        priority = self.priority,
                    })
                end
            end
        end
    end
end

--- Scan file lines and return every tag found, ready to be written to a tagfile.
---
--- Returns an empty table when `save_to_tagfile` is false — kinds that do not
--- persist tags (bib, hl, cfg, ref) should never appear in tagfiles.
---
---@param filepath string Absolute path of the file being scanned
---@param lines string[] All lines of the file
---@return table[] tags Each entry: `{ name, file, lnum }`
---@param is_disabled? fun(lnum: number, col: number): boolean
function TagKind:collect_tags(filepath, lines, is_disabled)
    if not self.save_to_tagfile then
        return {}
    end

    local tags = {}
    for lnum, line in ipairs(lines) do
        for match_start, capture in line:gmatch("()" .. self.pattern) do
            local col0 = match_start - 1
            local is_disabled_tag = is_disabled and is_disabled(lnum - 1, col0)

            if not is_disabled_tag then
                table.insert(tags, {
                    name = self.extract_name(capture),
                    file = filepath,
                    lnum = lnum,
                })
            end
        end
    end
    return tags
end

--- Default parse-time diagnostics extension point (no-op for kinds that do not use it).
---@param bufnr number
---@param lines string[]
---@param is_disabled? fun(lnum: number, col: number): boolean
function TagKind:apply_diagnostics(bufnr, lines, is_disabled) end

--- Default disabled-interval parser extension point (kinds opt-in).
---@param lines string[]
---@param directive_name string
---@return table[]
function TagKind:get_disabled_intervals(lines, directive_name)
    return {}
end

M.TagKind = TagKind
M.Builder = Builder
return M
