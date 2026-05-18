# Plan I — Architecture Docs Sweep (Post-Plan-H Sync)

**Date:** 2026-05-18
**Status:** Design (awaiting implementation plan)
**Target repo:** `~/projects/nvim-writing-metrics/`
**Affects:** `docs/CORE_MODULES.md`, `docs/DESIGN_INNOVATIONS.md`, `docs/MODULE_FLOW.md` (doc-only; no production code)

---

## Problem

After Plans C/E/F/G/H landed in `nvim-writing-metrics`, the three architecture docs in `docs/` drifted from the code. An audit identified 11 stale references; a fresh re-audit during brainstorming added 3 closely-related items in the same files. The docs now misrepresent:

- The module inventory (no mention of `commands.lua`, which Plan F extracted)
- The `_G.accurate_wordcount` contract (described as function-only, but Plan F made it a callable table with both function and table contracts)
- The cache strategy (flow diagrams still show full-mode caching that was deliberately removed)
- The roadmap (`Next Steps` lists Tracks 3-7 as future work; all five have shipped)
- A measurement claim (`30x faster startup`) whose specific numbers were never re-verified after Plan F restructured `setup()`
- Several smaller items: missing `M.get()` accessor, missing `commands.enable_legacy` default, undocumented `filter.auto_detect` semantics, stale "pre-existing failure cluster" testing note (suite is 118/0 after Plan H), and a `vim.loop.hrtime()` example that contradicts the Plan-C `vim.uv.*` migration.

The drift is bounded: three files, ~17 atomic edits, no production code involved.

## Scope

**In scope:** 17 atomic doc edits across 3 files in `~/projects/nvim-writing-metrics/docs/`. (The 14 findings in the Problem section above map to 17 edits because the missing `commands.lua` finding alone requires multiple atomic edits — architecture diagram, new §5 section, module statistics update, dependency graph, init sequence, and the init.lua delegation note.)

**Out of scope:**
- Test files (the 3 remaining `tests/` luacheck warnings are tracked here as Plan J)
- Stylua reconciliation (the 7 stylua diffs vs column-aligned comments — tracked as Plan K)
- Any production-code change
- Other docs (`README.md`, `MIGRATION.md`, `FEATURE_MAPPING.md`, etc.) — not in the audit and outside this bounded scope

## Design Decisions (Locked)

The following decisions were locked in during brainstorming and drive the per-file edit lists below.

### D1. `commands.lua` gets a full parallel §5 section in CORE_MODULES.md

It is a peer module, not a sub-component of `init.lua`. The architecture diagram, dependency graph, and initialization sequence in MODULE_FLOW.md all integrate `commands.lua` parallel to the other modules.

### D2. MODULE_FLOW.md Flow 2 — lean replacement + brief "Why" note

Strip the stale `Check full cache → Return immediately` / `Store in cache (cache.set_full)` branches. Show the actual flow (always compute fresh). Add 2-3 lines below the diagram explaining the no-full-cache decision inline, because "we cache basic mode but not full mode" is a counter-intuitive asymmetry that readers will ask about. Mild duplication with `cache.lua`'s docstring and CORE_MODULES.md's "What's NOT cached" note is accepted for the inline-clarity benefit.

### D3. `_G.accurate_wordcount` — document the full contract

Both contracts are public after Plan F:
- Function form: `_G.accurate_wordcount()` returns cached word count (lualine consumers)
- Table form: `_G.accurate_wordcount.<method>(bufnr)` exposes 8 methods forwarded from the `basic` module

Doc updates (in both CORE_MODULES.md §Backward Compatibility and DESIGN_INNOVATIONS.md §5) show the `setmetatable({ ... methods ... }, { __call = ... })` form with a comment naming both contracts.

### D4. "30x faster startup" measurement — delete the entire subsection

Drop lines 155-174 of DESIGN_INNOVATIONS.md (the eager/lazy benchmark code block and the "30x faster startup!" headline). Keep the Benefits bullets above the deleted block. Rationale: the qualitative claim (lazy loading helps) is still true and remains documented in the Benefits list; the specific numbers were never re-measured after Plan F and would be misleading to keep. Side effect: this also resolves the stale `vim.loop.hrtime()` example, since it lived inside the deleted block.

### D5. `Next Steps` section — replace with realistic Future Work

Four concrete items, all live in the user's head as work-to-track:
1. **Plan J — tests/ luacheck cleanup.** Close the 3 remaining warnings in `tests/` that were scoped out of Plan H.
2. **Plan K — stylua reconciliation.** Decide whether to keep column-aligned comments and live with 7 stylua diffs, or run `stylua lua/` and accept the formatting loss.
3. **filter.auto_detect simplification.** Evaluate whether the `auto_detect=true|false` toggle adds enough value to justify the configuration surface. (Distinct from edit #5 below, which only documents the toggle's current semantics — this future-work item asks whether the toggle should exist at all.)
4. **`:checkhealth` completeness audit.** Verify `:checkhealth writing-metrics` exercises the full dep chain (Pandoc version, filter path, autocmd registration, command registration) post-Plan-F.

## Per-File Edit Lists

### `docs/CORE_MODULES.md` (10 atomic edits)

| # | Location | Change |
|---|---|---|
| 1 | Line 3 ("four core modules") + lines 7-16 (architecture box) | Reframe as "core modules" (drop count); add `commands.lua` to the box |
| 2 | §1 init.lua, around line 26 | Add one-line note: `setup()` delegates command registration to `commands.lua` |
| 3 | §1 init.lua, line 39 | Update `_G.accurate_wordcount` description: callable table (call → cached count, table → basic-module methods) |
| 4 | §2 config.lua Key Functions, after line 63 | Add `M.get()` — returns resolved config (used by other modules to read merged opts) |
| 5 | §2 config.lua defaults block (lines 67-103, the `M.defaults = {…}` literal) | Add a sibling `commands = { enable_legacy = true }` entry; add inline comment on `filter.auto_detect` semantics (false = trust user path unconditionally). Insertion point for `commands` block: implementer's choice, but recommend placing between `filter` and the closing brace. |
| 6 | New §5 (after §4 utils.lua, around line 196) | Full `commands.lua` section per D1: signature, command list, legacy gating, dependencies |
| 7 | §Design Decisions §5 Backward Compatibility, lines 263-270 | Replace function-only `_G.accurate_wordcount` snippet with the callable-table form per D3 |
| 8 | §Testing, line 295 | Drop the "pre-existing failure cluster in basic_spec.lua and full_spec.lua" sentence (suite is 118/0 post-Plan H) |
| 9 | §Module Statistics, line 379 | Update line-count and module list to include `commands.lua` (verify exact figure at write time via `wc -l lua/writing-metrics/*.lua`) |
| 10 | §Next Steps, lines 367-376 | Replace with §Future Work listing the 4 items from D5 |

### `docs/DESIGN_INNOVATIONS.md` (2 atomic edits)

| # | Location | Change |
|---|---|---|
| 11 | §4 Lazy Module Loading, lines 155-174 | Delete the "Measurement" subsection entirely per D4. Keep the Benefits bullets above; close the section after them. Side effect: removes stale `vim.loop.hrtime()` example. |
| 12 | §5 Backward Compatibility Shims, lines 184-216 | Replace function-only `_G.accurate_wordcount` snippet with callable-table form per D3. Show both contracts (call form + 8-method table). |

### `docs/MODULE_FLOW.md` (5 atomic edits)

| # | Location | Change |
|---|---|---|
| 13 | Architecture diagram, lines 22-28 | Add a `commands` box parallel to config/cache/utils |
| 14 | Flow 1, lines 53-58 | Strip the "Basic cache expired? → Check full cache (smart optimization!) → Extract basic metrics" branch. Remaining flow: cache hit (changedtick match) → return cached; miss → return last-known + trigger background update |
| 15 | Flow 2, lines 80-114 | Replace per D2: lean diagram showing always-fresh path, plus 2-3 line "Why" note below |
| 16 | Module Dependencies, lines 177-192 | Add `commands.lua` entry: depends on init/config; provides user-command registration |
| 17 | Initialization Sequence, lines 251-272 | Add `commands.setup_commands(cfg)` step after cache autocmd setup. Aligns with init.lua's actual `setup()` order. |

## Verification

Doc-only work has no test harness; verification is disciplined self-checks at write time:

1. **Cross-check against HEAD source.** Every claim that names a function, default value, signature, or line count must match the code at the time of writing. Per touched section: open the relevant source file, verify the claim, then write the doc.
2. **Stale-term grep after edits.** Once all edits are in, grep the three files for: `four core modules`, `30x faster`, `pre-existing failure cluster`, `vim.loop`, `set_full`, `cache.get_full`, `Track 3`, `Track 4`, `Track 5`, `Track 6`, `Track 7`. All should return zero hits.
3. **Fresh-reader pass.** Read each modified section straight through, without codebase context, and confirm someone new to the project would understand it. Catches new ambiguity introduced by the edits.

## Commit Strategy

**Single commit** in `~/projects/nvim-writing-metrics/`. All edits share one motivation (sync with post-Plan-H state), all three files are touched together, doc-only changes carry near-zero functional risk. Splitting by file would force any future revert to reason about which file's docs were the wrong one; splitting by edit (17 commits) is overkill.

Suggested commit message:

```
docs: sync architecture docs with post-Plan-H state (Plan I)

Closes 11 audit items + 3 adjacent stale claims across CORE_MODULES.md,
DESIGN_INNOVATIONS.md, MODULE_FLOW.md:
- Adds commands.lua module section and integrates it into the
  architecture diagram, dependency graph, and init sequence
- Updates _G.accurate_wordcount snippets to reflect the callable-table
  contract introduced in Plan F (both call form and 8-method table form)
- Removes stale full-mode cache flows from MODULE_FLOW.md Flow 1 + 2;
  adds 'why no full cache' note to Flow 2
- Drops the stale '30x faster startup' measurement subsection (numbers
  were unverified after Plan F's setup() refactor)
- Documents M.get() accessor, commands.enable_legacy default, and
  filter.auto_detect semantics
- Replaces stale 'Next Steps' (Track 3/4/5/6/7 — all shipped) with a
  Future Work list (Plan J, Plan K, auto_detect simplification,
  checkhealth audit)
- Updates Module Statistics line count to include commands.lua
- Drops stale 'pre-existing failure cluster' claim (suite is 118/0
  after Plan H)
```

## Risk Profile

Doc-only, no functional code touched, no production-runtime impact. Worst case is a typo or a misleading sentence — both caught in fresh-reader pass plus the user spec-review gate. No branch isolation needed.
