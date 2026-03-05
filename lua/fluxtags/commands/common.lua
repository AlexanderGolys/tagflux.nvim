local M = {}

local kind_help = {
    mark = { syntax = "-- @@@<name>", info = "Named anchors persisted to tagfiles; refs jump to these." },
    ref = { syntax = "-- |||<name>||| or @<base>.<subtag>", info = "References to marks; resolves base name on Ctrl-]." },
    refog = { syntax = "#|#||<name>||", info = "Reference-only OG jump tag; does not create saved hashtag entries." },
    bib = { syntax = "-- ///<target>", info = "External links (URL/file/help topic); opens target on Ctrl-]." },
    og = { syntax = "@##<name>", info = "Topic hashtags across files; Ctrl-] opens a picker of occurrences." },
    hl = { syntax = "&&&<HlGroup>&&&<text>&&&", info = "Inline styled text using any Neovim highlight group." },
    cfg = { syntax = "$$$<key>(<value>)", info = "Buffer-local config directives applied on enter." },
}

local preview_kinds = { "mark", "ref", "refog", "bib", "og", "hl", "cfg" }

---@param kind string
---@return boolean
function M.notify_kind_help(kind)
    local item = kind_help[kind]
    if not item then return false end
    vim.notify(("[%s] %s\n%s"):format(kind, item.syntax, item.info), vim.log.levels.INFO)
    return true
end

---@return string[]
function M.preview_kinds()
    return preview_kinds
end

---@return table<string, {syntax:string, info:string}>
function M.kind_help()
    return kind_help
end

---@param kind string
---@return string
function M.kind_symbol(kind)
    local symbols = { mark = "@", ref = "&", refog = "#", og = "#", cfg = "$", hl = "%", bib = "/" }
    return symbols[kind] or "?"
end

return M
