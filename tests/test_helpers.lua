--- Shared test utilities for fluxtags tests
local M = {}

--- Assert that two values are equal
---@param expected any
---@param actual any
---@param msg string|nil
function M.assert_eq(expected, actual, msg)
    if expected ~= actual then
        error(string.format("%s: expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
    end
end

--- Assert deep equality (tables, nested structures)
---@param expected any
---@param actual any
---@param msg string|nil
function M.assert_deep_eq(expected, actual, msg)
    if not vim.deep_equal(expected, actual) then
        error(string.format("%s:\nExpected: %s\nActual: %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
    end
end

--- Assert a condition is true
---@param condition boolean
---@param msg string|nil
function M.assert_true(condition, msg)
    if not condition then
        error(msg or "Expected true, got false")
    end
end

--- Assert a condition is false
---@param condition boolean
---@param msg string|nil
function M.assert_false(condition, msg)
    if condition then
        error(msg or "Expected false, got true")
    end
end

--- Assert that a value is nil
---@param value any
---@param msg string|nil
function M.assert_nil(value, msg)
    if value ~= nil then
        error(string.format("%s: expected nil, got %s", msg or "Assertion failed", vim.inspect(value)))
    end
end

--- Assert that a value is not nil
---@param value any
---@param msg string|nil
function M.assert_not_nil(value, msg)
    if value == nil then
        error(msg or "Expected non-nil value, got nil")
    end
end

--- Assert that table contains expected element
---@param tbl table
---@param expected any
---@param msg string|nil
function M.assert_contains(tbl, expected, msg)
    for _, v in ipairs(tbl) do
        if vim.deep_equal(v, expected) then
            return
        end
    end
    error(string.format("%s: table does not contain %s", msg or "Assertion failed", vim.inspect(expected)))
end

--- Assert that table length matches
---@param tbl table
---@param expected_len integer
---@param msg string|nil
function M.assert_len(tbl, expected_len, msg)
    if #tbl ~= expected_len then
        error(string.format("%s: expected length %d, got %d", msg or "Assertion failed", expected_len, #tbl))
    end
end

--- Create a temporary buffer with lines
---@param lines string[]
---@return integer bufnr
function M.create_test_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

--- Clean up a test buffer
---@param bufnr integer
function M.cleanup_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

--- Create a temporary directory
---@return string tmpdir
function M.create_tmpdir()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    return tmpdir
end

--- Clean up a temporary directory
---@param tmpdir string
function M.cleanup_tmpdir(tmpdir)
    if vim.fn.isdirectory(tmpdir) == 1 then
        vim.fn.system("rm -rf " .. tmpdir)
    end
end

return M
