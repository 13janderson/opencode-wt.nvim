local Path = require("plenary.path")

local State = {}
State.__index = State

State.state_dir = tostring(Path:new(vim.fn.stdpath("data"), "opencode-wt"))
State.state_file = tostring(Path:new(State.state_dir, "sessions.json"))

local function safe_json_decode(raw, label)
  local ok, result = pcall(vim.json.decode, raw)
  if not ok then
    vim.notify(
      "[opencode-wt] JSON decode failed for " .. label .. ":\n" .. tostring(result) .. "\nRaw:\n" .. tostring(raw),
      vim.log.levels.ERROR
    )
    return nil
  end
  if type(result) ~= "table" then
    vim.notify(
      "[opencode-wt] JSON decode returned non-table for " .. label .. ":\n" .. vim.inspect(result),
      vim.log.levels.ERROR
    )
    return nil
  end
  return result
end

State.safe_json_decode = safe_json_decode

function State:new()
  local obj = setmetatable({}, self)
  obj.data = obj:read()
  return obj
end

function State:read()
  local read_ok, content = pcall(function()
    return Path:new(self.state_file):read()
  end)
  if not read_ok or not content or content == "" then
    return {}
  end

  local decoded = safe_json_decode(content, "state file (" .. self.state_file .. ")")
  if not decoded then
    return {}
  end
  return decoded
end

function State:write()
  Path:new(self.state_dir):mkdir({ parents = true, mode = 493 })
  Path:new(self.state_file):write(vim.json.encode(self.data), "w")
end

function State:get_session(path)
  if self.data[path] then
    return self.data[path].session_id
  end
  return nil
end

function State:validate_session(path)
  local saved_id = self:get_session(path)
  if not saved_id then
    return nil
  end

  local ok, output = pcall(function()
    return vim.fn.system("opencode session list --format json -n 50")
  end)
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end

  local sessions = safe_json_decode(output, "opencode session list")
  if not sessions then
    self:remove_session(path)
    return nil
  end

  for _, session in ipairs(sessions) do
    if session.id == saved_id then
      return saved_id
    end
  end

  self:remove_session(path)
  return nil
end

function State:set_session(path, session_id)
  self.data[path] = self.data[path] or {}
  self.data[path].session_id = session_id
  self:write()
end

function State:remove_session(path)
  self.data[path] = nil
  self:write()
end

function State:refresh_session(path)
  local ok, output = pcall(function()
    return vim.fn.system("opencode session list --format json -n 50")
  end)
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end

  local sessions = safe_json_decode(output, "opencode session list")
  if not sessions then
    return nil
  end

  for _, session in ipairs(sessions) do
    if session.directory == path then
      self:set_session(path, session.id)
      return session.id
    end
  end
  return nil
end

local the_state = State:new()
return the_state