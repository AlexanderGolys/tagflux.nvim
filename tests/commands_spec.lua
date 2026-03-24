local M = {}

local helpers = require("tests.test_helpers")

---@param lines string[]
---@param pattern string
local function has_line(lines, pattern)
  for _, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

function M.run()
  local fluxtags = require("fluxtags")
  local commands = require("fluxtags.commands")
  local tmpdir = helpers.create_tmpdir()
  local original_cwd = vim.loop.cwd()
  local ok, err

  fluxtags.setup({
    kinds = {
      mark = { tagfile = tmpdir .. "/mark.tags" },
      og = { tagfile = tmpdir .. "/og.tags" },
      ref = { tagfile = tmpdir .. "/ref.tags" },
    },
  })

  ok, err = xpcall(function()
    local terminal_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(terminal_buf, tmpdir .. "/term.txt")
    vim.api.nvim_open_term(terminal_buf, {})
    helpers.assert_false(fluxtags:should_process_buf(terminal_buf), "terminal buffers should be skipped")
    helpers.cleanup_buffer(terminal_buf)

    local oil_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(oil_buf, tmpdir .. "/oil.txt")
    vim.bo[oil_buf].filetype = "oil"
    helpers.assert_false(fluxtags:should_process_buf(oil_buf), "oil buffers should be skipped")
    helpers.cleanup_buffer(oil_buf)

    local tree_buf = helpers.create_test_buffer({ "-- /@@target" })
    local ns = vim.api.nvim_create_namespace("fluxtags_ref_conceal_test")
    fluxtags.tag_kinds.ref:apply_extmarks(tree_buf, 0, "-- /@@target", ns)
    local extmarks = vim.api.nvim_buf_get_extmarks(tree_buf, ns, 0, -1, { details = true })
    table.sort(extmarks, function(a, b)
      return a[3] < b[3]
    end)
    helpers.assert_eq("/", extmarks[1][4].conceal, "ref prefix should keep slash visible")
    helpers.assert_eq("@", extmarks[2][4].conceal, "ref marker should collapse @@ to @")
    helpers.cleanup_buffer(tree_buf)

    local mark_file = tmpdir .. "/notes.md"
    local ref_file = tmpdir .. "/refs.md"
    local topic_file = tmpdir .. "/topics.md"
    vim.fn.writefile({
      "-- @@@target",
      "text",
    }, mark_file)
    vim.fn.writefile({
      "-- /@@target",
      "inline @target.section",
    }, ref_file)
    vim.fn.writefile({
      "Topic @##alpha",
      "-- #|#||alpha||",
    }, topic_file)

    vim.cmd.cd(tmpdir)
    local lines = commands._build_tree_lines(tmpdir, function(kind_name)
      if kind_name == "mark" then
        return {
          target = {
            { file = mark_file, lnum = 1 },
          },
          outside = {
            { file = "/tmp/outside.md", lnum = 1 },
          },
        }
      end
      if kind_name == "og" then
        return {
          alpha = {
            { file = topic_file, lnum = 1 },
          },
        }
      end
      return {}
    end)

    helpers.assert_true(has_line(lines, "- `@@@target` — notes.md:1"), "tree should list project mark")
    helpers.assert_true(has_line(lines, "refs (2):"), "tree should count block and inline refs")
    helpers.assert_true(has_line(lines, "refs.md:1 -> /@@target"), "tree should list block refs")
    helpers.assert_true(has_line(lines, "refs.md:2 -> /@@target.section"), "tree should list inline refs")
    helpers.assert_true(has_line(lines, "### @##alpha (1 occurrences)"), "tree should list og topic")
    helpers.assert_true(has_line(lines, "refogs (1):"), "tree should count refog references")
    helpers.assert_true(has_line(lines, "topics.md:2 -> #|#||alpha"), "tree should list refogs")
    helpers.assert_false(has_line(lines, "@@@outside"), "tree should ignore non-project marks")

    fluxtags.setup({ keymaps = { jump = "g]" } })
    local custom_jump = vim.fn.maparg("g]", "n", false, true)
    helpers.assert_eq("Jump to fluxtag under cursor", custom_jump.desc, "custom jump keymap should be registered")

    fluxtags.setup({ keymaps = { jump = false } })
    local disabled_jump = vim.fn.maparg("<C-]>", "n", false, true)
    helpers.assert_true(vim.tbl_isempty(disabled_jump), "disabled jump keymap should not be registered")
  end, debug.traceback)

  vim.cmd.cd(original_cwd)
  helpers.cleanup_tmpdir(tmpdir)
  if not ok then
    error(err)
  end
  print("Command tests passed!")
end

M.run()
