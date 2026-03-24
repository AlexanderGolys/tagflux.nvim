--- @brief [[
--- Kind registration registry for fluxtags built-ins.
---
--- Keeps construction of built-in kind modules in one place and provides a small
--- class-backed structure for registering all available kinds during setup.
--- /@@fts.core.app_new
--- @brief ]]

local M = {}

---@class TagKindEntry
---@field name string
---@field module string
---@field optional boolean
---@field config_key string
local KindEntry = {}
KindEntry.__index = KindEntry

---@param name string
---@param module string
---@param opts? table
---@return TagKindEntry
function KindEntry.new(name, module, opts)
    local entry = {
        name = name,
        module = module,
        optional = (opts and opts.optional) or false,
        config_key = (opts and opts.config_key) or name,
    }
    return setmetatable(entry, KindEntry)
end

function KindEntry:register(fluxtags)
    if not self.module then
        vim.notify("fluxtags: invalid kind module for " .. self.name, vim.log.levels.ERROR)
        return false
    end

    local ok, kind_module = pcall(require, self.module)
    if not ok then
        if self.optional then
            return false
        end
        vim.notify("fluxtags: failed to load kind module '" .. self.module .. "'", vim.log.levels.ERROR)
        return false
    end

    if kind_module == nil or kind_module.register == nil then
        vim.notify("fluxtags: kind module '" .. self.module .. "' does not expose register()", vim.log.levels.ERROR)
        return false
    end

    kind_module.register(fluxtags)
    return true
end

---@class TagKindRegistry
---@field entries TagKindEntry[]
local KindRegistry = {}
KindRegistry.__index = KindRegistry

---@param entries TagKindEntry[]
---@return TagKindRegistry
function KindRegistry.new(entries)
    local self = setmetatable({}, KindRegistry)
    self.entries = entries or {}
    return self
end

---@param name string
---@param module string
---@param opts? table
---@return TagKindRegistry
function KindRegistry:add(name, module, opts)
    table.insert(self.entries, KindEntry.new(name, module, opts))
    return self
end

---@param fluxtags table
function KindRegistry:register_all(fluxtags)
    for _, entry in ipairs(self.entries) do
        entry:register(fluxtags)
    end
end

--- Build default built-in kind registry in explicit order.
---@return TagKindRegistry
-- @@@fluxtags.registry.builtins
function M.builtins()
    return KindRegistry.new({
        KindEntry.new("mark", "tagkinds.mark"),
        KindEntry.new("ref", "tagkinds.ref"),
        KindEntry.new("refog", "tagkinds.refog"),
        KindEntry.new("bib", "tagkinds.bib"),
        KindEntry.new("og", "tagkinds.og"),
        KindEntry.new("hl", "tagkinds.hl"),
        KindEntry.new("cfg", "tagkinds.cfg"),
    })
end

M.Entry = KindEntry
M.Registry = KindRegistry

return M
