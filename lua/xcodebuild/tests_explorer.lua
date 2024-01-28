local config = require("xcodebuild.config").options.tests_explorer

local M = {}

local spinnerFrames = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}

local STATUS_NOT_EXECUTED = "not_executed"
local STATUS_RUNNING = "running"
local STATUS_PASSED = "passed"
local STATUS_FAILED = "failed"
local STATUS_DISABLED = "disabled"

local KIND_TARGET = "target"
local KIND_CLASS = "class"
local KIND_TEST = "test"

local currentFrame = 1
local last_update = nil
local ns = vim.api.nvim_create_namespace("xcodebuild-tests-explorer")

local function generate_report(tests)
  local targets = {}
  local current_target = {
    name = "",
    classes = {},
  }
  local current_class = {
    name = "",
    tests = {},
  }

  for _, test in ipairs(tests) do
    if not config.show_disabled_tests and not test.enabled then
      goto continue
    end

    if test.target ~= current_target.name then
      current_target = {
        id = test.target,
        kind = KIND_TARGET,
        status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
        name = test.target,
        classes = {},
      }
      table.insert(targets, current_target)
    end

    if test.class ~= current_class.name then
      current_class = {
        id = test.target .. "/" .. test.class,
        kind = KIND_CLASS,
        status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
        name = test.class,
        tests = {},
      }
      table.insert(current_target.classes, current_class)
    end

    table.insert(current_class.tests, {
      id = test.id,
      kind = KIND_TEST,
      status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
      name = test.name,
    })

    ::continue::
  end

  M.report = targets
end

local function get_hl_for_status(status)
  if status == STATUS_NOT_EXECUTED then
    return "XcodebuildTestsExplorerTestNotExecuted"
  elseif status == STATUS_RUNNING then
    return "XcodebuildTestsExplorerTestInProgress"
  elseif status == STATUS_PASSED then
    return "XcodebuildTestsExplorerTestPassed"
  elseif status == STATUS_FAILED then
    return "XcodebuildTestsExplorerTestFailed"
  elseif status == STATUS_DISABLED then
    return "XcodebuildTestsExplorerTestDisabled"
  else
    return "@text"
  end
end

local function get_icon_for_status(status)
  if status == STATUS_NOT_EXECUTED then
    return config.not_executed_sign
  elseif status == STATUS_RUNNING then
    return config.animate_status and spinnerFrames[currentFrame] or config.progress_sign
  elseif status == STATUS_PASSED then
    return config.success_sign
  elseif status == STATUS_FAILED then
    return config.failure_sign
  elseif status == STATUS_DISABLED then
    return config.disabled_sign
  else
    return "@text"
  end
end

local function get_text_hl_for_kind(kind, status)
  if status == STATUS_DISABLED then
    return "XcodebuildTestsExplorerTestDisabled"
  elseif kind == KIND_TEST then
    return "XcodebuildTestsExplorerTest"
  elseif kind == KIND_CLASS then
    return "XcodebuildTestsExplorerClass"
  elseif kind == KIND_TARGET then
    return "XcodebuildTestsExplorerTarget"
  end
end

local function format_line(line, row)
  local status = line.status
  local kind = line.kind
  local name = line.name
  local icon = get_icon_for_status(status)
  local icon_len = string.len(icon)
  local text_hl = get_text_hl_for_kind(kind, status)

  local get_highlights = function(col_start, text_highlight)
    return {
      {
        row = row,
        col_start = col_start,
        col_end = icon_len + col_start + 2,
        group = get_hl_for_status(status),
      },
      {
        row = row,
        col_start = icon_len + col_start + 2,
        col_end = -1,
        group = text_highlight,
      },
    }
  end

  if kind == KIND_TEST then
    return string.format("    [%s] %s", icon, name), get_highlights(4, text_hl)
  elseif kind == KIND_CLASS then
    return string.format("  [%s] %s", icon, name), get_highlights(2, text_hl)
  elseif kind == KIND_TARGET then
    return string.format("[%s] %s", icon, name), get_highlights(0, text_hl)
  end
end

local function get_aggregated_status(children)
  local passed = false
  local failed = false
  local disabled = false
  local notExecuted = false

  for _, child in ipairs(children) do
    if child.status == STATUS_RUNNING then
      return STATUS_RUNNING
    elseif child.status == STATUS_FAILED then
      failed = true
      passed = false
    elseif child.status == STATUS_PASSED then
      passed = not failed
    elseif child.status == STATUS_NOT_EXECUTED then
      notExecuted = true
    end
  end

  if notExecuted then
    return STATUS_NOT_EXECUTED
  elseif failed then
    return STATUS_FAILED
  elseif passed then
    return STATUS_PASSED
  elseif disabled then
    return STATUS_DISABLED
  else
    return STATUS_NOT_EXECUTED
  end
end

local function refresh_progress()
  local lines = {}
  local highlights = {}
  local row = 1
  local move_cursor_to_row = nil

  local add_line = function(data)
    local text, hls = format_line(data, row)
    table.insert(lines, text)

    for _, hl in ipairs(hls) do
      table.insert(highlights, hl)
    end

    if config.cursor_follows_tests and last_update == data.id then
      move_cursor_to_row = row
      last_update = nil
    end

    row = row + 1
  end

  for _, target in ipairs(M.report) do
    add_line(target)

    for _, class in ipairs(target.classes) do
      add_line(class)

      for _, test in ipairs(class.tests) do
        add_line(test)
      end
    end
  end

  vim.api.nvim_buf_clear_namespace(M.bufnr, ns, 0, -1)
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(M.bufnr, "modified", false)

  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      M.bufnr,
      ns,
      highlight.group,
      highlight.row - 1,
      highlight.col_start,
      highlight.col_end
    )
  end

  if move_cursor_to_row then
    local winnr = vim.fn.win_findbuf(M.bufnr)
    if winnr and winnr[1] then
      vim.api.nvim_win_set_cursor(winnr[1], { move_cursor_to_row, 0 })
    end
  end
end

local function animate_status()
  M.timer = vim.fn.timer_start(100, function()
    refresh_progress()
    currentFrame = currentFrame % 10 + 1
  end, { ["repeat"] = -1 })
end

function M.start_tests()
  if not M.report then
    return
  end

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      for _, test in ipairs(class.tests) do
        if test.status ~= STATUS_DISABLED then
          target.status = STATUS_RUNNING
          class.status = STATUS_RUNNING
          test.status = STATUS_RUNNING
        end
      end
    end
  end

  if config.animate_status then
    animate_status()
  else
    refresh_progress()
  end
end

function M.finish_tests()
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end

  if not M.report then
    return
  end

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      for _, test in ipairs(class.tests) do
        if test.status == STATUS_RUNNING then
          test.status = STATUS_NOT_EXECUTED
        end
      end

      if class.status == STATUS_RUNNING then
        class.status = get_aggregated_status(class.tests)
      end
    end

    if target.status == STATUS_RUNNING then
      target.status = get_aggregated_status(target.classes)
    end
  end

  refresh_progress()
end

function M.update_test_status(test, status)
  if not M.report then
    return
  end

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      for _, t in ipairs(class.tests) do
        if t.id == test then
          t.status = t.status == STATUS_DISABLED and STATUS_DISABLED or status
          class.status = get_aggregated_status(class.tests)
          target.status = get_aggregated_status(target.classes)

          if status == STATUS_PASSED or status == STATUS_FAILED then
            last_update = t.id
          end

          if not config.animate_status then
            refresh_progress()
          end

          return
        end
      end
    end
  end
end

function M.show(tests)
  M.finish_tests()

  vim.cmd(config.open_command)
  M.bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", true)

  vim.api.nvim_win_set_option(0, "fillchars", "eob: ")
  vim.api.nvim_win_set_option(0, "wrap", false)
  vim.api.nvim_win_set_option(0, "number", false)
  vim.api.nvim_win_set_option(0, "relativenumber", false)
  vim.api.nvim_win_set_option(0, "scl", "no")
  vim.api.nvim_win_set_option(0, "spell", false)

  vim.api.nvim_buf_set_option(M.bufnr, "fileencoding", "utf-8")
  vim.api.nvim_buf_set_option(M.bufnr, "modified", false)
  vim.api.nvim_buf_set_option(M.bufnr, "readonly", false)
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", false)

  generate_report(tests)
  refresh_progress()
end

function M.setup()
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTest", { link = "@function", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerClass", { link = "@type", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTarget", { link = "@keyword", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTestInProgress", { link = "@operator", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTestPassed", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTestFailed", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTestDisabled", { link = "@comment", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestsExplorerTestNotExecuted", { link = "@text", default = true })
end

return M
