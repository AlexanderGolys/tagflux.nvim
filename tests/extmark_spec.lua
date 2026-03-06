local M = {}

local helpers = require("tests.test_helpers")

function M.run()
    local Extmark = require("fluxtags.extmark")

    -- Test 1: required constructor fields
    print("Test 1: constructor required fields")
    local ok_missing_bufnr = pcall(Extmark.new, nil, 0, 1, 1, {})
    helpers.assert_false(ok_missing_bufnr, "Should fail without bufnr")

    local ok_missing_lnum = pcall(Extmark.new, 1, 0, nil, 1, {})
    helpers.assert_false(ok_missing_lnum, "Should fail without lnum")

    local ok_missing_col = pcall(Extmark.new, 1, 0, 1, nil, {})
    helpers.assert_false(ok_missing_col, "Should fail without col")

    -- Test 2: defaults for ns and opts
    print("Test 2: constructor defaults")
    local em = Extmark.new(10, nil, 2, 3, nil, {})
    helpers.assert_eq(10, em.bufnr, "bufnr preserved")
    helpers.assert_eq(0, em.ns, "ns defaults to 0")
    helpers.assert_eq(2, em.lnum, "lnum preserved")
    helpers.assert_eq(3, em.col, "col preserved")
    helpers.assert_deep_eq({}, em.opts, "opts defaults to empty table")

    -- Test 3: instance set delegates to api
    print("Test 3: set delegates to api")
    local captured = {}
    local fake_api = {
        nvim_buf_set_extmark = function(bufnr, ns, lnum, col, opts)
            captured = { bufnr = bufnr, ns = ns, lnum = lnum, col = col, opts = opts }
            return 99
        end,
    }
    local em2 = Extmark.new(4, 7, 8, 9, { hl_group = "X" }, fake_api)
    local ok_set, id = em2:set()
    helpers.assert_true(ok_set, "set should succeed with fake api")
    helpers.assert_eq(99, id, "set should return extmark id")
    helpers.assert_eq(4, captured.bufnr, "bufnr passed to api")
    helpers.assert_eq(7, captured.ns, "ns passed to api")
    helpers.assert_eq(8, captured.lnum, "lnum passed to api")
    helpers.assert_eq(9, captured.col, "col passed to api")
    helpers.assert_eq("X", captured.opts.hl_group, "opts passed to api")

    -- Test 4: place helper creates and sets extmark
    print("Test 4: place helper")
    local captured_place = {}
    local fake_api_place = {
        nvim_buf_set_extmark = function(bufnr, ns, lnum, col, opts)
            captured_place = { bufnr = bufnr, ns = ns, lnum = lnum, col = col, opts = opts }
            return 123
        end,
    }
    local ok_place, id_place = Extmark.place(1, nil, 2, 3, nil, fake_api_place)
    helpers.assert_true(ok_place, "place should succeed")
    helpers.assert_eq(123, id_place, "place should return extmark id")
    helpers.assert_eq(1, captured_place.bufnr, "place bufnr")
    helpers.assert_eq(0, captured_place.ns, "place ns default")
    helpers.assert_eq(2, captured_place.lnum, "place lnum")
    helpers.assert_eq(3, captured_place.col, "place col")
    helpers.assert_deep_eq({}, captured_place.opts, "place opts default")

    print("All extmark tests passed!")
end

M.run()
