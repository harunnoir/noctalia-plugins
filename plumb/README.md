# Plumb for Noctalia — dynamic action tree

Plumb is a selected-text action menu for Noctalia v5. The panel itself is generic: every visible folder and action comes from one editable JSON tree.

## Install

```bash
chmod +x install.sh
./install.sh
```

The important files are:

```text
~/.local/share/noctalia/plugins/plumb/   # plugin code
~/.config/noctalia/plumb/actions.json   # your editable action tree
~/bin/plumb                              # selection launcher
```

The installer never overwrites an existing `actions.json`.

## Tree model

The array order is the menu order. Any node containing `children` becomes a folder, and nesting can be arbitrarily deep:

```json
[
  {
    "label": "Search On Web",
    "icon": "folder-search",
    "children": [
      {
        "label": "DuckDuckGo",
        "icon": "brand-duckduckgo",
        "type": "url",
        "url": "https://duckduckgo.com/?q={text}"
      },
      {
        "label": "Google",
        "icon": "brand-google",
        "type": "url",
        "url": "https://www.google.com/search?q={text}"
      },
      {
        "label": "Wikipedia",
        "icon": "brand-wikipedia",
        "type": "url",
        "url": "https://en.wikipedia.org/w/index.php?search={text}"
      }
    ]
  },
  {
    "label": "Translate",
    "icon": "language",
    "children": []
  },
  {
    "label": "Copy",
    "icon": "copy",
    "type": "copy"
  },
  {
    "label": "Save as note",
    "icon": "note",
    "type": "note"
  }
]
```

Edit the JSON and reopen Plumb. It reloads the file on every open. The refresh icon reloads it while the panel is already open.

## Supported leaf types

### URL

`{text}` and `{urlencoded}` are replaced by the URL-encoded selection.

```json
{
  "label": "Stack Overflow",
  "icon": "brand-stackoverflow",
  "type": "url",
  "url": "https://stackoverflow.com/search?q={text}"
}
```

### Copy

```json
{
  "label": "Copy",
  "icon": "copy",
  "type": "copy"
}
```

### Note

Appends to the Markdown file configured in Noctalia’s Plumb settings.

```json
{
  "label": "Save as note",
  "icon": "note",
  "type": "note"
}
```

### Command

Commands are trusted local configuration and run through the shell.

Available placeholders:

- `{text}` — shell-quoted selected text
- `{urlencoded}` — URL-encoded selected text
- `{file}` — shell-quoted path containing the exact selected text

Example: uppercase the selection and copy the result:

```json
{
  "label": "Uppercase → clipboard",
  "icon": "letter-case-upper",
  "type": "command",
  "command": "printf %s {text} | tr '[:lower:]' '[:upper:]' | wl-copy",
  "message": "Uppercase text copied"
}
```

Example: pass the selection file to your own program:

```json
{
  "label": "Send to my script",
  "icon": "terminal-2",
  "type": "command",
  "command": "~/bin/my-text-tool {file}"
}
```

Optional leaf fields:

```json
{
  "close": false,
  "notify": false,
  "message": "Custom notification"
}
```

Set `hidden` to `true` on any node to temporarily remove it without deleting it.

## Validate after editing

```bash
jq empty ~/.config/noctalia/plumb/actions.json
```

## Void Linux dependencies

```bash
sudo xbps-install -S wl-clipboard xdg-utils libnotify python3
```

## Use

Your Niri binding should keep calling:

```text
~/bin/plumb
```

Only ordinary prose opens this menu. URLs, paths, emails, man pages, and the other recognized selections keep their direct Plumb routing.
