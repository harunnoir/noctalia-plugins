--!nonstrict
-- Plumb: selected-text action palette for Noctalia v5.
-- The panel snapshots the Wayland primary selection when it opens, then keeps
-- every action inside the plugin: no separately installed plumb script needed.

local selection = ""
local selectionType = "text"
local selectedPath = nil
local page = "main"
local query = ""
local selectedIndex = 1
local searchKey = 0
local searchWantsFocus = false
local editKey = 0
local editText = ""
local loading = false
local status = ""
local helpVisible = false
local visibleActions = {}
local render

local favorites = {}
local lastAction = ""
local dataPath = nil

local SEARCH_ENGINES = {
  { id = "duckduckgo", name = "DuckDuckGo", glyph = "shield-search", base = "https://duckduckgo.com/?q=", tags = "ddg private privacy duck" },
  { id = "google", name = "Google", glyph = "brand-google", base = "https://www.google.com/search?q=", tags = "google web" },
  { id = "brave", name = "Brave Search", glyph = "shield", base = "https://search.brave.com/search?q=", tags = "brave private privacy" },
  { id = "startpage", name = "Startpage", glyph = "shield-lock", base = "https://www.startpage.com/sp/search?query=", tags = "startpage private privacy" },
  { id = "wikipedia", name = "Wikipedia", glyph = "brand-wikipedia", base = "https://en.wikipedia.org/w/index.php?search=", tags = "wiki encyclopedia knowledge" },
  { id = "github", name = "GitHub", glyph = "brand-github", base = "https://github.com/search?q=", tags = "github code repository programming" },
  { id = "stackoverflow", name = "Stack Overflow", glyph = "brand-stackoverflow", base = "https://stackoverflow.com/search?q=", tags = "stackoverflow error programming debug" },
  { id = "youtube", name = "YouTube", glyph = "brand-youtube", base = "https://www.youtube.com/results?search_query=", tags = "youtube video" },
  { id = "reddit", name = "Reddit", glyph = "brand-reddit", base = "https://www.reddit.com/search/?q=", tags = "reddit discussion community" },
}

local LANGUAGES = {
  { code = "ar", name = "Arabic", tags = "arabic ar العربية" },
  { code = "en", name = "English", tags = "english en" },
  { code = "fr", name = "French", tags = "french fr français" },
  { code = "es", name = "Spanish", tags = "spanish es español" },
  { code = "de", name = "German", tags = "german de deutsch" },
  { code = "ja", name = "Japanese", tags = "japanese ja 日本語" },
}

local function trim(value)
  if value == nil then return "" end
  return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(value)
  return string.lower(tostring(value or ""))
end

local function shellQuote(value)
  return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function urlEncode(value)
  return tostring(value or ""):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "."
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function preview(value, limit)
  local text = trim(value):gsub("[%s\n\r\t]+", " ")
  local maxLength = limit or 220
  if #text > maxLength then
    return text:sub(1, maxLength - 1) .. "…"
  end
  return text
end

local function quoteMarkdown(value)
  local text = trim(value)
  if text == "" then return "" end
  return "> " .. text:gsub("\n", "\n> ")
end

local function cleanError(value)
  local text = tostring(value or "")
  text = text:gsub("\27%[[0-9;]*m", "")
  text = text:gsub("/home/[%w%._%-%+/]+", "<path>")
  text = text:gsub(":%d+:%d+", "")
  text = text:gsub("^%s*%d%d%d%d%-%d%d%-%d%d[T ]%d%d:%d%d:%d%d[%w%p]*%s*", "")
  text = trim(text)
  if #text > 700 then text = text:sub(1, 700) end
  return text
end

local function domainFromUrl(value)
  return tostring(value or ""):match("^https?://([^/%?#]+)")
end

local function resolvePath(value)
  local raw = trim(value)
  if raw == "" then return nil end

  local path = raw
  local withLine = raw:match("^(.-):%d+:%d+$") or raw:match("^(.-):%d+$")
  if withLine ~= nil and withLine ~= "" then path = withLine end

  if path:sub(1, 7) == "file://" then path = path:sub(8) end
  path = noctalia.expandPath(path)
  if noctalia.fileExists(path) then return path end
  return nil
end

local function detectType(value)
  local text = trim(value)
  selectedPath = resolvePath(text)
  if selectedPath ~= nil then return "file" end
  if text:match("^https?://") or text:match("^ftp://") or text:match("^magnet:") then return "url" end
  if text:match("^[%w%._%%+%-]+@[%w%.%-]+%.[%a]+$") then return "email" end

  local lowered = lower(text)
  if lowered:find("traceback", 1, true)
      or lowered:find("exception", 1, true)
      or lowered:find("segmentation fault", 1, true)
      or lowered:find("stack trace", 1, true)
      or lowered:find("error:", 1, true)
      or lowered:find("failed:", 1, true)
      or lowered:find("panic:", 1, true) then
    return "error"
  end

  if text:find("\n", 1, true) and (
      text:match("[%{%};]")
      or text:match("^%s*def%s+")
      or text:match("^%s*class%s+")
      or text:match("^%s*function%s+")
      or text:match("^%s*local%s+")
      or text:match("^%s*import%s+")
      or text:match("^%s*#include%s+")
    ) then
    return "code"
  end

  return "text"
end

local function config(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then return fallback end
  return value
end

local function persistState()
  if dataPath == nil then return end
  local ok, encoded = pcall(function()
    return noctalia.json.encode({ favorites = favorites, lastAction = lastAction })
  end)
  if ok and encoded ~= nil then
    noctalia.writeFile(dataPath, encoded)
  end
end

local function loadState()
  local dir = noctalia.pluginDataDir()
  if dir == nil then return end
  dataPath = dir .. "/state.json"
  local raw = noctalia.readFile(dataPath)
  if raw == nil or raw == "" then return end

  local ok, decoded = pcall(function() return noctalia.json.decode(raw) end)
  if not ok or type(decoded) ~= "table" then return end
  if type(decoded.favorites) == "table" then favorites = decoded.favorites end
  if type(decoded.lastAction) == "string" then lastAction = decoded.lastAction end
end

loadState()

local function finish(message)
  status = message or "Done"
  if config("close_after_action", true) == true then
    panel.close()
  else
    render()
  end
end

local function openUri(uri)
  local command
  if noctalia.commandExists("xdg-open") then
    command = "xdg-open " .. shellQuote(uri)
  elseif noctalia.commandExists("gio") then
    command = "gio open " .. shellQuote(uri)
  else
    noctalia.notifyError("Plumb", "Install xdg-utils, or provide gio.")
    return false
  end

  if not noctalia.runAsync(command) then
    noctalia.notifyError("Plumb", "Could not launch the URI opener.")
    return false
  end
  return true
end

local function engineById(id)
  for _, engine in ipairs(SEARCH_ENGINES) do
    if engine.id == id then return engine end
  end
  return SEARCH_ENGINES[1]
end

local function languageByCode(code)
  for _, language in ipairs(LANGUAGES) do
    if language.code == code then return language end
  end
  return LANGUAGES[1]
end

local function runSearch(engineId, text, exact)
  local engine = engineById(engineId)
  local searchText = trim(text)
  if exact then searchText = '"' .. searchText .. '"' end
  if openUri(engine.base .. urlEncode(searchText)) then
    finish("Opened " .. engine.name)
  end
end

local function runTranslation(provider, targetCode)
  local language = languageByCode(targetCode)
  local uri
  if provider == "deepl" then
    uri = "https://www.deepl.com/translator#auto/" .. targetCode .. "/" .. urlEncode(selection)
  else
    uri = "https://translate.google.com/?sl=auto&tl=" .. targetCode .. "&text=" .. urlEncode(selection) .. "&op=translate"
  end
  if openUri(uri) then
    finish("Opened " .. language.name .. " translation")
  end
end

local function appendFile(path, content)
  local expanded = noctalia.expandPath(path)
  local parent = dirname(expanded)
  local made, makeError = noctalia.mkdirAll(parent)
  if not made then
    noctalia.notifyError("Plumb", "Could not create notes directory: " .. tostring(makeError or parent))
    return false
  end

  local existing = noctalia.readFile(expanded) or ""
  if existing ~= "" and existing:sub(-1) ~= "\n" then existing = existing .. "\n" end
  local ok, writeError = noctalia.writeFile(expanded, existing .. content)
  if not ok then
    noctalia.notifyError("Plumb", "Could not save note: " .. tostring(writeError or expanded))
    return false
  end
  return true
end

local function noteEntry(kind)
  local timestamp = noctalia.formatTime("%Y-%m-%d %H:%M")
  local body = trim(selection)
  if kind == "quote" then
    body = quoteMarkdown(body)
  elseif kind == "code" then
    body = "```\n" .. body .. "\n```"
  end
  return "## Selection — " .. timestamp .. "\n\n" .. body .. "\n\n"
end

local function saveNote(kind)
  if kind == "daily" then
    local folder = config("daily_notes_dir", "~/.local/share/plumb/daily")
    local filename = noctalia.formatTime("%Y-%m-%d") .. ".md"
    local path = noctalia.expandPath(folder) .. "/" .. filename
    local entry = "\n### " .. noctalia.formatTime("%H:%M") .. "\n\n" .. trim(selection) .. "\n"
    if appendFile(path, entry) then
      finish("Saved to " .. filename)
    end
    return
  end

  local path = config("notes_file", "~/.local/share/plumb/notes.md")
  if appendFile(path, noteEntry(kind)) then
    finish("Saved to " .. basename(noctalia.expandPath(path)))
  end
end

local function copyText(value, message)
  if noctalia.copyToClipboard(value, "text/plain") then
    finish(message or "Copied")
  else
    noctalia.notifyError("Plumb", "Could not copy to the clipboard.")
  end
end

local function setPage(nextPage)
  page = nextPage
  query = ""
  selectedIndex = 1
  searchWantsFocus = false
  searchKey = searchKey + 1
  helpVisible = false
  render()
end

local function rememberAction(id)
  lastAction = id
  persistState()
end

local function performAction(id, repeating)
  if id == nil or id == "" then return end

  if id == "copy" then
    if not repeating then rememberAction(id) end
    copyText(selection, "Selection copied")
    return
  elseif id == "copy-quote" then
    if not repeating then rememberAction(id) end
    copyText(quoteMarkdown(selection), "Markdown quote copied")
    return
  elseif id == "copy-domain" then
    local domain = domainFromUrl(selection)
    if domain ~= nil then
      if not repeating then rememberAction(id) end
      copyText(domain, "Domain copied")
    end
    return
  elseif id == "open" then
    if not repeating then rememberAction(id) end
    local target = selection
    if selectionType == "email" then target = "mailto:" .. selection end
    if selectionType == "file" and selectedPath ~= nil then target = selectedPath end
    if openUri(target) then finish("Opened selection") end
    return
  elseif id == "edit-file" and selectedPath ~= nil then
    if not repeating then rememberAction(id) end
    local editor = config("editor", "nvim")
    if noctalia.runInTerminal(editor .. " " .. shellQuote(selectedPath)) then
      finish("Opened in " .. editor)
    else
      noctalia.notifyError("Plumb", "Could not start the terminal editor.")
    end
    return
  elseif id == "reveal-file" and selectedPath ~= nil then
    if not repeating then rememberAction(id) end
    if openUri(dirname(selectedPath)) then finish("Opened parent directory") end
    return
  elseif id == "note-quick" then
    if not repeating then rememberAction(id) end
    saveNote("plain")
    return
  elseif id == "note-quote" then
    if not repeating then rememberAction(id) end
    saveNote("quote")
    return
  elseif id == "note-code" then
    if not repeating then rememberAction(id) end
    saveNote("code")
    return
  elseif id == "note-daily" then
    if not repeating then rememberAction(id) end
    saveNote("daily")
    return
  elseif id == "search-quick" then
    if not repeating then rememberAction(id) end
    runSearch(config("default_search", "duckduckgo"), selection, false)
    return
  elseif id == "translate-quick" then
    if not repeating then rememberAction(id) end
    runTranslation("google", config("default_translate_target", "ar"))
    return
  elseif id == "search-domain" then
    local domain = domainFromUrl(selection)
    if domain ~= nil then
      if not repeating then rememberAction(id) end
      runSearch(config("default_search", "duckduckgo"), "site:" .. domain, false)
    end
    return
  end

  if id:sub(1, 7) == "search:" then
    if not repeating then rememberAction(id) end
    runSearch(id:sub(8), selection, false)
    return
  elseif id:sub(1, 13) == "search-exact:" then
    if not repeating then rememberAction(id) end
    runSearch(id:sub(14), selection, true)
    return
  elseif id:sub(1, 13) == "search-clean:" then
    if not repeating then rememberAction(id) end
    runSearch(id:sub(14), cleanError(selection), false)
    return
  end

  local provider, target = id:match("^translate:([^:]+):([^:]+)$")
  if provider ~= nil and target ~= nil then
    if not repeating then rememberAction(id) end
    runTranslation(provider, target)
  end
end

local function repeatLast()
  if lastAction == "" then
    status = "No previous action yet"
    render()
    return
  end
  performAction(lastAction, true)
end

local function action(id, title, subtitle, glyph, tags)
  return {
    id = id,
    title = title,
    subtitle = subtitle or "",
    glyph = glyph or "circle",
    tags = tags or "",
  }
end

local function mainActions()
  local actions = {}

  if selectionType == "url" then
    table.insert(actions, action("open", "Open URL", "Open the selected address", "external-link", "url browser open"))
    table.insert(actions, action("copy-domain", "Copy domain", "Copy only the website domain", "world-www", "domain host copy"))
    table.insert(actions, action("search-domain", "Search this website", "Search within the selected domain", "world-search", "site domain search"))
  elseif selectionType == "file" then
    table.insert(actions, action("open", "Open file", "Open with the default application", "file", "file path open"))
    table.insert(actions, action("edit-file", "Edit in terminal", "Open the file with your configured editor", "terminal-2", "file nvim vim editor"))
    table.insert(actions, action("reveal-file", "Open parent directory", "Reveal the file's containing directory", "folder-open", "file folder reveal parent"))
  elseif selectionType == "email" then
    table.insert(actions, action("open", "Compose email", "Open a mailto link for this address", "mail", "email compose mailto"))
  end

  table.insert(actions, action("page:translate", "Translate…", "Choose target language and provider", "language", "translate language google deepl t"))
  table.insert(actions, action("page:search", "Search web…", "Choose DuckDuckGo, Google, GitHub, and more", "world-search", "search engine web s"))
  table.insert(actions, action("page:note", "Save as note…", "Quick note, quote, code snippet, or daily note", "note", "save note markdown daily n"))
  table.insert(actions, action("copy", "Copy selection", "Copy the captured text to the clipboard", "copy", "copy clipboard yank y"))
  table.insert(actions, action("page:edit", "Edit captured text", "Trim or rewrite the text before using it", "edit", "edit modify clean e"))
  table.insert(actions, action("copy-quote", "Copy as Markdown quote", "Prefix every selected line with >", "quote", "markdown quote copy"))
  table.insert(actions, action("search-exact:duckduckgo", "Search exact phrase", "Search the selection inside quotation marks", "quotes", "exact phrase quote search"))

  if selectionType == "error" then
    table.insert(actions, action("search-clean:google", "Search cleaned error", "Remove paths, line columns, timestamps, and ANSI color", "bug", "error clean debug google"))
    table.insert(actions, action("search:stackoverflow", "Search Stack Overflow", "Look for the selected error on Stack Overflow", "brand-stackoverflow", "error debug stackoverflow"))
    table.insert(actions, action("search:github", "Search GitHub issues", "Look for the selected error across GitHub", "brand-github", "error issue github"))
  elseif selectionType == "code" then
    table.insert(actions, action("search:github", "Search code on GitHub", "Search repositories for the selected code or symbol", "brand-github", "code github programming"))
    table.insert(actions, action("search:stackoverflow", "Search programming answers", "Search Stack Overflow for the selection", "brand-stackoverflow", "code stackoverflow programming"))
    table.insert(actions, action("note-code", "Save code snippet", "Append the selection inside a fenced code block", "code", "code snippet note markdown"))
  end

  if lastAction ~= "" then
    table.insert(actions, action("repeat", "Repeat previous action", "Run the last action on this new selection", "repeat", "repeat previous dot ."))
  end

  return actions
end

local function searchActions()
  local actions = {}
  for _, engine in ipairs(SEARCH_ENGINES) do
    table.insert(actions, action(
      "search:" .. engine.id,
      engine.name,
      "Search the captured text with " .. engine.name,
      engine.glyph,
      engine.tags
    ))
  end
  return actions
end

local function translateActions()
  local actions = {}
  for _, language in ipairs(LANGUAGES) do
    table.insert(actions, action(
      "translate:google:" .. language.code,
      language.name .. " · Google",
      "Translate from automatic detection to " .. language.name,
      "brand-google",
      language.tags .. " translate google"
    ))
    table.insert(actions, action(
      "translate:deepl:" .. language.code,
      language.name .. " · DeepL",
      "Translate from automatic detection to " .. language.name,
      "language",
      language.tags .. " translate deepl"
    ))
  end
  return actions
end

local function noteActions()
  return {
    action("note-quick", "Quick inbox note", "Append plain selected text to your notes file", "note", "quick plain inbox note"),
    action("note-quote", "Save as quote", "Append the selection as a Markdown block quote", "quote", "quote markdown note"),
    action("note-code", "Save as code snippet", "Append the selection in a fenced code block", "code", "code snippet markdown note"),
    action("note-daily", "Append to today's note", "Write into YYYY-MM-DD.md in your daily notes directory", "calendar", "daily today journal note"),
  }
end

local function pageActions()
  if page == "search" then return searchActions() end
  if page == "translate" then return translateActions() end
  if page == "note" then return noteActions() end
  return mainActions()
end

local function orderedActions(actions)
  local ordered = {}
  for _, item in ipairs(actions) do
    if favorites[item.id] == true then table.insert(ordered, item) end
  end
  for _, item in ipairs(actions) do
    if favorites[item.id] ~= true then table.insert(ordered, item) end
  end
  return ordered
end

local function filteredActions()
  local actions = orderedActions(pageActions())
  local needle = lower(trim(query))
  if needle == "" then return actions end

  local matches = {}
  for _, item in ipairs(actions) do
    local haystack = lower(item.title .. " " .. item.subtitle .. " " .. item.tags .. " " .. item.id)
    if haystack:find(needle, 1, true) ~= nil then
      table.insert(matches, item)
    end
  end
  return matches
end

local function isLeafAction(id)
  return id ~= "repeat" and id:sub(1, 5) ~= "page:"
end

local function toggleFavorite(id)
  if not isLeafAction(id) then return end
  favorites[id] = favorites[id] ~= true
  persistState()
  status = favorites[id] and "Added to favorites" or "Removed from favorites"
  render()
end

local function executeAction(id)
  if id == "page:translate" then setPage("translate"); return end
  if id == "page:search" then setPage("search"); return end
  if id == "page:note" then setPage("note"); return end
  if id == "page:edit" then
    page = "edit"
    editText = selection
    editKey = editKey + 1
    helpVisible = false
    render()
    return
  end
  if id == "repeat" then repeatLast(); return end
  performAction(id, false)
end

local function executeSelected()
  local item = visibleActions[selectedIndex]
  if item ~= nil then executeAction(item.id) end
end

local function moveSelection(delta)
  if #visibleActions == 0 then return end
  selectedIndex = math.clamp(selectedIndex + delta, 1, #visibleActions)
  render()
end

local function goBack()
  if page ~= "main" then
    setPage("main")
  else
    panel.close()
  end
end

local function pageTitle()
  if page == "translate" then return "Translate" end
  if page == "search" then return "Search web" end
  if page == "note" then return "Save note" end
  if page == "edit" then return "Edit selection" end
  return "Plumb"
end

local function helpCard()
  return ui.column({ gap = 5, padding = 10, fill = "surface_variant/0.45", radius = 10, border = "outline_variant", borderWidth = 1 }, {
    ui.label({ text = "Vim navigation", fontWeight = "bold", color = "primary" }),
    ui.label({ text = "j/k or Ctrl+n/Ctrl+p  move    ·    l/Enter  run", color = "on_surface_variant" }),
    ui.label({ text = "g/G  first/last    ·    Ctrl+d/u  jump    ·    1–9  run item", color = "on_surface_variant" }),
    ui.label({ text = "/  search    ·    Ctrl+g  leave search    ·    h  back", color = "on_surface_variant" }),
    ui.label({ text = "t/s/n/y  quick translate/search/note/copy    ·    .  repeat", color = "on_surface_variant" }),
    ui.label({ text = "Right-click an action to favorite it. Escape always closes.", color = "on_surface_variant" }),
  })
end

local function actionRows(actions)
  local rows = {}
  for index, item in ipairs(actions) do
    local number = index <= 9 and (tostring(index) .. ". ") or "   "
    local favorite = favorites[item.id] == true and "★ " or ""
    table.insert(rows, ui.button({
      key = item.id,
      text = number .. favorite .. item.title,
      glyph = item.glyph,
      contentAlign = "start",
      controlSize = "md",
      selected = index == selectedIndex,
      variant = index == selectedIndex and "secondary" or "ghost",
      tooltip = item.subtitle .. (isLeafAction(item.id) and "\nRight-click to favorite" or ""),
      onClick = function() executeAction(item.id) end,
      onRightClick = function() toggleFavorite(item.id) end,
      onHover = function(state)
        if state == "true" and selectedIndex ~= index then
          selectedIndex = index
          render()
        end
      end,
    }))
  end
  return rows
end

local function renderEditPage(header)
  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    header,
    ui.label({ text = "Edit the captured text. Ctrl+Enter applies it.", color = "on_surface_variant" }),
    ui.input({
      key = "edit-" .. tostring(editKey),
      value = editText,
      placeholder = "Captured text…",
      multiline = true,
      focus = true,
      flexGrow = 1,
      onChange = "onEditChange",
      onSubmit = "onApplyEdit",
    }),
    ui.row({ gap = 8, justify = "end" }, {
      ui.button({ text = "Back", glyph = "arrow-left", variant = "ghost", onClick = "onBackClicked" }),
      ui.button({ text = "Use edited text", glyph = "check", variant = "primary", onClick = "onApplyEdit" }),
    }),
    ui.label({ text = "Escape closes the panel · h works again after leaving this text field", color = "on_surface_variant", fontSize = 12 }),
  }))
end

render = function()
  local header = ui.row({ align = "center", justify = "space_between", gap = 8 }, {
    ui.row({ align = "center", gap = 8, flexGrow = 1 }, {
      page ~= "main" and ui.button({ glyph = "arrow-left", variant = "ghost", tooltip = "Back (h)", onClick = "onBackClicked" }) or ui.glyph({ name = "wand", size = 18, color = "primary" }),
      ui.label({ text = pageTitle(), fontSize = 17, fontWeight = "bold", color = "on_surface" }),
      ui.label({ text = selectionType, fontSize = 12, color = "primary" }),
    }),
    ui.button({ glyph = "help", variant = "ghost", tooltip = "Keyboard help (?)", onClick = "onHelpClicked" }),
    ui.button({ glyph = "close", variant = "ghost", tooltip = "Close (q / Escape)", onClick = "onCloseClicked" }),
  })

  if page == "edit" then
    renderEditPage(header)
    return
  end

  if loading then
    panel.render(ui.column({ flexGrow = 1, gap = 14 }, {
      header,
      ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 12 }, {
        ui.glyph({ name = "loader-2", size = 28, color = "primary" }),
        ui.label({ text = "Capturing the selected text…", color = "on_surface_variant" }),
      }),
    }))
    return
  end

  visibleActions = filteredActions()
  selectedIndex = math.clamp(selectedIndex, 1, math.max(1, #visibleActions))
  local chosen = visibleActions[selectedIndex]
  local chosenDescription = chosen ~= nil and chosen.subtitle or "No matching actions"

  local content = {
    header,
    ui.column({ gap = 5, padding = 11, fill = "surface_variant/0.35", radius = 10, border = "outline_variant", borderWidth = 1 }, {
      ui.label({ text = selection == "" and "No selected text found" or preview(selection, 260), maxLines = 3, color = selection == "" and "error" or "on_surface" }),
      ui.label({ text = tostring(#selection) .. " bytes captured", fontSize = 12, color = "on_surface_variant" }),
    }),
  }

  if helpVisible then table.insert(content, helpCard()) end

  if selection == "" then
    table.insert(content, ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 8 }, {
      ui.glyph({ name = "text-scan-2", size = 30, color = "outline" }),
      ui.label({ text = "Select text, then open Plumb again.", color = "on_surface_variant" }),
      ui.button({ text = "Try clipboard instead", glyph = "clipboard", onClick = "onUseClipboard" }),
    }))
  else
    table.insert(content, ui.scroll({ flexGrow = 1, gap = 5 }, actionRows(visibleActions)))
  end

  table.insert(content, ui.label({ text = chosenDescription, fontSize = 12, color = "on_surface_variant", maxLines = 2 }))
  if status ~= "" then
    table.insert(content, ui.label({ text = status, fontSize = 12, color = "primary" }))
  end
  table.insert(content, ui.input({
    key = "search-" .. tostring(searchKey),
    value = query,
    placeholder = "Search actions…   /",
    controlSize = "sm",
    focus = searchWantsFocus,
    onChange = "onSearchChange",
    onSubmit = "onSearchSubmit",
  }))
  table.insert(content, ui.label({
    text = "j/k navigate · Enter run · / search · h back · ? help · right-click favorite",
    fontSize = 11,
    color = "on_surface_variant",
    textAlign = "center",
  }))

  panel.render(ui.column({ flexGrow = 1, gap = 10 }, content))
end

local function acceptSelection(value)
  selection = trim(value)
  selectionType = detectType(selection)
  editText = selection
  loading = false
  status = ""
  selectedIndex = 1
  render()
end

local function captureSelection()
  loading = true
  render()

  if noctalia.commandExists("wl-paste") then
    local accepted = noctalia.runAsync("wl-paste --primary --no-newline", function(result)
      local value = ""
      if result ~= nil and result.exitCode == 0 then value = result.stdout or "" end
      if trim(value) == "" then value = noctalia.clipboardText() or "" end
      acceptSelection(value)
    end)
    if accepted then return end
  end

  acceptSelection(noctalia.clipboardText() or "")
end

function onOpen(_context)
  page = "main"
  query = ""
  selectedIndex = 1
  searchKey = searchKey + 1
  searchWantsFocus = false
  helpVisible = false
  status = ""
  captureSelection()
end

function onClose()
  loading = false
  searchWantsFocus = false
end

function onCloseClicked()
  panel.close()
end

function onBackClicked()
  goBack()
end

function onHelpClicked()
  helpVisible = not helpVisible
  render()
end

function onUseClipboard()
  acceptSelection(noctalia.clipboardText() or "")
end

function onSearchChange(value)
  query = value or ""
  selectedIndex = 1
  render()
end

function onSearchSubmit(_value)
  executeSelected()
end

function onEditChange(value)
  editText = value or ""
end

function onApplyEdit(value)
  if type(value) == "string" and value ~= "" then editText = value end
  selection = trim(editText)
  selectionType = detectType(selection)
  page = "main"
  query = ""
  selectedIndex = 1
  searchKey = searchKey + 1
  searchWantsFocus = false
  status = "Edited selection applied"
  render()
end

function onKey(chord, pressed)
  if not pressed then return end

  if chord == "j" or chord == "ctrl+n" then
    moveSelection(1)
  elseif chord == "k" or chord == "ctrl+p" then
    moveSelection(-1)
  elseif chord == "ctrl+d" then
    moveSelection(5)
  elseif chord == "ctrl+u" then
    moveSelection(-5)
  elseif chord == "g" then
    selectedIndex = 1
    render()
  elseif chord == "shift+g" then
    selectedIndex = math.max(1, #visibleActions)
    render()
  elseif chord == "l" or chord == "Return" then
    executeSelected()
  elseif chord == "h" then
    goBack()
  elseif chord == "/" then
    searchWantsFocus = true
    searchKey = searchKey + 1
    render()
  elseif chord == "ctrl+g" then
    query = ""
    selectedIndex = 1
    searchWantsFocus = false
    searchKey = searchKey + 1
    status = "Search cleared"
    render()
  elseif chord == "q" then
    panel.close()
  elseif chord == "shift+/" then
    helpVisible = not helpVisible
    render()
  elseif chord == "." then
    repeatLast()
  elseif chord == "t" then
    performAction("translate-quick", false)
  elseif chord == "s" then
    performAction("search-quick", false)
  elseif chord == "n" then
    performAction("note-quick", false)
  elseif chord == "y" then
    performAction("copy", false)
  elseif chord == "e" then
    executeAction("page:edit")
  else
    local number = tonumber(chord)
    if number ~= nil and number >= 1 and number <= 9 then
      local item = visibleActions[number]
      if item ~= nil then executeAction(item.id) end
    end
  end
end
