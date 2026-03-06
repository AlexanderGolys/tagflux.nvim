---@class FluxtagsPath
---@field fn table
local Path = {}
Path.__index = Path

---@param fn? table
---@return FluxtagsPath
function Path.new(fn)
    return setmetatable({
        fn = fn or vim.fn,
    }, Path)
end

---@param path string
---@return string
function Path:absolute(path)
    return self.fn.fnamemodify(path, ":p")
end

---@param path string
---@return string
function Path:display_relative(path)
    return self.fn.fnamemodify(path, ":~:.")
end

---@param path string
---@return string
function Path:dirname(path)
    return self.fn.fnamemodify(path, ":h")
end

---@param path string
---@return string
function Path:basename(path)
    return self.fn.fnamemodify(path, ":t")
end

return Path
