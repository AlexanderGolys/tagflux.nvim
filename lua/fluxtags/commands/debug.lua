local M = {}

---@param ns number
---@param tag_kinds table<string, TagKind>
function M.setup(ns, tag_kinds)
    vim.api.nvim_create_user_command("FTagsDebug", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local line = vim.api.nvim_get_current_line()
        local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
        local info = {
            buffer = bufnr,
            conceallevel = vim.opt_local.conceallevel:get(),
            concealcursor = vim.opt_local.concealcursor:get(),
            extmarks = #all_extmarks,
            kinds = {},
        }

        for name, kind in pairs(tag_kinds) do
            local matches = {}
            for m in line:gmatch(kind.pattern) do table.insert(matches, m) end
            table.insert(info.kinds, {
                name = name,
                pattern = kind.pattern,
                hl_group = kind.hl_group,
                hl = kind.hl_group and vim.api.nvim_get_hl(0, { name = kind.hl_group }) or nil,
                priority = kind.priority,
                matches = matches,
            })
        end

        vim.notify(vim.inspect(info), vim.log.levels.INFO)
    end, { desc = "Dump fluxtags debug info for current line" })

    vim.api.nvim_create_user_command("FTagsDebugMarks", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
        vim.notify(vim.inspect(marks), vim.log.levels.INFO)
    end, { desc = "Dump all fluxtags extmarks in current buffer" })

    vim.api.nvim_create_user_command("FTagsDebugAtCursor", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local row = vim.fn.line(".") - 1
        local col = vim.fn.col(".") - 1
        local line_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 }, { details = true })
        local at_cursor = {}

        for _, mark in ipairs(line_marks) do
            local start_col = mark[3]
            local details = mark[4] or {}
            local end_col = details.end_col or start_col
            local end_row = details.end_row or row
            if end_row == row and col >= start_col and col < end_col then
                table.insert(at_cursor, mark)
            end
        end

        vim.notify(vim.inspect({ row = row, col = col, marks = at_cursor }), vim.log.levels.INFO)
    end, { desc = "Dump fluxtags extmarks covering the cursor" })
end

return M
