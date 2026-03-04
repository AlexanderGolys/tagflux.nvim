local M = {}

local function assert_eq(expected, actual, msg)
    if expected ~= actual then
        error(string.format("%s: expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
    end
end

local function assert_deep_eq(expected, actual, msg)
    if not vim.deep_equal(expected, actual) then
        error(string.format("%s:\nExpected: %s\nActual: %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
    end
end

function M.run()
    local fluxtags = require("fluxtags")
    local tag_kind = require("tag_kind")
    
    local test_kind = tag_kind.new({
        name = "test_kind",
        pattern = "###([%w_]+)",
        save_to_tagfile = true,
        tagfile = vim.fn.tempname() .. ".tags"
    })
    
    fluxtags.setup({ kinds = { test_kind = { priority = 100 } } })
    fluxtags.register_kind(test_kind)
    
    local lines = {
        "line 1 ###test1",
        "line 2",
        "###test2 line 3",
        "line 4"
    }

    -- Test 1: collect_tags without disabled intervals
    local filepath = "/tmp/test.txt"
    local tags = test_kind:collect_tags(filepath, lines)
    assert_eq(2, #tags, "Should find 2 tags")
    assert_eq("test1", tags[1].name)
    assert_eq(1, tags[1].lnum)
    assert_eq("test2", tags[2].name)
    assert_eq(3, tags[2].lnum)

    -- Test 2: collect_tags with disabled intervals
    -- Let's pretend ###test1 is disabled
    local is_disabled = function(lnum, col)
        return lnum == 0 -- line 1
    end
    
    local disabled_tags = test_kind:collect_tags(filepath, lines, is_disabled)
    assert_eq(1, #disabled_tags, "Should find 1 tag when line 1 is disabled")
    assert_eq("test2", disabled_tags[1].name)

    -- Test 3: applying extmarks
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local ns = vim.api.nvim_create_namespace("test_ns")
    
    test_kind:apply_extmarks(bufnr, 0, lines[1], ns)
    test_kind:apply_extmarks(bufnr, 2, lines[3], ns)
    
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert_eq(2, #extmarks, "Should have applied 2 extmarks")

    -- Apply with disabled
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    test_kind:apply_extmarks(bufnr, 0, lines[1], ns, is_disabled)
    test_kind:apply_extmarks(bufnr, 2, lines[3], ns, is_disabled)
    
    extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert_eq(1, #extmarks, "Should have applied 1 extmark with is_disabled")

    print("Core tests passed!")
end

M.run()
