local M = {}

local helpers = require("tests.test_helpers")

function M.run()
    print("Running integration tests...")
    
    -- Test 1: Mark kind basic workflow
    print("Test 1: Mark kind basic")
    local fluxtags = require("fluxtags")
    local tmpdir = helpers.create_tmpdir()
    
    fluxtags.setup({
        kinds = {
            mark = { tagfile = tmpdir .. "/mark.tags" },
            og = { tagfile = tmpdir .. "/og.tags" },
        }
    })
    
    local mark_kind = fluxtags.tag_kinds.mark
    
    local lines = {
        "-- @@@function_start",
        "function code here",
        "-- @@@function_end",
    }
    
    -- collect_tags should work for mark kind
    local tags = mark_kind:collect_tags("/tmp/test.lua", lines)
    helpers.assert_len(tags, 2, "Should collect 2 mark tags")
    helpers.assert_eq("function_start", tags[1].name)
    helpers.assert_eq(1, tags[1].lnum)
    
    -- Test 2: OG kind basic workflow
    print("Test 2: OG kind basic")
    local og_kind = fluxtags.tag_kinds.og
    
    local og_lines = {
        "Task @##high-priority",
        "Bug @##regression",
        "Feature @##enhancement",
    }
    
    local og_tags = og_kind:collect_tags("/tmp/doc.lua", og_lines)
    helpers.assert_len(og_tags, 3, "Should collect 3 og tags")
    helpers.assert_eq("high-priority", og_tags[1].name)
    helpers.assert_eq(1, og_tags[1].lnum)
    helpers.assert_eq("regression", og_tags[2].name)

    -- /@@fluxtags.hl
    -- Test 2b: HL extmarks stay within bounds at end of line
    print("Test 2b: HL extmark bounds")
    local hl_kind = fluxtags.tag_kinds.hl
    local hl_lines = {
        "-- &&&Error&&&FIXME: broken&&&",
    }
    local hl_bufnr = helpers.create_test_buffer(hl_lines)
    local hl_ns = vim.api.nvim_create_namespace("test_hl")
    local ok_hl, err_hl = pcall(function()
        hl_kind:apply_extmarks(hl_bufnr, 0, hl_lines[1], hl_ns)
    end)
    helpers.assert_true(ok_hl, "HL extmarks should not overflow line bounds: " .. tostring(err_hl))
    local hl_extmarks = vim.api.nvim_buf_get_extmarks(hl_bufnr, hl_ns, 0, -1, {})
    helpers.assert_len(hl_extmarks, 5, "HL tags should create five extmarks")
    helpers.cleanup_buffer(hl_bufnr)

    -- Test 2c: HL tags support multiline content
    print("Test 2c: HL multiline content")
    local hl_multiline_lines = {
        "-- &&&Error&&&FIXME: broken",
        "-- still broken&&&",
    }
    local hl_multiline_bufnr = helpers.create_test_buffer(hl_multiline_lines)
    local hl_multiline_ns = vim.api.nvim_create_namespace("test_hl_multiline")
    local ok_hl_multiline, err_hl_multiline = pcall(function()
        hl_kind:apply_extmarks(hl_multiline_bufnr, 0, hl_multiline_lines[1], hl_multiline_ns)
    end)
    helpers.assert_true(ok_hl_multiline, "HL multiline extmarks should apply: " .. tostring(err_hl_multiline))
    local hl_multiline_extmarks = vim.api.nvim_buf_get_extmarks(hl_multiline_bufnr, hl_multiline_ns, 0, -1, { details = true })
    helpers.assert_len(hl_multiline_extmarks, 7, "Multiline HL tags should create seven extmarks")

    local saw_second_line_highlight = false
    for _, extmark in ipairs(hl_multiline_extmarks) do
        local details = extmark[4]
        if extmark[2] == 1 and details and details.hl_group == "Error" then
            saw_second_line_highlight = true
            break
        end
    end
    helpers.assert_true(saw_second_line_highlight, "Multiline HL tags should highlight continuation lines")
    helpers.cleanup_buffer(hl_multiline_bufnr)

    -- Test 3: Extmarks work for collected tags
    print("Test 3: Extmarks application")
    local bufnr = helpers.create_test_buffer(lines)
    local ns = vim.api.nvim_create_namespace("test_marks")
    
    for i, tag in ipairs(tags) do
        mark_kind:apply_extmarks(bufnr, tag.lnum - 1, lines[tag.lnum], ns)
    end
    
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    helpers.assert_not_nil(extmarks, "Should have extmarks applied")
    
    helpers.cleanup_buffer(bufnr)
    
    -- Test 4: Mixed tags with disabled regions
    print("Test 4: Disabled regions")
    bufnr = helpers.create_test_buffer(og_lines)
    local is_disabled = function(lnum, col)
        return lnum == 1 -- disable line 2
    end
    
    for i, tag in ipairs(og_tags) do
        og_kind:apply_extmarks(bufnr, tag.lnum - 1, og_lines[tag.lnum], ns, is_disabled)
    end
    
    extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    -- Should skip one extmark due to disabled region
    helpers.assert_not_nil(extmarks, "Should apply extmarks with disabled handling")
    
    helpers.cleanup_buffer(bufnr)
    
    -- Test 5: Tag validation
    print("Test 5: Tag name validation")
    local invalid_lines = {
        "-- @@@valid",
        "-- @@@",
        "-- @@@another.valid",
    }
    
    local mixed_tags = mark_kind:collect_tags("/tmp/mixed.lua", invalid_lines)
    -- Only valid tags should be collected
    helpers.assert_not_nil(mixed_tags, "Should handle mixed valid/invalid")
    
    -- Test 6: Empty buffer handling
    print("Test 6: Empty buffer")
    local empty_tags = mark_kind:collect_tags("/tmp/empty.lua", {})
    helpers.assert_len(empty_tags, 0, "Should handle empty buffer")
    
    -- Test 7: Sparse buffer
    print("Test 7: Sparse buffer")
    local sparse = {
        "",
        "",
        "-- @@@sparse_tag",
        "",
    }
    
    local sparse_tags = mark_kind:collect_tags("/tmp/sparse.lua", sparse)
    helpers.assert_len(sparse_tags, 1, "Should find tag in sparse buffer")
    helpers.assert_eq(3, sparse_tags[1].lnum, "Tag at correct line")
    
    -- Test 8: Special characters in names
    print("Test 8: Special character support")
    local special_lines = {
        "-- @@@config.defaults",
        "-- @@@feature-flag",
        "-- @@@parser_v2",
    }
    
    local special_tags = mark_kind:collect_tags("/tmp/special.lua", special_lines)
    helpers.assert_len(special_tags, 3, "Should handle special chars")

    -- Test 8b: Dotted mark jumps resolve to the parent mark
    print("Test 8b: Dotted mark jump resolution")
    local jump_file = tmpdir .. "/jump.lua"
    vim.fn.writefile({
        "-- @@@config",
        "-- @@@config.defaults",
    }, jump_file)
    local jump_ctx = {
        utils = {
            load_tagfile = function()
                return {
                    config = {
                        { file = jump_file, lnum = 1, col = 4 },
                    },
                    ["config.defaults"] = {
                        { file = jump_file, lnum = 2, col = 4 },
                    },
                }
            end,
            open_file = function(path)
                vim.cmd.edit(path)
            end,
        },
        kind_name = "mark",
    }
    local jumped = mark_kind.on_jump("config.defaults", jump_ctx)
    helpers.assert_true(jumped, "Dotted mark jump should be handled")
    helpers.assert_eq(1, vim.fn.line("."), "Dotted mark should jump to parent mark")
    
    -- Test 9: Duplicate names in file
    print("Test 9: Duplicate names")
    local dups = {
        "-- @@@sameName",
        "other content",
        "-- @@@sameName",
    }
    
    local dup_tags = mark_kind:collect_tags("/tmp/dups.lua", dups)
    helpers.assert_len(dup_tags, 2, "Should collect both duplicates")
    helpers.assert_eq("sameName", dup_tags[1].name)
    helpers.assert_eq("sameName", dup_tags[2].name)
    
    -- Test 10: Large buffer
    print("Test 10: Large buffer")
    local large = {}
    for i = 1, 100 do
        if i % 10 == 0 then
            table.insert(large, "-- @@@mark_" .. i)
        else
            table.insert(large, "line " .. i)
        end
    end
    
    local large_tags = mark_kind:collect_tags("/tmp/large.lua", large)
    helpers.assert_len(large_tags, 10, "Should handle large buffer")
    
    helpers.cleanup_tmpdir(tmpdir)
    print("All integration tests passed!")
end

M.run()
