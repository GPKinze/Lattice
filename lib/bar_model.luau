--!nonstrict
-- Pure presentation model. The Milestone 1 state/presentation interfaces stay intact.
local Presentation = require("./presentation.luau")
local M = {}
local defaults = { capsule_padding = 6, workspace_spacing = 4, icon_size = 16,
    max_icons = 4, group_icons = true, density = "compact" }

local function integer(value, fallback, minimum, maximum)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return fallback end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

function M.settings(raw)
    raw = type(raw) == "table" and raw or {}
    local density = raw.density
    if density ~= "compact" and density ~= "normal" and density ~= "roomy" then density = defaults.density end
    local grouping = defaults.group_icons
    if type(raw.group_icons) == "boolean" then grouping = raw.group_icons end
    return { capsule_padding = integer(raw.capsule_padding, 6, 0, 16),
        workspace_spacing = integer(raw.workspace_spacing, 4, 0, 12),
        icon_size = integer(raw.icon_size, 16, 12, 24),
        max_icons = integer(raw.max_icons, 4, 1, 8),
        group_icons = grouping,
        density = density }
end

local function available(view, output)
    return type(view) == "table" and view.ready == true and type(output) == "string"
        and view.outputs[output] ~= nil and view.outputs[output].enabled == true
end

function M.validHover(view, output, reference)
    if not available(view, output) or type(reference) ~= "table" then return nil end
    local workspace = view.workspaces[reference.id]
    if reference.generation ~= view.generation or reference.output ~= output
        or not workspace or workspace.output ~= output then return nil end
    return { id = reference.id, output = output, generation = view.generation }
end

function M.hover(view, output, current, target, entered)
    current = M.validHover(view, output, current)
    target = M.validHover(view, output, target)
    if not target then return current end
    if entered == true or entered == "true" then return target end
    if current and current.id == target.id then return nil end
    return current
end

local function groupsFor(view, workspace, grouping)
    local groups, lookup, seen = {}, {}, {}
    for _, id in ipairs(workspace.windowIds) do
        local w = view.windows[id]
        -- Independent families can briefly disagree during a window/output move.
        if w and not seen[id] and w.workspace == workspace.id and w.output == workspace.output then
            seen[id] = true
            local key = grouping and w.app_id ~= "" and ("app:" .. w.app_id) or ("window:" .. id)
            local group = lookup[key]
            if not group then
                group = { key = key, appId = w.app_id, windowIds = {}, titles = {}, count = 0,
                    active = false, remembered = false, urgent = false, allMinimized = true }
                lookup[key] = group
                table.insert(groups, group)
            end
            table.insert(group.windowIds, id)
            if type(w.title) == "string" and w.title ~= "" then table.insert(group.titles, w.title) end
            group.count = group.count + 1
            group.active = group.active or view.focus.activeWindowId == id
            group.remembered = group.remembered or workspace.rememberedWindowId == id
            group.urgent = group.urgent or w.urgent == true
            group.allMinimized = group.allMinimized and w.minimized == true
        end
    end
    return groups
end

-- The only icon visibility policy in Milestone 2: Active + Hover.
-- Empty is compositor-reported, never derived from pinned-window membership.
-- Side bars use the documented label-only fallback; app details stay in tooltip.
function M.iconsVisible(workspace, hovered, vertical)
    return not vertical and workspace.occupied == true and #workspace.groups > 0
        and (workspace.active == true or hovered == true)
end

local function limited(groups, maximum)
    local visible = {}
    for i = 1, math.min(#groups, maximum) do table.insert(visible, groups[i]) end
    -- Overflow should not conceal the global active app (or local remembered app).
    local priority = nil
    for _, group in ipairs(groups) do
        if group.active then priority = group; break end
        if group.remembered then priority = group end
    end
    if priority then
        local found = false
        for _, group in ipairs(visible) do found = found or group.key == priority.key end
        if not found then visible[#visible] = priority end
    end
    return visible, #groups - #visible
end

function M.forOutput(view, output, hover, rawSettings, vertical)
    local settings = M.settings(rawSettings)
    local result = { ready = available(view, output) == true, output = output,
        generation = type(view) == "table" and view.generation or 0,
        revision = type(view) == "table" and view.revision or 0,
        settings = settings, vertical = vertical == true, policy = "active_hover", workspaces = {} }
    if not result.ready then return result end
    result.hover = M.validHover(view, output, hover)
    local prepared = Presentation.forOutput(view, output)
    for _, item in ipairs(prepared.workspaces) do
        local workspace = view.workspaces[item.id]
        item.groups = groupsFor(view, workspace, settings.group_icons)
        item.hovered = result.hover ~= nil and result.hover.id == item.id
        item.showIcons = M.iconsVisible(item, item.hovered, result.vertical)
        item.icons, item.overflow = {}, 0
        if item.showIcons then item.icons, item.overflow = limited(item.groups, settings.max_icons) end
        item.key = "workspace:" .. tostring(view.generation) .. ":" .. item.id
        item.reference = { id = item.id, output = output, generation = view.generation }
        table.insert(result.workspaces, item)
    end
    return result
end

return M
