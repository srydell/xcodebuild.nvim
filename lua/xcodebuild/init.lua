local M = {}

local function call(action, args)
  return function()
    action(args)
  end
end

local function setupHighlights()
  local highlights = require("xcodebuild.core.config").options.highlights or {}

  for hl, color in pairs(highlights) do
    if type(color) == "table" then
      vim.api.nvim_set_hl(0, hl, color)
    elseif vim.startswith(color, "#") then
      vim.api.nvim_set_hl(0, hl, { fg = color })
    else
      vim.api.nvim_set_hl(0, hl, { link = color })
    end
  end
end

local function warnAboutOldConfig()
  local config = require("xcodebuild.core.config").options

  if
    config.code_coverage.covered
    or config.code_coverage.partially_covered
    or config.code_coverage.not_covered
    or config.code_coverage.not_executable
    or config.code_coverage_report.ok_level_hl_group
    or config.code_coverage_report.warning_level_hl_group
    or config.code_coverage_report.error_level_hl_group
    or config.marks.success_sign_hl
    or config.marks.failure_sign_hl
    or config.marks.success_test_duration_hl
    or config.marks.failure_test_duration_hl
  then
    print("xcodebuild.nvim: Code coverage and marks options related to higlights were changed.")
    print("xcodebuild.nvim: Please see README.md and update your config.")
  end
end

-- stylua: ignore start
function M.setup(options)
  require("xcodebuild.core.config").setup(options)

  local autocmd = require("xcodebuild.core.autocmd")
  local actions = require("xcodebuild.actions")
  local projectConfig = require("xcodebuild.project.config")
  local coverage = require("xcodebuild.code_coverage.coverage")
  local coverageReport = require("xcodebuild.code_coverage.coverage_report")
  local testExplorer = require("xcodebuild.tests.explorer")
  local diagnostics = require("xcodebuild.core.diagnostics")
  local nvimTree = require("xcodebuild.integrations.nvim-tree")

  autocmd.setup()
  projectConfig.load_settings()
  diagnostics.setup()
  coverage.setup()
  coverageReport.setup()
  testExplorer.setup()
  nvimTree.setup()
  setupHighlights()
  warnAboutOldConfig()

  -- Build
  vim.api.nvim_create_user_command("XcodebuildBuild", call(actions.build), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCleanBuild", call(actions.clean_build), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBuildRun", call(actions.build_and_run), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBuildForTesting", call(actions.build_for_testing), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildRun", call(actions.run), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCancel", call(actions.cancel), { nargs = 0 })

  -- Testing
  vim.api.nvim_create_user_command("XcodebuildTest", call(actions.run_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestTarget", call(actions.run_target_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestClass", call(actions.run_class_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestFunc", call(actions.run_func_test), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestSelected", call(actions.run_selected_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestFailing", call(actions.run_failing_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildFailingSnapshots", call(actions.show_failing_snapshot_tests), { nargs = 0 })

  -- Coverage
  vim.api.nvim_create_user_command("XcodebuildToggleCodeCoverage", call(actions.toggle_code_coverage), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildShowCodeCoverageReport", call(actions.show_code_coverage_report), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildJumpToNextCoverage", call(actions.jump_to_next_coverage), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildJumpToPrevCoverage", call(actions.jump_to_previous_coverage), { nargs = 0 })

  -- Test Explorer
  vim.api.nvim_create_user_command("XcodebuildTestExplorerShow", call(actions.test_explorer_show), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerHide", call(actions.test_explorer_hide), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerToggle", call(actions.test_explorer_toggle), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerRunSelectedTests", call(actions.test_explorer_run_selected_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerRerunTests", call(actions.test_explorer_rerun_tests), { nargs = 0 })

  -- Pickers
  vim.api.nvim_create_user_command("XcodebuildSetup", call(actions.configure_project), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildPicker", call(actions.show_picker), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectProject", call(actions.select_project), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectScheme", call(actions.select_scheme), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectConfig", call(actions.select_config), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectDevice", call(actions.select_device), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectTestPlan", call(actions.select_testplan), { nargs = 0 })

  -- Logs
  vim.api.nvim_create_user_command("XcodebuildToggleLogs", call(actions.toggle_logs), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildOpenLogs", call(actions.open_logs), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCloseLogs", call(actions.close_logs), { nargs = 0 })

  -- Project Manager
  vim.api.nvim_create_user_command("XcodebuildProjectManager", call(actions.show_project_manager_actions), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCreateNewFile", call(actions.create_new_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildAddCurrentFile", call(actions.add_current_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildDeleteCurrentFile", call(actions.delete_current_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildRenameCurrentFile", call(actions.rename_current_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCreateNewGroup", call(actions.create_new_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildAddCurrentGroup", call(actions.add_current_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildRenameCurrentGroup", call(actions.rename_current_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildDeleteCurrentGroup", call(actions.delete_current_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildUpdateCurrentFileTargets", call(actions.update_current_file_targets), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildShowCurrentFileTargets", call(actions.show_current_file_targets), { nargs = 0 })

  -- Other
  vim.api.nvim_create_user_command("XcodebuildShowConfig", call(actions.show_current_config), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBootSimulator", call(actions.boot_simulator), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCleanDerivedData", call(actions.clean_derived_data), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildInstallApp", call(actions.install_app), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildUninstallApp", call(actions.uninstall_app), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildOpenInXcode", call(actions.open_in_xcode), { nargs = 0 })

  -- Backward compatibility
  vim.api.nvim_create_user_command("XcodebuildUninstall", call(actions.uninstall), { nargs = 0 })
end

return M
