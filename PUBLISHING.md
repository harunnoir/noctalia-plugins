# Publishing Plumb

## 1. Publish the personal plugin source

Create an empty GitHub repository named `noctalia-plugins` under `harunnoir`, then run from this directory:

```bash
git init
git branch -M main
git add .
git commit -m "feat: publish Plumb 1.0.1"
git remote add origin git@github.com:harunnoir/noctalia-plugins.git
git push -u origin main
```

Test installation from the public source:

```bash
noctalia msg plugins source add harunnoir git     https://github.com/harunnoir/noctalia-plugins
noctalia msg plugins enable harunnoir/plumb
noctalia msg panel-toggle harunnoir/plumb:actions
```

## 2. Submit to Noctalia community plugins

The personal source commits `catalog.toml`. The community repository does **not** accept that file in plugin pull requests because its CI regenerates the shared catalog.

1. Fork `noctalia-dev/community-plugins`.
2. Clone your fork.
3. Copy this repository's `plumb/` directory to the root of the community repository.
4. Do not copy this repository's root `catalog.toml`.
5. Run the community repository's validation workflow.
6. Commit only the new `plumb/` directory and open one pull request for this plugin.

Suggested commit:

```bash
git add plumb
git commit -m "feat: add harunnoir/plumb"
git push
```

## Pull-request disclosure

Include these details in the PR description:

- **External dependencies:** `wl-clipboard`, `xdg-utils`.
- **Spawned processes:** `wl-paste`, `xdg-open` or `gio open`, and the configured terminal editor.
- **Network behavior:** no direct HTTP calls; explicit search and translation actions open provider URLs in the default browser with the selected text encoded as a query.
- **Filesystem writes:** configured notes paths and Noctalia's per-plugin data directory for favorites and last-action history.
- **Remote code:** none is downloaded or executed.
- **Visual surface:** panel entry `harunnoir/plumb:actions`; include a real panel screenshot or short recording after testing it locally.

The included `thumbnail.webp` is a 960×540 store preview. Replacing it with a real screenshot passed through Noctalia's thumbnail generator before submission is recommended after live testing.
