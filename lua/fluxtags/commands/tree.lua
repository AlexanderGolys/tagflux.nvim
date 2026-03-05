local M = {}

---@param load_tagfile fun(kind_name:string):table
---@param output_file? string
function M.generate(load_tagfile, output_file)
    local marks = load_tagfile("mark") or {}
    local ogs = load_tagfile("og") or {}
    local cwd_prefix = vim.loop.cwd() .. "/"

    local function relpath(path)
        return path:gsub("^" .. cwd_prefix, "")
    end

    local lines = {
        "# Fluxtags Project Tree",
        "",
        "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "",
    }

    if next(marks) then
        table.insert(lines, "## Marks (@@@name)")
        table.insert(lines, "")
        local sorted_marks = {}
        for name, entries in pairs(marks) do table.insert(sorted_marks, { name = name, entry = entries[1] }) end
        table.sort(sorted_marks, function(a, b) return a.name < b.name end)
        for _, item in ipairs(sorted_marks) do
            table.insert(lines, ("- `@@@%s` — %s:%d"):format(item.name, relpath(item.entry.file), item.entry.lnum))
        end
        table.insert(lines, "")
    end

    if next(ogs) then
        table.insert(lines, "## Topics (@##name)")
        table.insert(lines, "")
        local sorted_ogs = {}
        for name, entries in pairs(ogs) do table.insert(sorted_ogs, { name = name, entries = entries }) end
        table.sort(sorted_ogs, function(a, b) return a.name < b.name end)

        for _, item in ipairs(sorted_ogs) do
            table.insert(lines, ("### @##%s (%d occurrences)"):format(item.name, #item.entries))
            for _, entry in ipairs(item.entries) do
                table.insert(lines, ("  - %s:%d"):format(relpath(entry.file), entry.lnum))
            end
            table.insert(lines, "")
        end
    end

    if output_file then
        vim.fn.writefile(lines, output_file)
        vim.notify(("Project tree written to %s (%d lines)"):format(output_file, #lines), vim.log.levels.INFO)
    else
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end
end

return M
