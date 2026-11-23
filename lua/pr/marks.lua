local M = {}

local file = vim.fs.joinpath(vim.fn.stdpath "state", "pr-marks.json")
local store

local function load()
  if store then return store end
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(file), "\n")) end)
  store = ok and type(data) == "table" and data or {}
  return store
end

local function save(root, numbers)
  load()[root] = numbers[1] and numbers or nil
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  vim.fn.writefile({ vim.json.encode(store) }, file)
end

function M.list(root) return load()[root] or {} end

function M.slots(root)
  local slots = {}
  for slot, number in ipairs(M.list(root)) do
    slots[number] = slot
  end
  return slots
end

function M.toggle(root, number)
  local numbers = vim.tbl_filter(function(n) return n ~= number end, M.list(root))
  if #numbers == #M.list(root) then numbers[#numbers + 1] = number end
  save(root, numbers)
end

function M.keep(root, prs)
  local open = {}
  for _, pr in ipairs(prs) do
    open[pr.number] = true
  end
  local numbers = vim.tbl_filter(function(n) return open[n] end, M.list(root))
  if #numbers ~= #M.list(root) then save(root, numbers) end
end

return M
