--!nonstrict
-- Deliberately uses the common Lua/Luau subset so installed Lua can test this
-- exact source. No compositor defaults, selectors, processes or UI live here.
local M = {}
local families = { "workspaces", "windows", "outputs" }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
M.copy = copy

function M.new()
    return { generation = 0, revision = 0, status = "stopped", ready = false,
        received = {}, snapshots = { workspaces = {}, windows = {}, outputs = {} },
        invalidEvents = 0, error = nil }
end

local function clear(s, status, generation)
    s.generation = generation or s.generation
    s.status, s.ready, s.received = status, false, {}
    s.snapshots = { workspaces = {}, windows = {}, outputs = {} }
    s.revision = s.revision + 1
end

function M.transport(s, status, generation)
    if type(generation) ~= "number" or generation % 1 ~= 0 or generation < s.generation then
        return false
    end
    if status == "connected" then
        if generation <= s.generation then return false end
        clear(s, "synchronizing", generation)
        s.error = nil
    elseif status == "connecting" or status == "disconnected" or status == "stopped" then
        clear(s, status, generation)
    else
        return false
    end
    return true
end

function M.liveness(s, alive)
    if not alive and (s.status == "ready" or s.status == "synchronizing") then
        s.ready, s.status, s.error = false, "unresponsive", "reader_unresponsive"
    elseif alive and s.status == "unresponsive" then
        s.ready = true
        for _, name in ipairs(families) do s.ready = s.ready and s.received[name] == true end
        s.status, s.error = s.ready and "ready" or "synchronizing", nil
    else return false end
    s.revision = s.revision + 1
    return true
end

local function stringField(row, key, empty)
    return type(row[key]) == "string" and (empty or row[key] ~= "")
end

local function validRow(family, row)
    if type(row) ~= "table" then return false end
    if family == "outputs" then
        return stringField(row, "name") and type(row.enabled) == "boolean"
            and type(row.focused) == "boolean" and stringField(row, "active_workspace", true)
    end
    if not stringField(row, "id") then return false end
    if family == "workspaces" then
        return stringField(row, "name", true) and type(row.named) == "boolean"
            and stringField(row, "output") and type(row.index) == "number"
            and row.index >= 1 and row.index % 1 == 0
            and type(row.active) == "boolean" and type(row.focused) == "boolean"
            and type(row.occupied) == "boolean" and type(row.window_count) == "number"
            and row.window_count >= 0 and row.window_count % 1 == 0
            and stringField(row, "focused_window", true)
    end
    return stringField(row, "workspace", true) and stringField(row, "output", true)
        and stringField(row, "app_id", true) and type(row.active) == "boolean"
        and type(row.focused) == "boolean" and type(row.pinned) == "boolean"
        and type(row.minimized) == "boolean"
end

local function validSnapshot(family, data)
    if type(data) ~= "table" then return false end
    local n, seen = 0, {}
    for k, row in pairs(data) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or not validRow(family, row) then
            return false
        end
        local id = family == "outputs" and row.name or row.id
        if seen[id] then return false end
        seen[id], n = true, n + 1
    end
    for i = 1, n do if data[i] == nil then return false end end
    return true
end

function M.invalid(s, family)
    s.invalidEvents = s.invalidEvents + 1
    s.error = "invalid_event" -- Never retain raw IPC, titles or server errors here.
    if s.snapshots[family] ~= nil then
        s.received[family] = nil
        s.ready, s.status = false, "synchronizing"
    end
    s.revision = s.revision + 1
end

function M.apply(s, event, generation)
    if generation ~= s.generation or (s.status ~= "synchronizing" and s.status ~= "ready") then
        return false
    end
    if type(event) ~= "table" or s.snapshots[event.event] == nil then
        M.invalid(s)
        return false
    end
    local family = event.event
    if not validSnapshot(family, event.data) then
        M.invalid(s, family)
        return false
    end
    s.snapshots[family] = copy(event.data) -- Replacement, never a delta merge.
    s.received[family] = true
    s.ready = true
    for _, name in ipairs(families) do s.ready = s.ready and s.received[name] == true end
    s.status = s.ready and "ready" or "synchronizing"
    s.error = nil
    s.revision = s.revision + 1
    return true
end

function M.view(s)
    local v = { generation = s.generation, revision = s.revision, ready = s.ready,
        status = s.status, error = s.error, invalidEvents = s.invalidEvents,
        received = copy(s.received), workspaces = {}, windows = {}, outputs = {},
        workspaceOrder = {}, windowOrder = {}, outputOrder = {}, byOutput = {},
        unassignedWindowIds = {}, orphanWorkspaceIds = {},
        focus = { activeWindowIds = {}, focusedWorkspaceIds = {}, focusedOutputNames = {} } }
    for _, output in ipairs(s.snapshots.outputs) do
        v.outputs[output.name] = copy(output)
        table.insert(v.outputOrder, output.name)
        v.byOutput[output.name] = { workspaceIds = {}, windowIds = {} }
        if output.focused then table.insert(v.focus.focusedOutputNames, output.name) end
    end
    for _, workspace in ipairs(s.snapshots.workspaces) do
        local w = copy(workspace)
        w.windowIds = {}
        v.workspaces[w.id] = w
        table.insert(v.workspaceOrder, w.id)
        local group = v.byOutput[w.output]
        if group then table.insert(group.workspaceIds, w.id)
        else table.insert(v.orphanWorkspaceIds, w.id) end
        if w.focused then table.insert(v.focus.focusedWorkspaceIds, w.id) end
    end
    -- Sort only within an output by compositor-provided position; ties preserve
    -- incoming order. IDs and labels do not participate in ordering.
    local rank = {}
    for i, id in ipairs(v.workspaceOrder) do rank[id] = i end
    for _, group in pairs(v.byOutput) do
        table.sort(group.workspaceIds, function(a, b)
            local ai, bi = v.workspaces[a].index, v.workspaces[b].index
            return ai < bi or (ai == bi and rank[a] < rank[b])
        end)
    end
    for _, window in ipairs(s.snapshots.windows) do
        local w = copy(window)
        v.windows[w.id] = w
        table.insert(v.windowOrder, w.id)
        if v.byOutput[w.output] then table.insert(v.byOutput[w.output].windowIds, w.id) end
        if v.workspaces[w.workspace] then
            table.insert(v.workspaces[w.workspace].windowIds, w.id)
        else table.insert(v.unassignedWindowIds, w.id) end
        if w.active then table.insert(v.focus.activeWindowIds, w.id) end
    end
    if #v.focus.activeWindowIds == 1 then v.focus.activeWindowId = v.focus.activeWindowIds[1] end
    for _, w in pairs(v.workspaces) do
        -- Preserve the raw remembered ID even while snapshot families disagree.
        local focused = v.windows[w.focused_window]
        if focused and focused.workspace == w.id and focused.output == w.output then
            w.rememberedWindowId = focused.id
        end
    end
    return v
end

function M.reference(v, kind, id)
    local collection = kind == "workspace" and v.workspaces or kind == "window" and v.windows
    if not v.ready or not collection or not collection[id] then return nil end
    return { kind = kind, id = id, generation = v.generation }
end

function M.resolve(v, ref)
    if not v.ready or type(ref) ~= "table" or ref.generation ~= v.generation then return nil end
    local collection = ref.kind == "workspace" and v.workspaces or ref.kind == "window" and v.windows
    local row = collection and collection[ref.id]
    if not row or not v.outputs[row.output] or not v.outputs[row.output].enabled then return nil end
    if ref.kind == "window" then
        local workspace = v.workspaces[row.workspace]
        if not workspace or workspace.output ~= row.output then return nil end
    end
    return copy(row) -- State lookup only. This module cannot dispatch actions.
end

return M
