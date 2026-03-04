local M = {}

local helpers = require("tests.test_helpers")

function M.run()
    local prefix_util = require("fluxtags.prefix")
    
    -- Test 1: find_prefix basic usage
    print("Test 1: find_prefix with comment prefix")
    local line1 = "-- @@@mark"
    local s1, prefix1 = prefix_util.find_prefix(line1, 4) -- position of "@"
    helpers.assert_eq("-- ", prefix1, "Should find Lua comment prefix")
    
    -- Test 2: find_prefix with hash
    print("Test 2: find_prefix with hash")
    local line2 = "# @@@mark"
    local s2, prefix2 = prefix_util.find_prefix(line2, 3) -- position of "@"
    helpers.assert_eq("# ", prefix2, "Should find Python comment prefix")
    
    -- Test 3: find_prefix with C comment
    print("Test 3: find_prefix with C comment")
    local line3 = "// @@@mark"
    local s3, prefix3 = prefix_util.find_prefix(line3, 4) -- position of "@"
    helpers.assert_eq("// ", prefix3, "Should find C comment prefix")
    
    -- Test 4: find_prefix with no prefix
    print("Test 4: find_prefix no prefix")
    local line4 = "@@@mark"
    local s4, prefix4 = prefix_util.find_prefix(line4, 1) -- marker starts at position 1
    helpers.assert_eq("", prefix4, "Should return empty when no prefix")
    helpers.assert_eq(1, s4, "Position should be marker start")
    
    -- Test 5: find_prefix with indentation
    print("Test 5: find_prefix with leading whitespace")
    local line5 = "  -- @@@mark"
    local s5, prefix5 = prefix_util.find_prefix(line5, 6) -- position of "@"
    helpers.assert_eq("-- ", prefix5, "Should find prefix after whitespace")
    
    -- Test 6: find_tag_at_cursor - basic pattern match
    print("Test 6: find_tag_at_cursor basic")
    local line_tag = "@@@mymark here"
    local pattern = "@@@([%w_.%-%+%*%/%\\:]+)"
    local capture, start_col, end_col = prefix_util.find_tag_at_cursor(line_tag, 5, pattern)
    helpers.assert_not_nil(capture, "Should find tag at cursor")
    helpers.assert_eq("mymark", capture, "Should capture tag name")
    
    -- Test 7: find_tag_at_cursor - no tag at cursor
    print("Test 7: find_tag_at_cursor no tag")
    local line_empty = "Just plain text here"
    local capture_empty = prefix_util.find_tag_at_cursor(line_empty, 5, pattern)
    helpers.assert_nil(capture_empty, "Should return nil when no tag at cursor")
    
    -- Test 8: find_match_at_cursor - basic match
    print("Test 8: find_match_at_cursor basic")
    local line_match = "text with /@@ref here"
    local pattern_ref = "/@@([%w_.%-%+%*%/%\\:]+)"
    local match = prefix_util.find_match_at_cursor(line_match, 12, pattern_ref)
    helpers.assert_not_nil(match, "Should find match at cursor")
    helpers.assert_eq("ref", match, "Should capture correct match")
    
    -- Test 9: find_match_at_cursor - no match at cursor
    print("Test 9: find_match_at_cursor no match")
    local line_nomatch = "just plain text"
    local nomatch = prefix_util.find_match_at_cursor(line_nomatch, 5, pattern_ref)
    helpers.assert_nil(nomatch, "Should return nil when no match at cursor")
    
    -- Test 10: find_match_at_cursor - multiple matches (first)
    print("Test 10: find_match_at_cursor first")
    local line_multi = "/@@first and /@@second"
    local match1 = prefix_util.find_match_at_cursor(line_multi, 3, pattern_ref)
    helpers.assert_not_nil(match1, "Should find first match")
    helpers.assert_eq("first", match1, "Should capture first ref")
    
    -- Test 11: find_match_at_cursor - multiple matches (second)
    print("Test 11: find_match_at_cursor second")
    local match2 = prefix_util.find_match_at_cursor(line_multi, 16, pattern_ref)
    helpers.assert_not_nil(match2, "Should find second match")
    helpers.assert_eq("second", match2, "Should capture second ref")
    
    -- Test 12: default_comment_prefix_patterns exists
    print("Test 12: default patterns")
    helpers.assert_not_nil(prefix_util.default_comment_prefix_patterns, "Default patterns exist")
    helpers.assert_true(#prefix_util.default_comment_prefix_patterns > 0, "Patterns list not empty")
    
    -- Test 13: find_tag_at_cursor with custom prefix patterns
    print("Test 13: find_tag_at_cursor custom patterns")
    local line_custom = "-- @@@mark"
    local custom_patterns = { "%-%-%s*" }
    local capture_custom = prefix_util.find_tag_at_cursor(line_custom, 5, pattern, custom_patterns)
    helpers.assert_not_nil(capture_custom, "Should find tag with custom patterns")
    
    -- Test 14: find_prefix with tab character
    print("Test 14: find_prefix with tab")
    local line_tab = "\t-- @@@mark"
    local s_tab, prefix_tab = prefix_util.find_prefix(line_tab, 5)
    helpers.assert_eq("-- ", prefix_tab, "Should find prefix after tab")
    
    -- Test 15: find_tag_at_cursor at match boundary
    print("Test 15: find_tag_at_cursor boundary")
    local line_boundary = "Start @@@mark end"
    local capture_boundary = prefix_util.find_tag_at_cursor(line_boundary, 7, pattern)
    helpers.assert_not_nil(capture_boundary, "Should find tag at cursor near boundary")
    
    print("All prefix tests passed!")
end

M.run()
