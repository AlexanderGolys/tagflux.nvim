local Path = require("fluxtags.path")

local M = {}

local path_utils = Path.new()
local PROJECT_DIR = ".fluxtags"
local PROJECT_FILE = "project.json"

local function join(...)
  return table.concat({ ... }, "/")
end

local function data_root()
  return join(vim.fn.stdpath("data"), "fluxtags", "projects")
end

local function registry_path()
  return join(data_root(), "projects.json")
end

local function sanitize_name(name)
  return (name:gsub("[^%w_.-]", "_"))
end

local function ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

local function read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

local function write_json(path, value)
  ensure_dir(path_utils:dirname(path))
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

local function normalize_project(project)
  if type(project) ~= "table" or type(project.name) ~= "string" or project.name == "" then
    return nil
  end
  project.root = path_utils:absolute(project.root or vim.loop.cwd())
  project.storage = project.storage == "root" and "root" or "data"
  project.id = project.id or sanitize_name(project.name)
  return project
end

local function read_registry()
  local registry = read_json(registry_path()) or { projects = {} }
  registry.projects = registry.projects or {}
  return registry
end

local function write_registry(registry)
  write_json(registry_path(), registry)
end

local function root_project_file(root)
  return join(path_utils:absolute(root), PROJECT_DIR, PROJECT_FILE)
end

local function data_project_file(project_id)
  return join(data_root(), project_id, PROJECT_FILE)
end

local function project_file(project)
  if project.storage == "root" then
    return root_project_file(project.root)
  end
  return data_project_file(project.id)
end

local function find_root_project(start)
  local dir = path_utils:absolute(start or vim.loop.cwd())
  while dir and dir ~= "" do
    local path = root_project_file(dir)
    local project = normalize_project(read_json(path))
    if project then
      return project
    end
    local parent = path_utils:dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
end

local function registry_project_for_root(root)
  local abs_root = path_utils:absolute(root or vim.loop.cwd())
  for _, project in ipairs(read_registry().projects) do
    project = normalize_project(project)
    if project and project.root == abs_root then
      return project
    end
  end
end

---@param root? string
---@return table|nil
function M.current(root)
  return find_root_project(root or vim.loop.cwd()) or registry_project_for_root(root or vim.loop.cwd())
end

---@return table[]
function M.all()
  local projects = {}
  for _, project in ipairs(read_registry().projects) do
    project = normalize_project(project)
    if project then
      table.insert(projects, project)
    end
  end
  table.sort(projects, function(a, b)
    return a.name < b.name
  end)
  return projects
end

---@param name string
---@param storage? string
---@param root? string
---@return table
function M.register(name, storage, root)
  if type(name) ~= "string" or name == "" then
    error("project name is required")
  end

  local project = normalize_project({
    name = name,
    id = sanitize_name(name),
    root = root or vim.loop.cwd(),
    storage = storage == "root" and "root" or "data",
  })

  write_json(project_file(project), project)

  local registry = read_registry()
  local replaced = false
  for i, existing in ipairs(registry.projects) do
    if existing.name == project.name or path_utils:absolute(existing.root or "") == project.root then
      registry.projects[i] = project
      replaced = true
      break
    end
  end
  if not replaced then
    table.insert(registry.projects, project)
  end
  write_registry(registry)

  ensure_dir(M.tag_dir(project))
  return project
end

---@param project table
---@return string
function M.tag_dir(project)
  if project.storage == "root" then
    return join(project.root, PROJECT_DIR, "tags")
  end
  return join(data_root(), project.id, "tags")
end

---@param project table
---@param kind string
---@return string
function M.tagfile(project, kind)
  return join(M.tag_dir(project), ("fluxtags.%s.tags"):format(kind))
end

return M
