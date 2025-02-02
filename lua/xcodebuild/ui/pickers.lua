local xcode = require("xcodebuild.core.xcode")
local projectConfig = require("xcodebuild.project.config")
local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local snapshots = require("xcodebuild.tests.snapshots")
local events = require("xcodebuild.broadcasting.events")
local deviceProxy = require("xcodebuild.platform.device_proxy")

local telescopePickers = require("telescope.pickers")
local telescopeFinders = require("telescope.finders")
local telescopeConfig = require("telescope.config").values
local telescopeActions = require("telescope.actions")
local telescopeState = require("telescope.actions.state")
local telescopeActionsUtils = require("telescope.actions.utils")

local M = {}

local cachedDestinations = {}
local cachedDeviceNames = {}
local currentJobId = nil
local activePicker = nil
local progressTimer = nil
local currentProgressFrame = 1
local progressFrames = {
  "[      ]",
  "[ .    ]",
  "[ ..   ]",
  "[ ...  ]",
  "[  ... ]",
  "[   .. ]",
  "[    . ]",
}

local function stop_telescope_spinner()
  if progressTimer then
    vim.fn.timer_stop(progressTimer)
    progressTimer = nil
  end
end

local function update_telescope_spinner()
  if activePicker and vim.api.nvim_win_is_valid(activePicker.results_win) then
    currentProgressFrame = currentProgressFrame >= #progressFrames and 1 or currentProgressFrame + 1
    activePicker:change_prompt_prefix(progressFrames[currentProgressFrame] .. " ", "TelescopePromptPrefix")
  else
    stop_telescope_spinner()
  end
end

local function start_telescope_spinner()
  if not progressTimer then
    progressTimer = vim.fn.timer_start(80, update_telescope_spinner, { ["repeat"] = -1 })
  end
end

local function update_results(results)
  if currentJobId == nil then
    return
  end

  stop_telescope_spinner()

  if activePicker then
    activePicker:refresh(
      telescopeFinders.new_table({
        results = results,
      }),
      {
        new_prefix = telescopeConfig.prompt_prefix,
      }
    )
  end
end

function M.show(title, items, callback, opts)
  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end

  opts = opts or {}

  activePicker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
    }),
    sorter = telescopeConfig.generic_sorter(),
    file_ignore_patterns = {},
    attach_mappings = function(prompt_bufnr, _)
      if opts.on_refresh ~= nil then
        vim.keymap.set({ "n", "i" }, "<C-r>", function()
          start_telescope_spinner()
          opts.on_refresh()
        end, { silent = true, buffer = prompt_bufnr })
      end

      telescopeActions.select_default:replace(function()
        local selection = telescopeState.get_selected_entry()

        local results = {}
        if opts.multiselect then
          telescopeActionsUtils.map_selections(prompt_bufnr, function(sel)
            table.insert(results, sel[1])
          end)

          if util.is_empty(results) and selection then
            table.insert(results, selection[1])
          end
        end

        if opts and opts.close_on_select and selection then
          telescopeActions.close(prompt_bufnr)
        end

        if callback and selection then
          if opts.multiselect then
            callback(results)
          else
            callback(selection[1], selection.index)
          end
        end
      end)
      return true
    end,
  })

  activePicker:find()
end

function M.select_xcodeproj_if_needed(callback, opts)
  if projectConfig.settings.xcodeproj then
    if callback then
      callback(projectConfig.settings.xcodeproj)
    end
    return
  end

  local projectFile = projectConfig.settings.projectFile
  local xcodeproj = string.gsub(projectFile, ".xcworkspace", ".xcodeproj")

  if util.file_exists(xcodeproj) then
    projectConfig.settings.xcodeproj = xcodeproj
    projectConfig.save_settings()

    if callback then
      callback(xcodeproj)
    end
  else
    M.select_xcodeproj(callback, opts)
  end
end

function M.select_xcodeproj(callback, opts)
  local maxdepth = require("xcodebuild.core.config").options.commands.project_search_max_depth
  local sanitizedFiles = {}
  local filenames = {}
  local files = util.shell(
    "find '"
      .. vim.fn.getcwd()
      .. "' -maxdepth "
      .. maxdepth
      .. " -iname '*.xcodeproj'"
      .. " -not -path '*/.*'"
      .. " 2>/dev/null"
  )

  for _, file in ipairs(files) do
    if util.trim(file) ~= "" then
      table.insert(sanitizedFiles, file)
      table.insert(filenames, string.match(file, ".*%/([^/]*)$"))
    end
  end

  M.show("Select Project", filenames, function(_, index)
    local selectedFile = sanitizedFiles[index]

    projectConfig.settings.xcodeproj = selectedFile
    projectConfig.save_settings()

    if callback then
      callback(selectedFile)
    end
  end, opts)
end

function M.select_project(callback, opts)
  local maxdepth = require("xcodebuild.core.config").options.commands.project_search_max_depth
  local sanitizedFiles = {}
  local filenames = {}
  local files = util.shell(
    "find '"
      .. vim.fn.getcwd()
      .. "' \\( -iname '*.xcodeproj' -o -iname '*.xcworkspace' \\)"
      .. " -not -path '*/.*' -not -path '*xcodeproj/project.xcworkspace'"
      .. " -maxdepth "
      .. maxdepth
      .. " 2>/dev/null"
  )

  for _, file in ipairs(files) do
    if util.trim(file) ~= "" then
      table.insert(sanitizedFiles, file)
      table.insert(filenames, string.match(file, ".*%/([^/]*)$"))
    end
  end

  M.show("Select Main Xcworkspace or Xcodeproj", filenames, function(_, index)
    local projectFile = sanitizedFiles[index]
    local isWorkspace = util.has_suffix(projectFile, "xcworkspace")

    projectConfig.settings.xcodeproj = not isWorkspace and projectFile
    projectConfig.settings.projectFile = projectFile
    projectConfig.settings.projectCommand = (isWorkspace and "-workspace '" or "-project '")
      .. projectFile
      .. "'"

    projectConfig.save_settings()

    if callback then
      callback(projectFile)
    end
  end, opts)
end

function M.select_scheme(schemes, callback, opts)
  if util.is_empty(schemes) then
    start_telescope_spinner()
  end

  M.show("Select Scheme", schemes, function(value, _)
    projectConfig.settings.scheme = value
    projectConfig.save_settings()

    if callback then
      callback(value)
    end
  end, opts)

  if util.is_empty(schemes) then
    local xcodeproj = projectConfig.settings.xcodeproj
    currentJobId = xcode.get_project_information(xcodeproj, function(info)
      update_results(info.schemes)
    end)

    return currentJobId
  end
end

function M.select_config(callback, opts)
  local xcodeproj = projectConfig.settings.xcodeproj
  local projectInfo = nil

  start_telescope_spinner()
  M.show("Select Build Configuration", {}, function(value, _)
    projectConfig.settings.config = value
    projectConfig.save_settings()

    if callback then
      callback(projectInfo)
    end
  end, opts)

  currentJobId = xcode.get_project_information(xcodeproj, function(info)
    projectInfo = info
    update_results(info.configs)
  end)

  return currentJobId
end

function M.select_testplan(callback, opts)
  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme

  start_telescope_spinner()
  M.show("Select Test Plan", {}, function(value, _)
    projectConfig.settings.testPlan = value
    projectConfig.save_settings()
    events.project_settings_updated(projectConfig.settings)

    if callback then
      callback(value)
    end
  end, opts)

  currentJobId = xcode.get_testplans(projectCommand, scheme, function(testPlans)
    if currentJobId and util.is_empty(testPlans) then
      vim.defer_fn(function()
        notifications.send_warning("Could not detect test plans")
      end, 100)

      if activePicker and util.is_not_empty(vim.fn.win_findbuf(activePicker.prompt_bufnr)) then
        telescopeActions.close(activePicker.prompt_bufnr)
      end

      if callback then
        callback()
      end
    else
      update_results(testPlans)
    end
  end)

  return currentJobId
end

function M.select_destination(callback, opts)
  opts = opts or {}

  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme
  local results = cachedDestinations or {}
  local useCache = require("xcodebuild.core.config").options.commands.cache_devices
  local hasCachedDevices = useCache and util.is_not_empty(results) and util.is_not_empty(cachedDeviceNames)

  local refreshDevices = function(connectedDevices)
    currentJobId = xcode.get_destinations(projectCommand, scheme, function(destinations)
      for _, device in ipairs(connectedDevices) do
        table.insert(destinations, 1, device)
      end

      local alreadyAdded = {}
      local filtered = util.filter(destinations, function(table)
        if table.id and not alreadyAdded[table.id] then
          alreadyAdded[table.id] = true

          return (not table.name or not string.find(table.name, "^Any")) and not table.error
        end
      end)

      local destinationNames = util.select(filtered, function(table)
        local name = table.name or ""

        if table.platform and table.platform == "iOS" then
          return util.trim(name) .. (table.os and " (" .. table.os .. ")" or "")
        end

        if table.platform and table.platform ~= "iOS Simulator" then
          name = util.trim(name .. " " .. table.platform)
        end
        if table.platform == "macOS" and table.arch then
          name = name .. " (" .. table.arch .. ")"
        end
        if table.os then
          name = name .. " (" .. table.os .. ")"
        end
        if table.variant then
          name = name .. " (" .. table.variant .. ")"
        end
        if table.error then
          name = name .. " [error]"
        end
        return name
      end)

      if useCache then
        cachedDeviceNames = destinationNames
        cachedDestinations = filtered
      end

      results = filtered
      update_results(destinationNames)
    end)

    return currentJobId
  end

  local function getConnectedDevices()
    if not deviceProxy.is_installed() then
      return refreshDevices({})
    end

    return deviceProxy.get_connected_devices(refreshDevices)
  end

  if not hasCachedDevices then
    start_telescope_spinner()
  end

  opts.on_refresh = getConnectedDevices

  M.show("Select Device", cachedDeviceNames or {}, function(_, index)
    projectConfig.settings.destination = results[index].id
    projectConfig.settings.platform = results[index].platform
    projectConfig.settings.deviceName = results[index].name
    projectConfig.settings.os = results[index].os
    projectConfig.save_settings()

    if callback then
      callback(results[index])
    end
  end, opts)

  if not hasCachedDevices then
    return getConnectedDevices()
  end
end

function M.select_failing_snapshot_test()
  local failingSnapshots = snapshots.get_failing_snapshots()
  local filenames = util.select(failingSnapshots, function(item)
    return util.get_filename(item)
  end)

  require("xcodebuild.ui.pickers").show("Failing Snapshot Tests", filenames, function(_, index)
    local selectedFile = failingSnapshots[index]
    vim.fn.jobstart("qlmanage -p '" .. selectedFile .. "'", {
      detach = true,
      on_exit = function() end,
    })
  end)
end

function M.show_all_actions()
  local actions = require("xcodebuild.actions")
  local actionsNames = {
    "Build Project",
    "Build Project (Clean Build)",
    "Build & Run Project",
    "Build For Testing",
    "Run Without Building",
    "Cancel Running Action",

    "Run Test Plan (All Tests)",
    "Run This Test Target",
    "Run This Test Class",
    "Run This Test",
    "Run Selected Tests",
    "Run Failed Tests",

    "Select Project File",
    "Select Scheme",
    "Select Build Configuration",
    "Select Device",
    "Select Test Plan",

    "Toggle Logs",
    "Show Project Manager",
    "Show Current Configuration",
    "Show Configuration Wizard",
    "Boot Selected Simulator",
    "Clean DerivedData",
    "Install Application",
    "Uninstall Application",
    "Open Project in Xcode",
  }
  local actionsPointers = {
    actions.build,
    actions.clean_build,
    actions.build_and_run,
    actions.build_for_testing,
    actions.run,
    actions.cancel,

    actions.run_tests,
    actions.run_target_tests,
    actions.run_class_tests,
    actions.run_func_test,
    actions.run_selected_tests,
    actions.run_failing_tests,

    actions.select_project,
    actions.select_scheme,
    actions.select_config,
    actions.select_device,
    actions.select_testplan,

    actions.toggle_logs,
    actions.show_project_manager_actions,
    actions.show_current_config,
    actions.configure_project,
    actions.boot_simulator,
    actions.clean_derived_data,
    actions.install_app,
    actions.uninstall_app,
    actions.open_in_xcode,
  }

  if not projectConfig.is_project_configured() then
    actionsNames = { "Show Configuration Wizard" }
    actionsPointers = { actions.configure_project }
  end

  local config = require("xcodebuild.core.config").options

  if config.prepare_snapshot_test_previews then
    if util.is_not_empty(snapshots.get_failing_snapshots()) then
      table.insert(actionsNames, 13, "Preview Failing Snapshot Tests")
      table.insert(actionsPointers, 13, actions.show_failing_snapshot_tests)
    end
  end

  if config.code_coverage.enabled then
    table.insert(actionsNames, 13, "Toggle Code Coverage")
    table.insert(actionsPointers, 13, actions.toggle_code_coverage)

    if require("xcodebuild.code_coverage.coverage_report").is_report_available() then
      table.insert(actionsNames, 14, "Show Code Coverage Report")
      table.insert(actionsPointers, 14, actions.show_code_coverage_report)
    end
  end

  if config.test_explorer.enabled then
    local row = util.indexOf(actionsNames, "Toggle Logs")
    if row then
      table.insert(actionsNames, row + 1, "Toggle Test Explorer")
      table.insert(actionsPointers, row + 1, actions.test_explorer_toggle)
    end
  end

  M.show("Xcodebuild Actions", actionsNames, function(_, index)
    if index > 12 or #actionsNames == 1 then
      actionsPointers[index]()
    else
      vim.defer_fn(actionsPointers[index], 100)
    end
  end, { close_on_select = true })
end

return M
