--!nonstrict
local M = {}
function M.workspace(view, reference)
    if type(view) ~= "table" or not view.ready or type(reference) ~= "table"
        or reference.generation ~= view.generation then return nil end
    local w = view.workspaces[reference.id]
    if not w or w.output ~= reference.output or not view.outputs[w.output]
        or not view.outputs[w.output].enabled then return nil end
    return w
end
function M.token(view, reference, windowId)
    local w = M.workspace(view, reference)
    if not w then return nil end
    if windowId then
        local window = view.windows[windowId]
        if not window or window.workspace ~= w.id or window.output ~= w.output then return nil end
    end
    return { kind = windowId and "window" or "workspace", id = w.id, output = w.output,
        name = w.name, named = w.named, index = w.index, window = windowId }
end
function M.send(view, reference, windowId, host, callback)
    local token = M.token(view, reference, windowId)
    if not token then return false end
    local encoded = host.json.encode(token)
    local directory = host.pluginDir()
    if not encoded or not directory then return false end
    return host.runAsync({ "python3", "-B", directory .. "/action_request.py", encoded }, function(result)
        if callback then callback(result.exitCode == 0 and not result.timedOut) end
    end, 4000)
end
function M.rows(view, reference)
    local workspace = M.workspace(view, reference)
    if not workspace then return nil end
    local rows = {}
    for _, id in ipairs(workspace.windowIds) do
        local w = view.windows[id]
        if w and w.workspace == workspace.id and w.output == workspace.output then
            table.insert(rows, { id = id, appId = w.app_id, title = w.title or "", active = w.active, urgent = w.urgent })
        end
    end
    return rows, workspace
end
return M
