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
    -- We can set up with dummy config to not write to actual user stdpath("data")
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    
    fluxtags.setup({
        kinds = {
            mark = { tagfile = tmpdir .. "/mark.tags" },
            ref = { tagfile = tmpdir .. "/ref.tags" },
        }
    })

    local cfg_kind = fluxtags.tag_kinds.cfg

    -- Test 1: get_disabled_intervals for fluxtags_hl
    local lines = {
        "line 1",
        "$$$fluxtags_hl(off)",
        "line 3",
        "$$$fluxtags_hl(on)",
        "line 5"
    }
    
    local hl_intervals = cfg_kind:get_disabled_intervals(lines, "fluxtags_hl")
    -- Expect: interval from line 2, col after '$$$fluxtags_hl(off)' to line 4, col before '$$$fluxtags_hl(on)'
    -- $$$fluxtags_hl(off) starts at col 1, ends at col 20 (length 19)
    -- lnum is 0-indexed in get_disabled_intervals.
    -- lnum0=2 (line 2) -> start_lnum = 1, tag_end = 20
    -- lnum0=4 (line 4) -> end_lnum = 3, s - 1 = 0
    assert_deep_eq({{1, 19, 3, 0}}, hl_intervals, "fluxtags_hl intervals should match")

    -- Test 2: get_disabled_intervals for fluxtags_reg without closing 'on'
    lines = {
        "line 1",
        "$$$fluxtags_reg(off)",
        "line 3",
    }
    local reg_intervals = cfg_kind:get_disabled_intervals(lines, "fluxtags_reg")
    assert_deep_eq({{1, 20, math.huge, math.huge}}, reg_intervals, "fluxtags_reg open interval")

    -- Test 3: multiple intervals
    lines = {
        "$$$fluxtags_hl(off)",
        "$$$fluxtags_hl(on)",
        "$$$fluxtags_hl(off)",
        "$$$fluxtags_hl(on)",
    }
    hl_intervals = cfg_kind:get_disabled_intervals(lines, "fluxtags_hl")
    assert_deep_eq({
        {0, 19, 1, 0},
        {2, 19, 3, 0},
    }, hl_intervals, "multiple hl intervals")
    

    -- Test 3b: new colon-style cfg directives
    lines = {
        "$$$ftags-hl:off",
        "line",
        "$$$ftags-hl:on",
        "$$$ftags-register:off",
    }
    hl_intervals = cfg_kind:get_disabled_intervals(lines, "ftags-hl")
    assert_deep_eq({{0, 15, 2, 0}}, hl_intervals, "ftags-hl colon interval")
    reg_intervals = cfg_kind:get_disabled_intervals(lines, "ftags-register")
    assert_deep_eq({{3, 21, math.huge, math.huge}}, reg_intervals, "ftags-register colon interval")

    -- Test 4: Buffer wide disabled flag
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "$$$ftags:off",
        "###test_mark",
    })
    
    -- Simulate on_enter to trigger the ftags:off handler
    cfg_kind.on_enter(bufnr, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert_eq(true, vim.b[bufnr].fluxtags_disabled, "ftags:off should set buffer variable")
    

    -- Test 5: directive list metadata includes syntax and examples for previews.
    local directives = require("tagkinds.cfg").get_directives_info()
    local by_key = {}
    for _, item in ipairs(directives) do
        by_key[item.key] = item
    end
    assert_eq("$$$ft(<value>)", by_key.ft.syntax, "cfg list should expose directive syntax")
    assert_eq(true, by_key.ft.example:find("$$$ft%(lua%)") ~= nil, "cfg list should expose an example")
    assert_eq("$$$ftags:<on|off>", by_key.ftags.syntax, "cfg list should expose colon syntax")
    print("All tests passed!")
end

M.run()
