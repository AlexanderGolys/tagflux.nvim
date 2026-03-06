local M = {}

local helpers = require("tests.test_helpers")

function M.run()
    local common = require("fluxtags.common")
    
    -- Test 1: is_valid_name with valid names
    print("Test 1: is_valid_name - valid names")
    helpers.assert_true(common.is_valid_name("simple"), "simple name")
    helpers.assert_true(common.is_valid_name("with_underscore"), "underscore")
    helpers.assert_true(common.is_valid_name("with-dash"), "dash")
    helpers.assert_true(common.is_valid_name("config.defaults"), "subtag")
    helpers.assert_true(common.is_valid_name("a"), "single char")
    helpers.assert_true(common.is_valid_name("NAME123"), "alphanumeric")
    
    -- Test 2: is_valid_name with invalid names
    print("Test 2: is_valid_name - invalid names")
    helpers.assert_false(common.is_valid_name(""), "empty string")
    helpers.assert_false(common.is_valid_name(" "), "space only")
    helpers.assert_false(common.is_valid_name("with space"), "contains space")
    helpers.assert_false(common.is_valid_name("!special"), "starts with special")
    
    -- Test 3: is_valid_name with special allowed chars
    print("Test 3: is_valid_name - allowed special chars")
    helpers.assert_true(common.is_valid_name("name+plus"), "plus sign")
    helpers.assert_true(common.is_valid_name("name*star"), "asterisk")
    helpers.assert_true(common.is_valid_name("name/slash"), "forward slash")
    helpers.assert_true(common.is_valid_name("name\\back"), "backslash")
    helpers.assert_true(common.is_valid_name("name:colon"), "colon")
    
    -- Test 4: INLINE_SUBTAG_PATTERN
    print("Test 4: INLINE_SUBTAG_PATTERN")
    helpers.assert_not_nil(common.INLINE_SUBTAG_PATTERN, "Pattern exists")
    -- Pattern should match inline subtag references
    local test_str = "@base.sub"
    local match = test_str:match(common.INLINE_SUBTAG_PATTERN)
    helpers.assert_not_nil(match, "Should match subtag pattern")
    
    -- Test 5: derive_open helper
    print("Test 5: derive_open")
    local open1 = common.derive_open("@@@([%w_.%-%+%*%/%\\:]+)", "@@@")
    helpers.assert_eq("@@@", open1, "Extract @@@ from pattern")
    
    local open2 = common.derive_open("/@@([%w_.%-%+%*%/%\\:]+)", "/@@")
    helpers.assert_eq("/@@", open2, "Extract /@@")
    
    local open3 = common.derive_open("&&&([%w_@-]+)&&&(.-)&&&", "&&&")
    helpers.assert_eq("&&&", open3, "Extract &&&")
    
    -- Test 6: derive_open with fallback
    print("Test 6: derive_open fallback")
    local open4 = common.derive_open("custom_pattern", "@")
    helpers.assert_eq("@", open4, "Use fallback when pattern doesn't match")
    
    -- Test 7: resolve_kind_config basic
    print("Test 7: resolve_kind_config basic")
    local fluxtags = require("fluxtags")
    fluxtags.setup({
        kinds = {
            test = { tagfile = "/tmp/test.tags" }
        }
    })
    
    local cfg, opts = common.resolve_kind_config(
        fluxtags,
        "test",
        {
            name = "test",
            pattern = "test_pattern",
            hl_group = "TestHL",
            priority = 50,
        },
        { "%-%-" } -- comment prefix patterns
    )
    
    helpers.assert_eq("test", opts.name, "Config name preserved")
    helpers.assert_eq("test_pattern", opts.pattern, "Pattern preserved")
    helpers.assert_eq("TestHL", opts.hl_group, "HL group preserved")
    helpers.assert_eq(50, opts.priority, "Priority preserved")
    
    -- Test 8: resolve_kind_config with user overrides
    print("Test 8: resolve_kind_config with overrides")
    fluxtags.setup({
        kinds = {
            test2 = { 
                pattern = "custom_pattern",
                hl_group = "CustomHL",
            }
        }
    })
    
    local cfg2, opts2 = common.resolve_kind_config(
        fluxtags,
        "test2",
        {
            name = "test2",
            pattern = "default_pattern",
            hl_group = "DefaultHL",
            priority = 50,
        },
        { "%-%-" }
    )
    
    helpers.assert_eq("custom_pattern", opts2.pattern, "User pattern override")
    helpers.assert_eq("CustomHL", opts2.hl_group, "User hl_group override")
    
    -- Test 9: resolve_kind_config preserves comment_prefix_patterns
    print("Test 9: resolve_kind_config comment patterns")
    local patterns = { "%-%-", "#", "%" }
    local cfg3, opts3 = common.resolve_kind_config(
        fluxtags,
        "test3",
        { name = "test3", pattern = "p" },
        patterns
    )
    
    helpers.assert_not_nil(opts3.comment_prefix_patterns, "Patterns set")
    helpers.assert_len(opts3.comment_prefix_patterns, 3, "Patterns count")
    
    print("All common tests passed!")
end

M.run()
