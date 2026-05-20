--!strict
-- Extract scripts from a Roblox .rbxl/.rbxlx into Rojo-compatible folder structure.
--
-- Reads the path mapping from default.project.json so we know which instance
-- paths get dumped where on disk:
--     ServerScriptService.Server   -> src/server
--     ReplicatedStorage.Shared     -> src/shared
--     StarterPlayer.StarterPlayerScripts.Client -> src/client
--
-- Script instances become .luau files; folders become directories. Script
-- instances WITH children become folders with an init.{server,client,}luau
-- inside. Non-script Instances (Parts, Models, etc.) are skipped.
--
-- Usage:
--     lune run scripts/extract.luau deathmatch.rbxl
-- or:
--     lune run scripts/extract.luau Deathmatch.rbxlx

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

-- ---- Configuration ----

local SCRIPT_EXTS: { [string]: string } = {
	Script = ".server.luau",
	LocalScript = ".client.luau",
	ModuleScript = ".luau",
}

-- ---- Argument parsing ----

local args = process.args
if #args < 1 then
	print("Usage: lune run scripts/extract.luau <file.rbxl|.rbxlx>")
	process.exit(1)
	return
end

local placeFile = args[1]
if not fs.isFile(placeFile) then
	print("File not found: " .. placeFile)
	process.exit(1)
	return
end

-- Project root = parent dir of this script's parent (i.e. one level up from `scripts/`)
local cwd = process.cwd
-- process.cwd ends with `/` per lune docs
local projectRoot = cwd
if string.sub(projectRoot, -1) == "/" then
	projectRoot = string.sub(projectRoot, 1, -2)
end

-- ---- Load Rojo project mapping ----

local projectJsonPath = projectRoot .. "/default.project.json"
if not fs.isFile(projectJsonPath) then
	print("default.project.json not found at " .. projectJsonPath)
	process.exit(1)
	return
end

local projectJson = serde.decode("json", fs.readFile(projectJsonPath))
type Mapping = { instancePath: { string }, diskPath: string }
local mappings: { Mapping } = {}

local function walkProjectTree(node: any, pathSoFar: { string })
	if typeof(node) ~= "table" then
		return
	end
	if node["$path"] then
		table.insert(mappings, {
			instancePath = pathSoFar,
			diskPath = projectRoot .. "/" .. node["$path"],
		})
		return
	end
	for key, value in node do
		if string.sub(key, 1, 1) ~= "$" then
			local newPath = table.clone(pathSoFar)
			table.insert(newPath, key)
			walkProjectTree(value, newPath)
		end
	end
end

walkProjectTree(projectJson.tree, {})

print("Project root: " .. projectRoot)
print("Mappings loaded:")
for _, m in mappings do
	print(string.format("  %s -> %s", table.concat(m.instancePath, "."), m.diskPath))
end

-- ---- Read & deserialize the place file ----

print("\nReading: " .. placeFile)
local placeBytes = fs.readFile(placeFile)
local game = roblox.deserializePlace(placeBytes)
print("Place loaded. Top-level service count: " .. #game:GetChildren())

-- ---- Helpers ----

local function ensureDir(path: string)
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

local function ensureParentDir(path: string)
	-- Strip filename, mkdir -p the dir
	local lastSlash = nil
	for i = #path, 1, -1 do
		if string.sub(path, i, i) == "/" then
			lastSlash = i
			break
		end
	end
	if not lastSlash then return end
	local dir = string.sub(path, 1, lastSlash - 1)
	-- Recursive mkdir
	local parts = {}
	for part in string.gmatch(dir, "[^/]+") do
		table.insert(parts, part)
	end
	local acc = ""
	for _, p in parts do
		acc = acc .. "/" .. p
		if not fs.isDir(acc) then
			fs.writeDir(acc)
		end
	end
end

local function normalizeNewlines(s: string): string
	-- Roblox source sometimes has CRLF; LF-only for consistency on disk.
	s = string.gsub(s, "\r\n", "\n")
	s = string.gsub(s, "\r", "\n")
	if string.sub(s, -1) ~= "\n" then
		s = s .. "\n"
	end
	return s
end

local function writeFile(path: string, content: string)
	ensureParentDir(path)
	fs.writeFile(path, normalizeNewlines(content))
end

local function findChildByName(instance: any, name: string): any?
	for _, child in instance:GetChildren() do
		if child.Name == name then
			return child
		end
	end
	return nil
end

local function isScript(className: string): boolean
	return SCRIPT_EXTS[className] ~= nil
end

local function hasScriptDescendant(instance: any): boolean
	for _, child in instance:GetChildren() do
		if isScript(child.ClassName) then return true end
		if hasScriptDescendant(child) then return true end
	end
	return false
end

local function isRelevant(instance: any): boolean
	local cls = instance.ClassName
	if isScript(cls) or cls == "Folder" then return true end
	return hasScriptDescendant(instance)
end

-- ---- Extraction ----

local fileCount = 0

local function extractInto(instance: any, destFolder: string, isRootMapping: boolean)
	local cls = instance.ClassName
	local name = instance.Name
	local children = instance:GetChildren()
	local relevantChildren: { any } = {}
	for _, c in children do
		if isRelevant(c) then
			table.insert(relevantChildren, c)
		end
	end
	local hasChildren = #relevantChildren > 0
	local isScr = isScript(cls)

	if isRootMapping then
		ensureDir(destFolder)
		if isScr then
			local ext = SCRIPT_EXTS[cls]
			local source = instance.Source or ""
			writeFile(destFolder .. "/init" .. ext, source)
			fileCount += 1
		end
		for _, c in relevantChildren do
			recurseChild(c, destFolder)
		end
		return
	end

	if isScr and not hasChildren then
		-- Leaf script
		local ext = SCRIPT_EXTS[cls]
		writeFile(destFolder .. "/" .. name .. ext, instance.Source or "")
		fileCount += 1
		return
	end

	if isScr and hasChildren then
		-- Script with children → folder + init file
		local sub = destFolder .. "/" .. name
		ensureDir(sub)
		local ext = SCRIPT_EXTS[cls]
		writeFile(sub .. "/init" .. ext, instance.Source or "")
		fileCount += 1
		for _, c in relevantChildren do
			recurseChild(c, sub)
		end
		return
	end

	if cls == "Folder" then
		local sub = destFolder .. "/" .. name
		ensureDir(sub)
		for _, c in relevantChildren do
			recurseChild(c, sub)
		end
		return
	end

	-- Non-script, non-folder instance that contains scripts — recurse into a
	-- folder so they're still extracted but the parent geometry is skipped.
	if hasScriptDescendant(instance) then
		local sub = destFolder .. "/" .. name
		ensureDir(sub)
		for _, c in relevantChildren do
			recurseChild(c, sub)
		end
	end
end

function recurseChild(instance: any, parentFolder: string)
	extractInto(instance, parentFolder, false)
end

-- ---- Apply each mapping ----

print("\nExtracting...")
for _, m in mappings do
	-- Walk from `game` down each mapping path segment
	local current: any = game
	local ok = true
	for _, segment in m.instancePath do
		local found = findChildByName(current, segment)
		if not found then
			-- Try service lookup by class
			for _, c in current:GetChildren() do
				if c.ClassName == segment then
					found = c
					break
				end
			end
		end
		if not found then
			ok = false
			break
		end
		current = found
	end
	if not ok then
		print(string.format("  ⚠️  Skipping %s — instance path not found in place",
			table.concat(m.instancePath, ".")))
		continue
	end
	local before = fileCount
	extractInto(current, m.diskPath, true)
	print(string.format("  ✓ %s -> %s (%d files)",
		table.concat(m.instancePath, "."), m.diskPath, fileCount - before))
end

print(string.format("\nTotal files written: %d", fileCount))
