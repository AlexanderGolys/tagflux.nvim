local M = {}

--- Register all autocommands that drive buffer initialization, live refresh,
--- and automatic tag persistence.
---
--- `schedule_refresh` is the debounced callback from fluxtags.lua; it is
--- passed in to avoid a circular require between this module and the core.
---
--- @param fluxtags table  The main fluxtags module table
--- @param schedule_refresh fun(bufnr: number)
---
function M.setup(fluxtags, schedule_refresh)
    local _config = require("fluxtags_config")
    local augroup = vim.api.nvim_create_augroup("Fluxtags", { clear = true })

    -- Re-link highlight groups after any colorscheme change so FluxTag* groups
    -- survive theme switching.
    vim.api.nvim_create_autocmd("ColorScheme", {
        group    = augroup,
        callback = function()
            _config.setup_default_highlights(fluxtags.config.highlights)
        end,
        pattern  = "*",
    })

    -- Apply once after startup so colorscheme plugins that run on VimEnter
    -- do not overwrite FluxTag* groups.
    vim.api.nvim_create_autocmd("VimEnter", {
        group    = augroup,
        once     = true,
        callback = function()
            vim.schedule(function()
                _config.setup_default_highlights(fluxtags.config.highlights)
            end)
        end,
    })

    -- Initialize extmarks and on_enter hooks whenever a buffer comes into view.
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group    = augroup,
        callback = function(args) schedule_refresh(args.buf) end,
    })

    -- Re-apply extmarks while editing so highlights stay in sync with edits.
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group    = augroup,
        callback = function(args) schedule_refresh(args.buf) end,
    })

    -- Persist tags to tagfiles whenever the buffer is written.
    vim.api.nvim_create_autocmd("BufWritePost", {
        group    = augroup,
        callback = function(args)
            fluxtags.setup_buffer(args.buf, true)
            fluxtags.update_tags(false, args.buf)
        end,
    })
end

return M
