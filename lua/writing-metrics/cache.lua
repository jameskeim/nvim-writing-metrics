--- Intelligent caching system for nvim-writing-metrics
--- @module writing-metrics.cache
local M = {}

--- Cache storage structure (single-tier for statusline)
--- @class Cache
--- @field basic table<number, CacheEntry> Basic metrics cache by buffer
local cache = {
  basic = {},
}

--- Cache entry structure
--- @class CacheEntry
--- @field content_hash string Hash of buffer content
--- @field timestamp number Unix timestamp
--- @field data table Metrics data

--- Get current timestamp in milliseconds
--- @return number
local function now()
  return vim.loop.now()
end

--- Check if a cache entry is still valid
--- @param entry CacheEntry|nil Cache entry
--- @param ttl number Time-to-live in milliseconds
--- @return boolean
function M.is_valid(entry, ttl)
  if not entry then
    return false
  end

  local age = now() - entry.timestamp
  return age < ttl
end

--- Get the current content hash for a buffer
--- @param bufnr number Buffer number
--- @return string Content hash
local function get_current_hash(bufnr)
  local utils = require("writing-metrics.utils")
  return utils.get_content_hash(bufnr)
end

--- Get basic metrics from cache
--- Content-based caching (like Vim's native wordcount):
--- - Cache is valid as long as buffer content hasn't changed
--- - No time-based expiration (TTL ignored for validation)
--- - Autocmds invalidate cache on actual text changes
--- @param bufnr number Buffer number
--- @return table|nil Basic metrics if cached
--- @return boolean True if cache is stale (content changed)
function M.get_basic(bufnr)
  local basic_entry = cache.basic[bufnr]

  -- Return cached data with staleness flag
  if basic_entry then
    return basic_entry.data, (basic_entry.stale or false)
  end

  -- No cache found
  return nil, false
end

--- Store basic metrics in cache
--- @param bufnr number Buffer number
--- @param data table Basic metrics data
function M.set_basic(bufnr, data)
  local current_hash = get_current_hash(bufnr)

  cache.basic[bufnr] = {
    content_hash = current_hash,
    timestamp = now(),
    data = data,
    stale = false,  -- Fresh data
  }
end

--- Invalidate cache for a specific buffer
--- Marks cache as stale instead of deleting to preserve last known count
--- @param bufnr number Buffer number
function M.invalidate(bufnr)
  if cache.basic[bufnr] then
    cache.basic[bufnr].stale = true  -- Mark stale, don't delete
  end
end

--- Permanently remove all cached entries for a buffer.
--- Called on BufDelete/BufWipeout to prevent unbounded cache growth.
--- Unlike invalidate (which marks stale for content changes), this is for buffer lifetime.
--- @param bufnr number Buffer number
function M.remove(bufnr)
  cache.basic[bufnr] = nil
end

--- Clear all caches (useful for testing or low memory situations)
function M.clear_all()
  cache.basic = {}
end

--- Get cache statistics for debugging
--- @return table Cache stats
function M.get_stats()
  local basic_count = 0

  for _ in pairs(cache.basic) do
    basic_count = basic_count + 1
  end

  return {
    basic_entries = basic_count,
  }
end

--- Get comprehensive cache statistics
--- @return table Statistics including cache size and memory usage
function M.get_statistics()
  local config = require("writing-metrics.config")
  local basic_count = 0
  local basic_memory = 0

  -- Count entries and estimate memory
  for _, entry in pairs(cache.basic) do
    basic_count = basic_count + 1
    -- Rough memory estimate: hash (32 bytes) + timestamp (8 bytes) + data (estimate 200 bytes)
    basic_memory = basic_memory + 240
  end

  return {
    basic = {
      count = basic_count,
      memory = basic_memory,
      ttl = config.config.cache.basic_ttl,
    },
  }
end

--- Check if content has changed since last cache
--- @param bufnr number Buffer number
--- @return boolean True if content changed
function M.content_changed(bufnr)
  local current_hash = get_current_hash(bufnr)

  -- Check basic cache
  local basic_entry = cache.basic[bufnr]
  if basic_entry and basic_entry.content_hash == current_hash then
    return false
  end

  return true
end

--- Setup cache invalidation autocmds
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup("WritingMetricsCache", { clear = true })

  -- Invalidate cache on text changes (only for writing filetypes)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    callback = function(args)
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      local utils = require("writing-metrics.utils")

      -- Only process writing filetypes
      if not utils.is_writing_filetype(ft) then
        return
      end

      -- Only invalidate if content actually changed
      if M.content_changed(args.buf) then
        M.invalidate(args.buf)
      end
    end,
  })

  -- Also invalidate on buffer write (ensures metrics reflect saved state)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      local utils = require("writing-metrics.utils")

      -- Only process writing filetypes
      if utils.is_writing_filetype(ft) then
        M.invalidate(args.buf)
      end
    end,
  })

  -- Clean up cache when buffer is deleted to prevent memory leaks
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      M.remove(args.buf)
    end,
  })

  -- Optional: Periodic cleanup of stale entries (every 5 minutes)
  local timer = vim.loop.new_timer()
  timer:start(
    300000,
    300000,
    vim.schedule_wrap(function()
      M.cleanup_stale_entries()
    end)
  )
end

--- Clean up cache entries for buffers that no longer exist
function M.cleanup_stale_entries()
  local valid_buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      valid_buffers[bufnr] = true
    end
  end

  -- Remove entries for invalid buffers
  for bufnr in pairs(cache.basic) do
    if not valid_buffers[bufnr] then
      cache.basic[bufnr] = nil
    end
  end
end

--- Debug function to inspect cache contents
--- @param bufnr number|nil Buffer number (nil for all)
--- @return table Cache contents
function M.inspect(bufnr)
  if bufnr then
    return {
      basic = cache.basic[bufnr],
      current_hash = get_current_hash(bufnr),
    }
  else
    return {
      basic = cache.basic,
      stats = M.get_stats(),
    }
  end
end

-- Manual testing:
-- :lua require("writing-metrics.cache").setup_autocmds()
-- :lua print(vim.inspect(require("writing-metrics.cache").get_stats()))
-- :lua print(vim.inspect(require("writing-metrics.cache").inspect(0)))
-- :lua require("writing-metrics.cache").invalidate(0)
-- :lua require("writing-metrics.cache").clear_all()

return M
