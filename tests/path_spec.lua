local M = {}

local helpers = require("tests.test_helpers")

function M.run()
    local Path = require("fluxtags.path")

    local calls = {}
    local fake_fn = {
        fnamemodify = function(path, flag)
            table.insert(calls, { path = path, flag = flag })
            return ("out:%s:%s"):format(path, flag)
        end,
    }

    local path_utils = Path.new(fake_fn)

    print("Test 1: absolute uses :p")
    local abs = path_utils:absolute("a/b")
    helpers.assert_eq("out:a/b::p", abs, "absolute return value")
    helpers.assert_eq(":p", calls[#calls].flag, "absolute should use :p")

    print("Test 2: display_relative uses :~:.")
    local rel = path_utils:display_relative("a/b")
    helpers.assert_eq("out:a/b::~:.", rel, "display_relative return value")
    helpers.assert_eq(":~:.", calls[#calls].flag, "display_relative should use :~:.")

    print("Test 3: dirname uses :h")
    local dir = path_utils:dirname("a/b")
    helpers.assert_eq("out:a/b::h", dir, "dirname return value")
    helpers.assert_eq(":h", calls[#calls].flag, "dirname should use :h")

    print("Test 4: basename uses :t")
    local base = path_utils:basename("a/b")
    helpers.assert_eq("out:a/b::t", base, "basename return value")
    helpers.assert_eq(":t", calls[#calls].flag, "basename should use :t")

    helpers.assert_eq(4, #calls, "Should invoke fnamemodify 4 times")
    print("All path tests passed!")
end

M.run()
