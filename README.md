# harunnoir Noctalia plugins

A custom Noctalia v5 plugin source maintained by **harunnoir**.

## Available plugins

| Plugin | Description |
|---|---|
| [`harunnoir/plumb`](./plumb/) | Search, translate, copy, open, edit, and save selected Wayland text from a Vim-friendly panel. |

## Add this source to Noctalia

After publishing this repository at `https://github.com/harunnoir/noctalia-plugins`:

```bash
noctalia msg plugins source add harunnoir git     https://github.com/harunnoir/noctalia-plugins

noctalia msg plugins enable harunnoir/plumb
```

Open Plumb:

```bash
noctalia msg panel-toggle harunnoir/plumb:actions
```

Update the source later:

```bash
noctalia msg plugins update harunnoir
```

The same operations are available in **Noctalia Settings → Plugins**.

## Local development

From the directory containing this repository:

```bash
noctalia msg plugins source add harunnoir-dev path "$PWD"
noctalia msg plugins enable harunnoir/plumb
```

Luau edits hot-reload. Reload Noctalia after changing `plugin.toml`.

## Validate and regenerate the catalog

```bash
make catalog
make validate
```

`catalog.toml` is committed because custom Git sources need it for discovery and compatibility checks.

## Publish this repository

```bash
git init
git branch -M main
git add .
git commit -m "feat: publish Plumb 1.0.1"
git remote add origin git@github.com:harunnoir/noctalia-plugins.git
git push -u origin main
```

For submission to Noctalia's built-in community store, see [`PUBLISHING.md`](./PUBLISHING.md).
