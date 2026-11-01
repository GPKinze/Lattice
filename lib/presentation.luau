--!nonstrict
-- Pure data preparation. No labels are derived, shortened or substituted.
local M = {}

function M.forOutput(view, outputName)
    local group = view.byOutput[outputName]
    local result = { output = outputName, ready = view.ready and group ~= nil,
        generation = view.generation, revision = view.revision, workspaces = {} }
    if not group then return result end
    for _, id in ipairs(group.workspaceIds) do
        local w = view.workspaces[id]
        local item = { id = w.id, name = w.name, named = w.named, index = w.index,
            output = w.output, active = w.active, focused = w.focused,
            occupied = w.occupied, windowCount = w.window_count, urgent = w.urgent,
            rememberedWindowId = w.rememberedWindowId, windows = {} }
        for _, windowId in ipairs(w.windowIds) do
            local window = view.windows[windowId]
            table.insert(item.windows, { id = window.id, appId = window.app_id,
                title = window.title, active = window.active, focused = window.focused,
                pinned = window.pinned, minimized = window.minimized, urgent = window.urgent })
        end
        table.insert(result.workspaces, item)
    end
    return result
end

return M
