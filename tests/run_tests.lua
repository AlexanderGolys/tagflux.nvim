local M = {}
local Path = require("fluxtags.path")
local path_utils = Path.new()

function M.run()
    local dir = path_utils:dirname(debug.getinfo(1, "S").source:sub(2))
    local pattern = dir .. "/*_spec.lua"
    local files = vim.split(vim.fn.glob(pattern), "\n")
    
    local passed = 0
    local failed = 0
    local failed_list = {}

    for _, file in ipairs(files) do
        if file ~= "" then
            print("\nRunning " .. path_utils:basename(file) .. "...")
            local chunk, err = loadfile(file)
            if not chunk then
                print("Failed to load: " .. file .. "\n" .. err)
                failed = failed + 1
                table.insert(failed_list, file)
            else
                local ok, run_err = pcall(chunk)
                if not ok then
                    print("Test failed: " .. file .. "\n" .. tostring(run_err))
                    failed = failed + 1
                    table.insert(failed_list, file)
                else
                    passed = passed + 1
                end
            end
        end
    end

    print(string.format("\n=== Test Summary ==="))
    print(string.format("Passed: %d", passed))
    print(string.format("Failed: %d", failed))
    
    if failed > 0 then
        print("Failing files:")
        for _, f in ipairs(failed_list) do
            print("  " .. f)
        end
        os.exit(1)
    else
        os.exit(0)
    end
end

M.run()
