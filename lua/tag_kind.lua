--- @brief [[
---     Base class for all tag kinds in fluxtags.
---
---     A TagKind defines how a particular tag syntax is matched, highlighted,
---     concealed, and navigated. Each tag kind (mark, ref, bib, og, hl, cfg)
---     is an instance created via `tag_kind.new()` with kind-specific callbacks.
--- @brief ]]

local M = {}

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
---
local TagKind = {}
TagKind.__index = TagKind

--- Construct a new TagKind with the given options.
---
--- Required fields: `name`, `pattern`.
--- All callbacks default to no-ops when omitted.
--- `tagfile` is derived from `name` when `save_to_tagfile` is true and no explicit path is given.
---
--- @param opts table
--- @return TagKind
---
function M.new(opts)
    local self = setmetatable({}, TagKind)
    self.name             = opts.name    or error("TagKind requires name")
    self.pattern          = opts.pattern or error("TagKind requires pattern")
    self.hl_group         = opts.hl_group or ("FluxTag" .. self.name:gsub("^%l", string.upper))
    self.conceal_pattern  = opts.conceal_pattern
    self.save_to_tagfile  = opts.save_to_tagfile ~= false
    self.priority         = opts.priority or 1100
    self.on_jump          = opts.on_jump  or function() return false end
    self.on_enter         = opts.on_enter
    self.extract_name     = opts.extract_name or function(capture) return capture end
    self.is_valid         = opts.is_valid

    if self.save_to_tagfile then
        self.tagfile = opts.tagfile
            or (vim.fn.stdpath("data") .. "/fluxtags." .. self.name .. ".tags")
    end

    return self
end

--- Return the tag name and byte range of the first tag that overlaps the cursor column.
---
--- Both `col` and the returned columns are 1-indexed to match `vim.fn.col(".")`.
--- Returns nil when no tag covers the cursor.
---
--- @param line string Full line text
--- @param col number Cursor column (1-indexed)
--- @return string? name  Canonical tag name
--- @return number? s     Match start column (1-indexed)
--- @return number? e     Match end column (1-indexed)
---
function TagKind:find_at_cursor(line, col)
    local search_from = 1
    while true do
        local s, e, capture = line:find(self.pattern, search_from)
        if not s then return nil end
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
--- @param bufnr number
--- @param lnum number Line index (0-indexed)
--- @param line string Full line text
--- @param ns number Extmark namespace id
--- @param is_disabled? fun(lnum: number, col: number): boolean
---
function TagKind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
    for match_start, capture in line:gmatch("()" .. self.pattern) do
        local col0 = match_start - 1

        -- Skip disabled or invalid tags
        local is_disabled_tag = is_disabled and is_disabled(lnum, col0)
        local is_invalid_tag = self.is_valid and not self.is_valid(capture)

        if not is_disabled_tag and not is_invalid_tag then
            if self.conceal_pattern then
                for _, spec in ipairs(self.conceal_pattern(capture)) do
                    local seg_start = col0 + spec.offset
                    local seg_end   = col0 + spec.offset + spec.length
                    if seg_start >= 0 and seg_end >= seg_start then
                        local extmark_opts = {
                            end_col  = seg_end,
                            hl_group = spec.hl_group or self.hl_group,
                            priority = spec.priority or self.priority,
                        }
                        if spec.char ~= nil then
                            extmark_opts.conceal = spec.char
                        end
                        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, seg_start, extmark_opts)
                    end
                end
            else
                -- No conceal spec: highlight from the start of the match to the end of the capture.
                local prefix_len = #(self.pattern:match("^(.-)%(") or "")
                local seg_end    = col0 + prefix_len + #capture
                if seg_end >= col0 then
                    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                        end_col  = seg_end,
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
--- @param filepath string Absolute path of the file being scanned
--- @param lines string[] All lines of the file
--- @return table[] tags  Each entry: `{ name, file, lnum }`
--- @param is_disabled? fun(lnum: number, col: number): boolean
---
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
                    name  = self.extract_name(capture),
                    file  = filepath,
                    lnum  = lnum,
                })
            end
        end
    end
    return tags
end

M.TagKind = TagKind
return M
