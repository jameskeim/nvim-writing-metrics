# Plan D — nvim-text-sharing fixes & UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two bugs in `nvim-text-sharing` (`os.tmpname()` race; misleading HTTP-server "started" toast when port is already in use), add `:Share*` user commands for discoverability, and switch the lazy-loader config from `lazy = false` to true lazy-loading on keys + cmd.

**Architecture:** Five small changes, no refactoring. Four commits land on `main` of `~/projects/nvim-text-sharing/`; one edit lands in `~/.config/nvim/lua/plugins/text-sharing.lua` (not git-tracked). The HTTP-server fix uses a synchronous `vim.uv.new_tcp():bind()` probe to detect port-in-use before launching python3.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), libuv (via `vim.uv`), python3 (the spawned HTTP server). No test framework — the plugin has no `tests/` directory; verification uses headless smoke tests.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-text-sharing/` — git-tracked; commits land directly on `main`. Repo currently has one commit: `980577d Initial commit: extract text-sharing plugin from nvim config`.
- **Nvim config:** `~/.config/nvim/` — NOT git-tracked. Changes apply on save; no commit needed.
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-tier3-tier4-cleanup-design.md`
- **No automated test suite.** Verification is done via `nvim --headless -c "lua ..." -c "qa!"` smoke tests. The plugin is ~270 lines of straightforward code; setting up plenary infrastructure for one or two tests would be disproportionate. The spec acknowledges this ("commands smoke-test via `:` invocation").

Pre-existing facts the implementer should know going in:
- `M.config` is initialized fresh on every module load (`M.config = { dropbox_path = ..., http_port = 8000, http_server_pid = nil }` at the top of `init.lua`). The "stale `http_server_pid`" concern from the audit isn't about Lua state surviving a reload — it's about an orphaned python3 process from a previous nvim crash that still holds the port. The fix is the port pre-check; the setup-time pid clear is belt-and-suspenders.
- `M.config.http_port` defaults to 8000 but the user can override via `setup({ http_port = ... })`.
- `setup_keybindings()` binds 9 keymaps under `<leader>y*` (yd in n+x, yD, yf, yo, yq in n+x, yh, yH). These stay as-is.
- The user runs `vim.fn.jobstart(cmd)` to spawn python3. `jobstart` returns a positive job ID even when the child process is about to die immediately (e.g., `EADDRINUSE`). That's why the current "started" toast is misleading.
- The plugin returns the module table (`return M` at the end), not a lazy.nvim plugin spec.

---

## Task 1: Fix #6 — Replace `os.tmpname()` with `vim.fn.tempname()`

**Files:**
- Modify: `~/projects/nvim-text-sharing/lua/text-sharing/init.lua:166`

**Background:** `os.tmpname()` returns a predictable path (typically `/tmp/lua_<rand>`) and creates the file with predictable permissions, allowing TOCTOU symlink attacks. `vim.fn.tempname()` is Neovim's secure variant: it returns a unique path under a per-session directory. The `nvim-writing-metrics` plugin's `utils.write_temp_file()` already uses `vim.fn.tempname()` — this brings `nvim-text-sharing` into consistency.

- [ ] **Step 1: Verify the current call site**

```bash
grep -n "os.tmpname\|vim.fn.tempname" ~/projects/nvim-text-sharing/lua/text-sharing/init.lua
```

Expected: one match at line 166 (`local temp_file = os.tmpname() .. ".utf8"`). No existing `vim.fn.tempname` usage.

- [ ] **Step 2: Apply the fix**

In `~/projects/nvim-text-sharing/lua/text-sharing/init.lua`, find line 166 inside `M._generate_qr_from_text`:

```lua
  local temp_file = os.tmpname() .. ".utf8"
  vim.fn.system(string.format("qrencode -t UTF8 -o %s %s", temp_file, vim.fn.shellescape(text)))
```

Replace with:

```lua
  -- Use vim.fn.tempname() instead of os.tmpname() to avoid the predictable
  -- /tmp/lua_<rand> path and the symlink TOCTOU window that comes with it.
  local temp_file = vim.fn.tempname() .. ".utf8"
  vim.fn.system(string.format("qrencode -t UTF8 -o %s %s", temp_file, vim.fn.shellescape(text)))
```

- [ ] **Step 3: Verify the file still parses**

```bash
nvim --headless -c "luafile /home/jkeim/projects/nvim-text-sharing/lua/text-sharing/init.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output (loads cleanly).

- [ ] **Step 4: Verify the structural change**

```bash
grep -n "os.tmpname\|vim.fn.tempname" ~/projects/nvim-text-sharing/lua/text-sharing/init.lua
```

Expected: one match for `vim.fn.tempname`, zero for `os.tmpname`.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-text-sharing
git add lua/text-sharing/init.lua
git commit -m "fix(qr): use vim.fn.tempname() to avoid os.tmpname() TOCTOU

os.tmpname() returns a predictable path (/tmp/lua_<rand>), opening
a brief symlink-attack window between when the path is returned
and when qrencode writes to it. vim.fn.tempname() is Neovim's
secure variant and is already used by sibling plugins."
```

---

## Task 2: Fix #5 — Pre-detect HTTP server port-in-use; clear stale pid in setup

**Files:**
- Modify: `~/projects/nvim-text-sharing/lua/text-sharing/init.lua:208-233` (`M.start_http_server`)
- Modify: `~/projects/nvim-text-sharing/lua/text-sharing/init.lua:265-270` (`M.setup`)

**Background:** `start_http_server` checks `M.config.http_server_pid` (always nil after a fresh nvim launch), then calls `vim.fn.jobstart` to spawn python3. `jobstart` returns a positive job ID even when the child is about to die (python3 fails with `EADDRINUSE` if the port is already bound — most commonly by an orphaned process from a prior nvim crash). The current code then optimistically shows "HTTP server started" and only learns the truth later via `on_exit`.

Fix:
1. Add a `port_in_use(port)` helper that synchronously probes the port using `vim.uv.new_tcp():bind()`. If the bind fails, the port is occupied.
2. In `start_http_server`, call the helper BEFORE `jobstart`. If the port is in use, surface a clear error instead of misleading the user.
3. In `setup`, defensively reset `M.config.http_server_pid = nil` so a stale value can't survive across a re-`require` (e.g., `:Lazy reload`).

- [ ] **Step 1: Add the `port_in_use` helper**

In `~/projects/nvim-text-sharing/lua/text-sharing/init.lua`, find the HTTP SERVER section header around line 204:

```lua
-- =============================================================================
-- HTTP SERVER
-- =============================================================================

function M.start_http_server()
```

Insert the helper between the section header and `function M.start_http_server()`:

```lua
-- =============================================================================
-- HTTP SERVER
-- =============================================================================

--- Synchronously probe whether a TCP port on 127.0.0.1 is already bound.
--- Strategy: try to bind a libuv TCP server to the port and close
--- immediately. If bind raises (typically EADDRINUSE), the port is in use.
--- The probe binds-and-closes without listen(), so it doesn't leave TIME_WAIT.
--- @param port integer Port number to probe
--- @return boolean True if the port appears to be in use
local function port_in_use(port)
  local server = vim.uv.new_tcp()
  if not server then
    -- libuv allocation failed; we can't probe, so optimistically say "free"
    -- and let jobstart's downstream error handling deal with any actual conflict.
    return false
  end
  local ok = pcall(function()
    server:bind("127.0.0.1", port)
  end)
  pcall(function() server:close() end)
  return not ok
end

function M.start_http_server()
```

- [ ] **Step 2: Update `start_http_server` to use the helper**

Still in `~/projects/nvim-text-sharing/lua/text-sharing/init.lua`, find the body of `start_http_server` (originally lines 208-233, now shifted down by the helper added above):

```lua
function M.start_http_server()
  if M.config.http_server_pid then
    M.notify("HTTP server already running on port " .. M.config.http_port, vim.log.levels.WARN)
    return
  end

  local cwd = vim.fn.getcwd()
  local cmd = string.format("python3 -m http.server %d --bind 127.0.0.1 --directory %s", M.config.http_port, vim.fn.shellescape(cwd))

  local job_id = vim.fn.jobstart(cmd, {
    on_exit = function()
      M.config.http_server_pid = nil
      M.notify("HTTP server stopped")
    end,
  })

  if job_id > 0 then
    M.config.http_server_pid = job_id
    M.notify(
      string.format("HTTP server started on http://127.0.0.1:%d (loopback only)\nServing: %s", M.config.http_port, cwd),
      vim.log.levels.INFO
    )
  else
    M.notify("Failed to start HTTP server", vim.log.levels.ERROR)
  end
end
```

Replace with:

```lua
function M.start_http_server()
  if M.config.http_server_pid then
    M.notify("HTTP server already running on port " .. M.config.http_port, vim.log.levels.WARN)
    return
  end

  -- Pre-detect port conflict so we don't fire a misleading "started" toast
  -- when python3 is about to die from EADDRINUSE. Most common cause: an
  -- orphaned python3 from a previous nvim crash that still holds the port.
  if port_in_use(M.config.http_port) then
    M.notify(
      string.format(
        "Port %d is already in use. Another process (possibly an orphaned python3 from a previous session) is holding it.",
        M.config.http_port
      ),
      vim.log.levels.ERROR
    )
    return
  end

  local cwd = vim.fn.getcwd()
  local cmd = string.format("python3 -m http.server %d --bind 127.0.0.1 --directory %s", M.config.http_port, vim.fn.shellescape(cwd))

  local job_id = vim.fn.jobstart(cmd, {
    on_exit = function()
      M.config.http_server_pid = nil
      M.notify("HTTP server stopped")
    end,
  })

  if job_id > 0 then
    M.config.http_server_pid = job_id
    M.notify(
      string.format("HTTP server started on http://127.0.0.1:%d (loopback only)\nServing: %s", M.config.http_port, cwd),
      vim.log.levels.INFO
    )
  else
    M.notify("Failed to start HTTP server", vim.log.levels.ERROR)
  end
end
```

(Only the pre-check block is added; everything else stays.)

- [ ] **Step 3: Defensively reset `http_server_pid` in `setup`**

Find `M.setup` near the bottom of `~/projects/nvim-text-sharing/lua/text-sharing/init.lua` (originally lines 265-270):

```lua
-- Public entry point. Pass `opts` to override M.config values.
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  M.setup_keybindings()
end
```

Replace with:

```lua
-- Public entry point. Pass `opts` to override M.config values.
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  -- Defensively clear http_server_pid so a stale value from a previous
  -- module load (e.g. across :Lazy reload) can't make start_http_server
  -- skip the spawn path on the assumption that a server is already running.
  M.config.http_server_pid = nil
  M.setup_keybindings()
end
```

- [ ] **Step 4: Verify the file still parses**

```bash
nvim --headless -c "luafile /home/jkeim/projects/nvim-text-sharing/lua/text-sharing/init.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 5: Smoke-test the port-in-use detection**

Run this orchestrated headless test that occupies port 9876 with a sleep process bound there via python, then asks the plugin to start its server on the same port. Use port 9876 (not the default 8000) so the test doesn't interfere with any real server the user has running.

```bash
# Start a blocking python http server on port 9876 in the background
python3 -m http.server 9876 --bind 127.0.0.1 >/dev/null 2>&1 &
BLOCKER_PID=$!
sleep 0.5  # let it bind

# Now ask the plugin to start its server on the same port
nvim --headless \
  -c "set rtp+=/home/jkeim/projects/nvim-text-sharing" \
  -c "lua require('text-sharing').setup({ http_port = 9876 })" \
  -c "lua require('text-sharing').start_http_server()" \
  -c "qa!" 2>&1 | head -10

# Clean up the blocker
kill $BLOCKER_PID 2>/dev/null
wait $BLOCKER_PID 2>/dev/null
```

Expected: the headless output includes a notification like `Port 9876 is already in use. Another process...`. It should NOT include the "started" success toast.

- [ ] **Step 6: Smoke-test the success path (port free)**

```bash
# Pick an obscure port that's definitely not occupied
nvim --headless \
  -c "set rtp+=/home/jkeim/projects/nvim-text-sharing" \
  -c "lua require('text-sharing').setup({ http_port = 19876 })" \
  -c "lua require('text-sharing').start_http_server()" \
  -c "sleep 200m" \
  -c "lua require('text-sharing').stop_http_server()" \
  -c "qa!" 2>&1 | head -10
```

Expected: output includes "HTTP server started on http://127.0.0.1:19876" then "HTTP server stopped". No port-in-use error.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/nvim-text-sharing
git add lua/text-sharing/init.lua
git commit -m "fix(http): pre-detect port-in-use before claiming server started

start_http_server() used to spawn python3 via jobstart and show
'HTTP server started' as soon as jobstart returned a job ID — but
jobstart returns a positive ID even when the child is about to die
from EADDRINUSE. Most common cause: an orphaned python3 from a
prior nvim crash still holding the port.

Adds a synchronous vim.uv.new_tcp():bind() probe before jobstart;
surfaces a clear error if the port is occupied. Also defensively
clears M.config.http_server_pid in setup() so a stale value can't
survive across :Lazy reload."
```

---

## Task 3: Add `:Share*` user commands (UX-1)

**Files:**
- Modify: `~/projects/nvim-text-sharing/lua/text-sharing/init.lua` — add `M.setup_commands()` function near `M.setup_keybindings`; call it from `M.setup`.

**Background:** The plugin currently only exposes its features via `<leader>y*` keymaps. Adding user commands lets users discover features via `:`-tab-completion and lets which-key and similar tools surface them. Per the spec, visual-mode variants for `<leader>yd` and `<leader>yq` stay keymap-only since `:CommandName` doesn't have a clean visual interface without `range` (which the spec explicitly opts out of).

Seven commands to register, mapped to existing public functions in the plugin:

| Command | Calls | Replaces keymap |
|---|---|---|
| `:ShareDropbox` | `M.share_to_dropbox_normal` | `<leader>yd` (normal) |
| `:ShareDropboxSave` | `M.save_to_dropbox` | `<leader>yD` |
| `:ShareDropboxOpen` | `M.open_from_dropbox` | `<leader>yo` |
| `:ShareDropboxFolder` | `M.open_dropbox_folder` | `<leader>yf` |
| `:ShareQR` | `M.generate_qr_code_normal` | `<leader>yq` (normal) |
| `:ServeHTTP` | `M.start_http_server` | `<leader>yh` |
| `:StopHTTP` | `M.stop_http_server` | `<leader>yH` |

- [ ] **Step 1: Add `M.setup_commands()` function**

In `~/projects/nvim-text-sharing/lua/text-sharing/init.lua`, find `M.setup_keybindings` around line 250-262. Add the new function IMMEDIATELY BEFORE `setup_keybindings` so they live together in the file's structure:

```lua
function M.setup_keybindings()
```

Insert above it:

```lua
--- Register user commands so each <leader>y* action also has a `:Share*`
--- counterpart. Discoverable via `:`-tab-completion, surfaced by which-key
--- and command-history tools. Visual-mode variants for share-selection and
--- qr-from-selection stay keymap-only (`:Command` has no clean visual
--- interface without range support, which the spec explicitly opts out of).
function M.setup_commands()
  vim.api.nvim_create_user_command("ShareDropbox", function()
    M.share_to_dropbox_normal()
  end, { desc = "Share entire buffer to Dropbox" })

  vim.api.nvim_create_user_command("ShareDropboxSave", function()
    M.save_to_dropbox()
  end, { desc = "Save buffer as new file in Dropbox (prompts for name)" })

  vim.api.nvim_create_user_command("ShareDropboxOpen", function()
    M.open_from_dropbox()
  end, { desc = "Pick a file from Dropbox via snacks.picker" })

  vim.api.nvim_create_user_command("ShareDropboxFolder", function()
    M.open_dropbox_folder()
  end, { desc = "Open Dropbox shared folder in nvim" })

  vim.api.nvim_create_user_command("ShareQR", function()
    M.generate_qr_code_normal()
  end, { desc = "QR code from entire buffer" })

  vim.api.nvim_create_user_command("ServeHTTP", function()
    M.start_http_server()
  end, { desc = "Start local HTTP server (loopback)" })

  vim.api.nvim_create_user_command("StopHTTP", function()
    M.stop_http_server()
  end, { desc = "Stop local HTTP server" })
end

function M.setup_keybindings()
```

- [ ] **Step 2: Call `setup_commands` from `setup`**

Find `M.setup` (modified in Task 2):

```lua
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  -- Defensively clear http_server_pid so a stale value from a previous
  -- module load (e.g. across :Lazy reload) can't make start_http_server
  -- skip the spawn path on the assumption that a server is already running.
  M.config.http_server_pid = nil
  M.setup_keybindings()
end
```

Replace with:

```lua
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  -- Defensively clear http_server_pid so a stale value from a previous
  -- module load (e.g. across :Lazy reload) can't make start_http_server
  -- skip the spawn path on the assumption that a server is already running.
  M.config.http_server_pid = nil
  M.setup_commands()
  M.setup_keybindings()
end
```

- [ ] **Step 3: Verify the file still parses**

```bash
nvim --headless -c "luafile /home/jkeim/projects/nvim-text-sharing/lua/text-sharing/init.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Smoke-test that all 7 commands register**

```bash
nvim --headless \
  -c "set rtp+=/home/jkeim/projects/nvim-text-sharing" \
  -c "lua require('text-sharing').setup()" \
  -c "command ShareDropbox" \
  -c "command ShareDropboxSave" \
  -c "command ShareDropboxOpen" \
  -c "command ShareDropboxFolder" \
  -c "command ShareQR" \
  -c "command ServeHTTP" \
  -c "command StopHTTP" \
  -c "qa!" 2>&1 | head -30
```

Expected: each `command` invocation prints a `Name` table row with the command name and its `desc` string. None should report "No such command" or similar.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-text-sharing
git add lua/text-sharing/init.lua
git commit -m "feat(commands): register :Share* user commands for discoverability

Every <leader>y* keymap that targets a normal-mode action now has
a matching :Share* command:
  :ShareDropbox            (was: <leader>yd normal)
  :ShareDropboxSave        (was: <leader>yD)
  :ShareDropboxOpen        (was: <leader>yo)
  :ShareDropboxFolder      (was: <leader>yf)
  :ShareQR                 (was: <leader>yq normal)
  :ServeHTTP               (was: <leader>yh)
  :StopHTTP                (was: <leader>yH)

Visual-mode variants for share-selection and qr-from-selection
stay keymap-only since :Command has no clean visual interface
without range support."
```

---

## Task 4: Document `:Share*` commands in README

**Files:**
- Modify: `~/projects/nvim-text-sharing/README.md` — add Commands section after Keybindings.

**Background:** The existing 65-line README is solid (Features / Installation / Configuration / Keybindings / Dependencies / Security notes). This task adds a Commands section that mirrors the Keybindings table, listing the 7 commands registered in Task 3.

- [ ] **Step 1: Find the Keybindings section**

```bash
grep -n "^## " ~/projects/nvim-text-sharing/README.md
```

Expected output includes:

```
## Features
## Installation
## Configuration
## Keybindings
## External dependencies
## Security notes
```

The new "## Commands" section will go AFTER "## Keybindings" and BEFORE "## External dependencies".

- [ ] **Step 2: Read the current Keybindings section to confirm format**

```bash
sed -n '/^## Keybindings/,/^## /p' ~/projects/nvim-text-sharing/README.md | head -20
```

Expected: a markdown table with columns "Key | Mode | Action" and 9 rows for the `<leader>y*` keymaps.

- [ ] **Step 3: Add the Commands section**

Find the line `## External dependencies` in `~/projects/nvim-text-sharing/README.md`. Immediately BEFORE that line (after the last row of the Keybindings table and its trailing blank line), insert:

```markdown
## Commands

Every normal-mode keymap above has a matching `:Share*` or `:*HTTP` command for discoverability via `:`-tab-completion and which-key:

| Command | Action |
|---|---|
| `:ShareDropbox` | Share entire buffer to Dropbox |
| `:ShareDropboxSave` | Save buffer as new file in Dropbox (prompts for name) |
| `:ShareDropboxOpen` | Pick a file from Dropbox via snacks.picker |
| `:ShareDropboxFolder` | Open Dropbox shared folder in nvim |
| `:ShareQR` | QR code from entire buffer |
| `:ServeHTTP` | Start local HTTP server (loopback only, port 8000 by default) |
| `:StopHTTP` | Stop local HTTP server |

Visual-mode variants for share-selection and QR-from-selection stay keymap-only (`<leader>yd` / `<leader>yq` in visual mode).

```

(Note: the trailing blank line before `## External dependencies` should be preserved.)

- [ ] **Step 4: Verify the README structure**

```bash
grep -n "^## " ~/projects/nvim-text-sharing/README.md
```

Expected: same sections as before, with `## Commands` now appearing between `## Keybindings` and `## External dependencies`.

```bash
sed -n '/^## Commands/,/^## External dependencies/p' ~/projects/nvim-text-sharing/README.md | head -20
```

Expected: the new Commands section renders, with 7 command rows.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-text-sharing
git add README.md
git commit -m "docs: document new :Share* commands in README

Adds a Commands section after Keybindings, listing the 7 user
commands registered in setup_commands(). Notes that visual-mode
variants stay keymap-only."
```

---

## Task 5: Switch lazy-loader config from `lazy = false` to true lazy-loading

**Files:**
- Modify: `~/.config/nvim/lua/plugins/text-sharing.lua` (NOT git-tracked; no commit)

**Background:** The plugin currently loads at every nvim startup (`lazy = false`). The text-sharing features are infrequent — typical sessions never invoke them. Switching to `lazy = true` with `keys` and `cmd` triggers means the plugin only loads when the user actually presses one of the `<leader>y*` keys or runs one of the `:Share*` commands. Lazy.nvim handles the trigger-load-replay dance transparently.

- [ ] **Step 1: Read the current lazy spec**

```bash
cat ~/.config/nvim/lua/plugins/text-sharing.lua
```

Expected:

```lua
-- nvim-text-sharing - local plugin loader
-- Source: ~/projects/nvim-text-sharing/
return {
  {
    dir = vim.fn.expand("~/projects/nvim-text-sharing"),
    lazy = false,
    config = function()
      require("text-sharing").setup()
    end,
  },
}
```

- [ ] **Step 2: Replace the spec with the lazy-loaded version**

Replace the contents of `~/.config/nvim/lua/plugins/text-sharing.lua` with:

```lua
-- nvim-text-sharing - local plugin loader
-- Source: ~/projects/nvim-text-sharing/
return {
  {
    dir = vim.fn.expand("~/projects/nvim-text-sharing"),
    -- Lazy-load on either a <leader>y* key or a :Share*/:ServeHTTP/:StopHTTP command.
    -- The plugin's setup() registers the real keymaps and commands; the entries
    -- below are lazy.nvim load triggers (no action), which replay the keystroke
    -- through the real handlers after the plugin loads.
    keys = {
      { "<leader>yd", mode = { "n", "x" }, desc = "share buffer/selection to dropbox" },
      { "<leader>yD", desc = "save buffer as to dropbox" },
      { "<leader>yf", desc = "open dropbox folder" },
      { "<leader>yo", desc = "open from dropbox" },
      { "<leader>yq", mode = { "n", "x" }, desc = "qr code from buffer/selection" },
      { "<leader>yh", desc = "start http server" },
      { "<leader>yH", desc = "stop http server" },
    },
    cmd = {
      "ShareDropbox",
      "ShareDropboxSave",
      "ShareDropboxOpen",
      "ShareDropboxFolder",
      "ShareQR",
      "ServeHTTP",
      "StopHTTP",
    },
    config = function()
      require("text-sharing").setup()
    end,
  },
}
```

- [ ] **Step 3: Verify the spec parses**

```bash
nvim --headless -c "luafile /home/jkeim/.config/nvim/lua/plugins/text-sharing.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Smoke-test cmd-based lazy loading**

Start a fresh nvim and verify that `:ShareDropbox` exists (lazy.nvim creates a placeholder until the plugin loads):

```bash
nvim --headless -c "Lazy load nvim-text-sharing" -c "command ShareDropbox" -c "qa!" 2>&1 | head -10
```

Expected: the command resolves to a real callback at the plugin's `init.lua` (a `Lua <number>: /home/jkeim/projects/nvim-text-sharing/...` line in the output).

If the `Lazy load` command fails with "No such plugin" or similar, the lazy spec didn't pick up the directory. Double-check the `dir = vim.fn.expand("~/projects/nvim-text-sharing")` path and run `:Lazy sync` manually.

- [ ] **Step 5: Visual verification (interactive — skip if running headless)**

If running this plan interactively, start a real nvim session and confirm:
- `:Lazy` shows `nvim-text-sharing` as lazy-loaded (not loaded at startup).
- Typing `:ShareDropbox<Tab>` completes; running it executes successfully.
- Pressing `<leader>yh` starts the server (loads the plugin on first keystroke).

- [ ] **Step 6: No commit needed**

`~/.config/nvim/` is not a git repository. The change is live as soon as the file is saved.

---

## Final verification

After all five tasks complete, run a holistic smoke check from a fresh nvim:

```bash
nvim --headless \
  -c "Lazy load nvim-text-sharing" \
  -c "command ShareDropbox" \
  -c "command ShareDropboxSave" \
  -c "command ShareDropboxOpen" \
  -c "command ShareDropboxFolder" \
  -c "command ShareQR" \
  -c "command ServeHTTP" \
  -c "command StopHTTP" \
  -c "qa!" 2>&1 | head -30
```

Expected: every `command` line resolves to a real callback (no "No such command" errors).

Then review the commit log:

```bash
cd ~/projects/nvim-text-sharing
git log --oneline
```

Expected: 4 new commits on top of `980577d Initial commit`, one per repo-touching task:
- `fix(qr): use vim.fn.tempname() to avoid os.tmpname() TOCTOU`
- `fix(http): pre-detect port-in-use before claiming server started`
- `feat(commands): register :Share* user commands for discoverability`
- `docs: document new :Share* commands in README`

The `~/.config/nvim/lua/plugins/text-sharing.lua` change has no commit (intentional — that repo isn't git-tracked).

---

## Summary

5 tasks. 4 commits on `main` of `~/projects/nvim-text-sharing/`. 1 saved edit in `~/.config/nvim/lua/plugins/text-sharing.lua` (no commit). No test files created — verification is via headless smoke tests proportional to the plugin's complexity. Estimated 1-1.5 hours of focused work.

After completion:
- QR generation no longer uses the racy `os.tmpname()` (#6).
- The HTTP server doesn't claim "started" when python3 is about to die from `EADDRINUSE` (#5); a stale `http_server_pid` from a previous `:Lazy reload` is defensively cleared.
- Seven new `:Share*` / `:*HTTP` commands surface every normal-mode action via `:`-tab-completion (UX-1).
- The plugin is lazy-loaded — no startup cost on sessions that never use it (UX-2).
- README documents the new commands.

After this plan lands, update the project memory entry `project_nvim_text_sharing_known_issues.md` to reclassify #5 and #6 as FIXED.
