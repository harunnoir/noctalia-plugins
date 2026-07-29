--!nonstrict
-- Plumb: a recursive, data-driven selected-text action tree.
--
-- The UI is generated entirely from actions.json. A node with `children` is a
-- folder. A leaf uses one of the built-in types: url, command, copy, or note.

local selectedText = ""
local selectionPath = ""
local keepSelectionPath = false
local rootActions = {}
local navigation = {}
local hovered = nil
local loadWarning = nil

local function shellQuote(value)
  return "'" .. string.gsub(value or "", "'", "'\"'\"'") .. "'"
end

local function trim(value)
  return noctalia.string.trim(value or "")
end

local function replaceLiteral(value, needle, replacement)
  return string.gsub(value, needle, function()
    return replacement
  end)
end

local function actionsFile()
  local configured = noctalia.getConfig("actions_file")
  if type(configured) ~= "string" or configured == "" then
    configured = "~/.config/noctalia/plumb/actions.json"
  end
  return noctalia.expandPath(configured)
end

local function notesFile()
  local configured = noctalia.getConfig("notes_file")
  if type(configured) ~= "string" or configured == "" then
    configured = "~/Notes/Inbox.md"
  end
  return noctalia.expandPath(configured)
end

local function pluginDefaultActionsFile()
  local dir = noctalia.pluginDir()
  if type(dir) ~= "string" or dir == "" then
    return "default-actions.json"
  end
  return dir .. "/default-actions.json"
end

local function currentFrame()
  return navigation[#navigation]
end

local function currentNodes()
  local frame = currentFrame()
  return frame ~= nil and frame.nodes or rootActions
end

local function currentTitle()
  local frame = currentFrame()
  return frame ~= nil and frame.title or "Plumb"
end

local function loadActionTree()
  loadWarning = nil

  local configuredPath = actionsFile()
  local raw, readError = noctalia.readFile(configuredPath)
  local sourcePath = configuredPath

  if raw == nil then
    sourcePath = pluginDefaultActionsFile()
    raw, readError = noctalia.readFile(sourcePath)
    loadWarning = "Could not read the configured actions file; showing the bundled defaults."
  end

  if raw == nil then
    rootActions = {}
    loadWarning = readError or "Could not read any actions file."
    return false
  end

  local decoded, decodeError = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    if sourcePath ~= pluginDefaultActionsFile() then
      local fallback = noctalia.readFile(pluginDefaultActionsFile())
      if fallback ~= nil then
        decoded = noctalia.json.decode(fallback)
        loadWarning = "The configured actions JSON is invalid; showing the bundled defaults."
      end
    end
  end

  if type(decoded) ~= "table" then
    rootActions = {}
    loadWarning = decodeError or "The actions file must contain a JSON array."
    return false
  end

  rootActions = decoded
  return true
end

local function expandUrl(template)
  local expanded = tostring(template or "")
  expanded = replaceLiteral(expanded, "{text}", noctalia.string.urlEncode(selectedText))
  expanded = replaceLiteral(expanded, "{urlencoded}", noctalia.string.urlEncode(selectedText))
  return expanded
end

local function ensureSelectionFile()
  if selectionPath ~= "" and noctalia.fileExists(selectionPath) then
    return selectionPath
  end

  local runtime = noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp"
  local dir = runtime .. "/plumb"
  local made, mkdirError = noctalia.mkdirAll(dir)
  if not made then
    return nil, mkdirError
  end

  local path = dir .. "/selection-command-" .. noctalia.formatTime("%s") .. ".txt"
  local written, writeError = noctalia.writeFile(path, selectedText)
  if not written then
    return nil, writeError
  end

  selectionPath = path
  return path
end

local function expandCommand(template)
  local expanded = tostring(template or "")
  local requiresFile = string.find(expanded, "{file}", 1, true) ~= nil
  local path = selectionPath

  if requiresFile then
    local fileError
    path, fileError = ensureSelectionFile()
    if path == nil then
      return nil, fileError or "Could not create the selection file."
    end
  end

  expanded = replaceLiteral(expanded, "{text}", shellQuote(selectedText))
  expanded = replaceLiteral(expanded, "{urlencoded}", noctalia.string.urlEncode(selectedText))
  expanded = replaceLiteral(expanded, "{file}", shellQuote(path or ""))

  return expanded, nil, requiresFile
end

local function openUrl(url)
  if url == "" then
    noctalia.notifyError("Plumb", "This action has no URL.")
    return
  end

  if not noctalia.commandExists("xdg-open") then
    noctalia.notifyError("Plumb", "xdg-open is missing. Install xdg-utils.")
    return
  end

  local launched = noctalia.runAsync("xdg-open " .. shellQuote(url))
  if not launched then
    noctalia.notifyError("Plumb", "Could not open the URL.")
    return
  end

  panel.close()
end

local function copySelection()
  if noctalia.copyToClipboard(selectedText, "text/plain") then
    noctalia.notify("Plumb", "Selected text copied.")
    panel.close()
  else
    noctalia.notifyError("Plumb", "Could not copy the selected text.")
  end
end

local function saveNote()
  local path = notesFile()
  local parent = string.match(path, "^(.*)/[^/]+$")

  if parent ~= nil and parent ~= "" then
    local made, mkdirError = noctalia.mkdirAll(parent)
    if not made then
      noctalia.notifyError("Plumb", mkdirError or "Could not create the notes directory.")
      return
    end
  end

  local existing, readError = noctalia.readFile(path)
  if existing == nil then
    if noctalia.fileExists(path) then
      noctalia.notifyError("Plumb", readError or "Could not read the notes file.")
      return
    end
    existing = ""
  end

  local separator = existing ~= "" and "\n\n" or ""
  local entry = separator
    .. "## " .. noctalia.formatTime("yyyy-MM-dd HH:mm")
    .. "\n\n" .. selectedText .. "\n"

  local written, writeError = noctalia.writeFile(path, existing .. entry)
  if not written then
    noctalia.notifyError("Plumb", writeError or "Could not save the note.")
    return
  end

  noctalia.notify("Plumb", "Saved to " .. path)
  panel.close()
end

local function runCommand(node)
  local template = node.command or node.value
  if type(template) ~= "string" or template == "" then
    noctalia.notifyError("Plumb", "This command action has no command.")
    return
  end

  local command, expandError, usesFile = expandCommand(template)
  if command == nil then
    noctalia.notifyError("Plumb", expandError or "Could not prepare the command.")
    return
  end

  if usesFile then
    keepSelectionPath = true
    command = "(" .. command .. "); status=$?; rm -f -- " .. shellQuote(selectionPath) .. "; exit $status"
  end

  local launched = noctalia.runAsync(command)
  if not launched then
    keepSelectionPath = false
    noctalia.notifyError("Plumb", "Could not start the command.")
    return
  end

  if node.notify ~= false then
    noctalia.notify("Plumb", node.message or ("Ran " .. tostring(node.label or "command")))
  end

  if node.close ~= false then
    panel.close()
  end
end

local function executeNode(node)
  if type(node) ~= "table" then
    return
  end

  if type(node.children) == "table" then
    table.insert(navigation, {
      title = tostring(node.label or "Folder"),
      nodes = node.children,
    })
    hovered = nil
    render()
    return
  end

  local kind = tostring(node.type or node.action or "")

  if kind == "url" or kind == "open_url" then
    openUrl(expandUrl(node.url or node.value))
  elseif kind == "command" then
    runCommand(node)
  elseif kind == "copy" then
    copySelection()
  elseif kind == "note" or kind == "save_note" then
    saveNote()
  else
    noctalia.notifyError("Plumb", "Unknown action type: " .. (kind ~= "" and kind or "missing"))
  end
end

local function header()
  local children = {}

  if #navigation > 1 then
    table.insert(children, ui.button({
      glyph = "arrow-left",
      variant = "ghost",
      tooltip = "Back",
      onClick = function()
        table.remove(navigation)
        hovered = nil
        render()
      end,
    }))
  end

  table.insert(children, ui.column({ flexGrow = 1, gap = 1 }, {
    ui.label({
      text = currentTitle(),
      fontSize = 17,
      fontWeight = "bold",
      color = "on_surface",
      maxLines = 1,
    }),
    ui.label({
      text = #navigation > 1 and "Plumb / " .. currentTitle() or "Selected-text actions",
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 1,
    }),
  }))

  table.insert(children, ui.button({
    glyph = "refresh",
    variant = "ghost",
    tooltip = "Reload actions.json",
    onClick = function()
      loadActionTree()
      navigation = { { title = "Plumb", nodes = rootActions } }
      hovered = nil
      render()
    end,
  }))

  table.insert(children, ui.button({
    glyph = "close",
    variant = "ghost",
    tooltip = "Close",
    onClick = function()
      panel.close()
    end,
  }))

  return ui.row({ align = "center", gap = 8 }, children)
end

local function preview()
  return ui.column({
    gap = 5,
    padding = 11,
    fill = "surface_variant/0.28",
    radius = 11,
    border = "outline/0.22",
    borderWidth = 1,
  }, {
    ui.row({ align = "center", gap = 7 }, {
      ui.glyph({ name = "text-caption", size = 15, color = "primary" }),
      ui.label({ text = "Selected text", fontSize = 10, fontWeight = "medium", color = "on_surface_variant" }),
    }),
    ui.label({
      text = selectedText ~= "" and selectedText or "No readable text was supplied.",
      fontSize = 12,
      color = selectedText ~= "" and "on_surface" or "error",
      maxLines = 3,
    }),
  })
end

local function actionRow(node, index)
  local label = tostring(node.label or ("Action " .. tostring(index)))
  local isFolder = type(node.children) == "table"
  local key = tostring(#navigation) .. ":" .. tostring(index) .. ":" .. label
  local active = hovered == key
  local icon = tostring(node.icon or (isFolder and "folder" or "bolt"))
  local description = type(node.description) == "string" and node.description or nil
  local rowChildren = {
    ui.glyph({
      name = icon,
      size = 21,
      color = active and "primary" or (isFolder and "primary" or "on_surface"),
    }),
    ui.column({ flexGrow = 1, gap = 2 }, {
      ui.label({
        text = label,
        fontSize = 13,
        fontWeight = "medium",
        color = "on_surface",
        maxLines = 1,
      }),
      ui.label({
        text = description or (isFolder and tostring(#node.children) .. " actions" or tostring(node.type or node.action or "action")),
        fontSize = 10,
        color = "on_surface_variant",
        maxLines = 1,
      }),
    }),
  }

  if isFolder then
    table.insert(rowChildren, ui.glyph({ name = "chevron-right", size = 17, color = "on_surface_variant" }))
  end

  return ui.row({
    key = key,
    minHeight = 54,
    paddingH = 12,
    paddingV = 8,
    gap = 11,
    align = "center",
    fill = active and "primary/0.13" or "surface_variant/0.32",
    radius = 11,
    border = active and "primary/0.60" or "outline/0.20",
    borderWidth = 1,
    onClick = function()
      executeNode(node)
    end,
    onHover = function(state)
      hovered = state == "true" and key or nil
      render()
    end,
  }, rowChildren)
end

local function actionList()
  local rows = {}
  local nodes = currentNodes()

  for index, node in ipairs(nodes) do
    if type(node) == "table" and node.hidden ~= true then
      table.insert(rows, actionRow(node, index))
    end
  end

  if #rows == 0 then
    table.insert(rows, ui.column({
      padding = 18,
      gap = 8,
      align = "center",
      fill = "surface_variant/0.24",
      radius = 12,
    }, {
      ui.glyph({ name = "folder-off", size = 28, color = "on_surface_variant" }),
      ui.label({ text = "This folder has no visible actions.", color = "on_surface_variant" }),
    }))
  end

  return ui.scroll({ flexGrow = 1, gap = 8 }, rows)
end

function render()
  local children = {
    header(),
    preview(),
  }

  if loadWarning ~= nil then
    table.insert(children, ui.row({
      gap = 7,
      align = "center",
      paddingH = 10,
      paddingV = 7,
      fill = "error/0.10",
      radius = 9,
    }, {
      ui.glyph({ name = "alert-triangle", size = 15, color = "error" }),
      ui.label({ text = loadWarning, fontSize = 10, color = "error", maxLines = 2, flexGrow = 1 }),
    }))
  end

  table.insert(children, actionList())
  panel.render(ui.column({ flexGrow = 1, gap = 11 }, children))
end

function onOpen(context)
  hovered = nil
  keepSelectionPath = false
  selectionPath = type(context) == "string" and context or ""

  local text = nil
  if selectionPath ~= "" then
    text = noctalia.readFile(selectionPath)
  end

  if text == nil or text == "" then
    text = noctalia.clipboardText() or ""
  end

  selectedText = trim(text)
  loadActionTree()
  navigation = { { title = "Plumb", nodes = rootActions } }
  render()
end

function onClose()
  if not keepSelectionPath
    and selectionPath ~= ""
    and string.match(selectionPath, "/plumb/selection[%w%-_]*%.txt$")
  then
    noctalia.removeFile(selectionPath)
  end

  selectedText = ""
  selectionPath = ""
  keepSelectionPath = false
  rootActions = {}
  navigation = {}
  hovered = nil
  loadWarning = nil
end
