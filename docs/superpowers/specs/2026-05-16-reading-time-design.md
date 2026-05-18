# Reading Time in nvim-writing-metrics — Design

**Goal:** Add reading-time estimation to `nvim-writing-metrics` so we can delete `nvim-prose` and end up with a net-positive change — accurate Pandoc-stripped word counts, silent + spoken WPM profiles, integration across statusline / full report / dedicated keymap.

## Context

`nvim-prose` is a 60-line plugin installed via lazy.nvim that exposes `word_count()` and `reading_time()` lualine components. Nothing in the user's config consumes it — it was added in October 2025 and orphaned by the custom `nvim-writing-metrics` system. Removal is safe; reading time was the only feature `nvim-prose` had that `nvim-writing-metrics` lacks.

This spec adds reading time directly to `nvim-writing-metrics`, surfaces it in three places, and authorizes the removal of `nvim-prose`.

## Architecture decision

Reading time is a pure derivation of word count (`words / wpm`). It lives alongside the words it derives from — inside `basic.lua` — as two new functions. No new module file. No new lualine component file. The statusline extension piggybacks on the existing writing-metrics component in `lualine-mods.lua`.

## Components

### Configuration (`lua/writing-metrics/config.lua`)

Add a `reading_time` block to the defaults:

```lua
reading_time = {
  enabled = true,                 -- compute reading time at all
  wpm_silent = 200,               -- average silent reading speed
  wpm_spoken = 150,               -- presentation / spoken delivery rate
  statusline = true,              -- show in statusline component
  statusline_profile = "silent",  -- "silent" | "spoken" | "both"
},
```

`enabled = false` short-circuits everything (statusline, report, keymap) — no minutes computed, rows omitted, toast disabled.

### Module API (`lua/writing-metrics/basic.lua`)

Two public functions:

```lua
--- Compute reading time for a buffer.
--- Reads cached words if fresh; otherwise returns nil (caller should
--- trigger an accurate count first if they need a guaranteed value).
--- Returns nil if reading_time.enabled = false or no word count available.
--- @param bufnr integer Buffer to compute for (0 or nil = current buffer)
--- @return table|nil { silent_minutes, spoken_minutes, silent, spoken }
function M.get_reading_time(bufnr)

--- Show a vim.notify toast with both profiles.
--- Triggered by `<leader>mT` and `:ReadingTime`.
--- Computes an accurate count synchronously via the existing pipeline;
--- falls back to fast count if accurate fails.
function M.show_reading_time()
```

The returned table from `get_reading_time`:

```lua
{
  silent_minutes = 5,           -- math.ceil(words / wpm_silent)
  spoken_minutes = 7,           -- math.ceil(words / wpm_spoken)
  silent = "~5 min",            -- pre-formatted for display
  spoken = "~7 min",            -- pre-formatted for display
}
```

Tilde prefix signals approximation (WPM is a model, not a measurement).

### Statusline integration (`~/.config/nvim/lua/plugins/lualine-mods.lua`)

The existing writing-metrics statusline component produces:

```
⚡ 1,247 words  󰬶 7,892 chars
```

Extend it to optionally append reading time:

| `statusline_profile` | Appended |
|---|---|
| `"silent"` (default) | `⏱ ~5 min` |
| `"spoken"` | `🎤 ~7 min` |
| `"both"` | `⏱ ~5/~7 min` |

If `reading_time.statusline = false`, nothing is appended.

The icon for `"both"` uses `⏱` since silent is the primary metric.

Implementation: in the same closure that currently formats the word/char string, call `basic.get_reading_time(bufnr)` and append based on the config. No new lualine component file.

### Full report integration (`lua/writing-metrics/display.lua`)

`format_basic_section` currently renders:

```markdown
## 📊 Basic Statistics

| Metric | Value |
|--------|-------|
| Words | **1,247** |
| Characters | **7,892** |
| Sentences | **65** |
| Paragraphs | **42** |
| Lines | **120** |
```

Append two rows when `reading_time.enabled` is true:

```markdown
| Reading time (silent, 200 wpm) | **~5 min** |
| Reading time (spoken, 150 wpm) | **~7 min** |
```

WPM annotated parenthetically so the values are self-documenting. Both profiles always appear in the report (unlike the statusline, where the default shows one).

### Dedicated keymap & command

**Keymap** registered in `~/.config/nvim/lua/plugins/writing-metrics.lua`:

```lua
{ "<leader>mT", "<cmd>ReadingTime<cr>", desc = "metrics: reading time toast" },
```

`<leader>mT` is the capital-T variant of `<leader>mt` (toggle fast/accurate). Semantically grouped under metrics; keeps the `T` mnemonic for "Time" while avoiding collision.

**Command** registered in `lua/writing-metrics/init.lua` alongside `WordCount` and `ReadabilityReport`:

```lua
vim.api.nvim_create_user_command("ReadingTime", function()
  require("writing-metrics.basic").show_reading_time()
end, { desc = "Show reading time toast" })
```

**Toast format** (vim.notify, INFO level):

```
~5 min silent · ~7 min spoken  (1,247 words at 200/150 wpm)
```

If accurate count fails and we fall back to fast count, prefix with `(fast)`:

```
(fast) ~5 min silent · ~7 min spoken  (1,247 raw words)
```

## Data flow

1. User edits buffer → existing TextChanged/InsertLeave autocmds mark cache stale.
2. Statusline refresh → lualine calls writing-metrics statusline closure → reads cached basic counts → calls `basic.get_reading_time(bufnr)` → appends to displayed string.
3. User presses `<leader>mr` → full report path runs as before → `format_basic_section` reads `data.basic.words` + config WPM → renders two extra table rows.
4. User presses `<leader>mT` → `basic.show_reading_time()` → triggers `get_accurate_count` (uses cache if fresh) → `vim.notify` toast.

Reading time is **never cached separately** — it's recomputed from the cached word count whenever requested. This is free (one division + one ceiling) and avoids cache-invalidation complexity.

## Error handling

- `enabled = false` → all entry points return nil/empty/skip silently.
- No word count yet (fresh buffer, never analyzed) → `get_reading_time` returns nil; statusline omits the reading-time segment; report skips the rows; keymap triggers fast count fallback.
- Buffer invalid → return nil cleanly.
- `wpm_silent` or `wpm_spoken` ≤ 0 → guarded with `if wpm > 0` to prevent division by zero. If invalid, that profile is silently omitted.

## Testing

Existing test infrastructure (plenary.busted) gets two new tests in `tests/basic_spec.lua`:

1. **`get_reading_time` with known word count** — set up a buffer of 400 words, assert `silent_minutes == 2` (400/200) and `spoken_minutes == 3` (math.ceil(400/150)).
2. **`get_reading_time` respects enabled flag** — set `reading_time.enabled = false`, assert function returns nil.

No new test file. The statusline integration, full-report rendering, and keymap are validated by manual smoke test (UI-level, hard to unit-test cleanly).

## Removal of nvim-prose

After the writing-metrics changes are committed and verified:

1. Delete `~/.config/nvim/lua/plugins/nvim-prose.lua`.
2. Run `:Lazy clean` in Neovim — drops `~/.local/share/nvim/lazy/nvim-prose/` and the `lazy-lock.json` entry.
3. Verify nothing else references it: `grep -rn "nvim-prose\|prose_word_count\|prose_reading_time" ~/.config/nvim/ --include="*.lua"` should be empty.

No documentation cleanup needed in `CLAUDE.md` (nvim-prose isn't mentioned there). `OLDCLAUDE.md` references are historical archive — leave alone.

## Files touched

| File | Type of change |
|---|---|
| `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` | Add `reading_time` defaults block |
| `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` | Add `get_reading_time` + `show_reading_time` |
| `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` | Register `:ReadingTime` user command |
| `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua` | Append two rows to `format_basic_section` |
| `~/projects/nvim-writing-metrics/tests/basic_spec.lua` | Two new tests |
| `~/.config/nvim/lua/plugins/lualine-mods.lua` | Extend writing-metrics component with reading-time segment |
| `~/.config/nvim/lua/plugins/writing-metrics.lua` | Add `<leader>mT` keymap |
| `~/.config/nvim/lua/plugins/nvim-prose.lua` | **Delete** (final step) |

## Non-goals

These are explicitly out of scope; if you want them later, they'll be separate work:

- Per-section reading time (e.g., "Abstract: 1 min, Methods: 4 min"). Useful but adds complexity to the report layout.
- Reading-speed comparison ("Reader speed: easy" based on Flesch score). Lives more naturally in the Readability section, not basic stats.
- Configurable format strings (e.g., custom prefix beyond `~`). YAGNI until someone needs it.
- Skim reading profile (third WPM tier). Adds a row that most users won't care about.

## Net gain over nvim-prose

What we gain by doing this and removing nvim-prose:

1. **Accurate prose word count** (Pandoc-stripped) feeding reading time, vs nvim-prose's raw `vim.fn.wordcount()` that counts YAML / code / markup.
2. **Two WPM profiles** (silent + spoken) vs nvim-prose's one. Spoken is useful for grant pitches and poetry readings.
3. **Three visibility tiers** (statusline / dedicated toast / full report) vs nvim-prose's lualine-only.
4. **Config consistency** — reading time options live next to the rest of writing-metrics config, not in a separate plugin's config.
5. **One fewer plugin** to maintain or worry about.

What we lose: nothing the user is actually using.
