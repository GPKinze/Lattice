--!nonstrict
local Base = require("./bar_model.luau")
local M = {}
M.settings = Base.settings
M.validHover = Base.validHover


local function stabilize(view, workspaces, stableOrders)
    if type(stableOrders) ~= "table"
        or type(view) ~= "table"
        or type(view.workspaces) ~= "table"
        or type(view.windows) ~= "table"
        or type(workspaces) ~= "table" then
        return
    end

    -- Forget workspaces that no longer exist.
    for id in pairs(stableOrders) do
        if not view.workspaces[id] then
            stableOrders[id] = nil
        end
    end

    for _, workspace in ipairs(workspaces) do
        local source = view.workspaces[workspace.id]

        if source and type(source.windowIds) == "table" then
            local present = {}

            -- Identify currently valid workspace members.
            for _, id in ipairs(source.windowIds) do
                local w = view.windows[id]
                if w and w.workspace == workspace.id then
                    present[id] = true
                end
            end

            local ordered, seen = {}, {}

            -- Retain surviving windows in remembered order.
            local previous = stableOrders[workspace.id]

            if type(previous) == "table" then
                for _, id in ipairs(previous) do
                    if present[id] and not seen[id] then
                        table.insert(ordered, id)
                        seen[id] = true
                    end
                end
            end

            -- Append newly discovered windows.
            for _, id in ipairs(source.windowIds) do
                if present[id] and not seen[id] then
                    table.insert(ordered, id)
                    seen[id] = true
                end
            end

            stableOrders[workspace.id] = ordered

            local rank = {}

            for index, id in ipairs(ordered) do
                rank[id] = index
            end

            if type(workspace.groups) == "table" then
                local groupOrder = {}

                for index, group in ipairs(workspace.groups) do
                    -- Sort members within their existing app group.
                    if type(group.windowIds) == "table" then
                        local originalIndex = {}

                        for i, id in ipairs(group.windowIds) do
                            originalIndex[id] = i
                        end

                        table.sort(group.windowIds, function(a, b)
                            local ar = rank[a] or math.huge
                            local br = rank[b] or math.huge

                            if ar == br then
                                return originalIndex[a] < originalIndex[b]
                            end

                            return ar < br
                        end)
                    end

                    -- Position each group using its earliest
                    -- remembered window.
                    local first = math.huge

                    for _, id in ipairs(group.windowIds or {}) do
                        first = math.min(
                            first,
                            rank[id] or math.huge
                        )
                    end

                    groupOrder[group] = {
                        rank = first,
                        index = index
                    }
                end

                table.sort(workspace.groups, function(a, b)
                    local ar = groupOrder[a]
                    local br = groupOrder[b]

                    if ar.rank == br.rank then
                        return ar.index < br.index
                    end

                    return ar.rank < br.rank
                end)
            end
        end
    end
end

function M.forOutput(view, output, hover, settings, vertical, pages, stableOrders)
    local result = Base.forOutput(view, output, hover, settings, vertical)
    stabilize(view, result.workspaces, stableOrders)
    for _, workspace in ipairs(result.workspaces) do
        local entries = {}
        -- App grouping means adjacency, never one ambiguous selectable app icon.
        for _, group in ipairs(workspace.groups) do
            for _, id in ipairs(group.windowIds) do
                local w = view.windows[id]
                table.insert(entries, { id = id, appId = w.app_id, title = w.title or "",
                    active = view.focus.activeWindowId == id, remembered = workspace.rememberedWindowId == id,
                    minimized = w.minimized, urgent = w.urgent, group = group.key })
            end
        end
        workspace.windowIcons, workspace.totalWindows = {}, #entries
        workspace.pageCount = math.max(1, math.ceil(#entries / result.settings.max_icons))
        local page = pages and pages[workspace.id]
        if type(page) ~= "number" or page < 0 or page % 1 ~= 0 then page = 0 end
        workspace.page = math.min(page, workspace.pageCount - 1)
        workspace.hiddenWindows = 0
        if workspace.showIcons then
            local first = workspace.page * result.settings.max_icons + 1
            for i = first, math.min(#entries, first + result.settings.max_icons - 1) do
                table.insert(workspace.windowIcons, entries[i])
            end
            workspace.hiddenWindows = #entries - #workspace.windowIcons
        end
    end
    return result
end
return M
