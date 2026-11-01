--!nonstrict
local M = {}
function M.render(model, api)
    local ui, s = api.ui, model.settings
    local pad = s.density == "roomy" and 4 or s.density == "normal" and 3 or 2
    local height, targets, capsules = s.icon_size + 2 + pad * 2, {}, {}
    local function target(key, reference)
        targets[key] = reference
        return key
    end
    if not model.ready or #model.workspaces == 0 then
        return ui.row({ key="status",height=height,align="center",
            tooltip=api.tr(model.ready and "status.empty" or "status.unavailable") }, {
            ui.glyph({name=model.ready and "layout-grid" or "plug-off",size=16,color="on_surface_variant"}),
        }), targets
    end
    for _, ws in ipairs(model.workspaces) do
        local labelKey = target(ws.key .. ":label", ws.reference)
        local children = { ui.row({key=labelKey,height=s.icon_size+2,align="center",
            onHover="onInlineHover",onClick=api.workspaceClick(ws.reference),
            tooltip=ws.name .. "\n" .. ws.output }, {
            ui.label({text=ws.name,maxLines=1,color="on_surface",fontWeight=ws.active and "semibold" or "normal"}),
        }) }
        for _, w in ipairs(ws.windowIcons) do
            local key = target(ws.key .. ":window:" .. w.id, ws.reference)
            local path = api.iconPath(w.appId, s.icon_size)
            local image = path and ui.image({path=path,width=s.icon_size,height=s.icon_size,fit="contain"})
                or ui.glyph({name="apps",size=s.icon_size,width=s.icon_size,height=s.icon_size,color="on_surface_variant"})
            table.insert(children,ui.row({ key=key,height=s.icon_size+2,paddingH=1,align="center",radius=4,
                borderWidth=1,border=w.urgent and "error" or w.active and "primary" or w.remembered and "secondary" or "on_surface_variant/0.12",
                fill=w.active and "primary/0.20" or api.hoverKey==key and "on_surface/0.10" or "surface/0",
                opacity=w.minimized and not w.active and 0.6 or 1,
                onHover="onInlineHover",onClick=api.windowClick(ws.reference,w.id),
                tooltip=(w.appId~="" and w.appId or api.tr("application.unknown")) .. "\n" .. w.title },{image}))
        end
        if ws.hiddenWindows > 0 then
            -- Keep the last page the same width so the overflow target cannot
            -- move out from under the pointer and collapse an inactive capsule.
            for i=#ws.windowIcons+1,math.min(ws.totalWindows,s.max_icons) do
                local slot=target(ws.key .. ":slot:" .. tostring(i),ws.reference)
                table.insert(children,ui.row({key=slot,width=s.icon_size+2,height=s.icon_size+2,onHover="onInlineHover"},{}))
            end
            local key = target(ws.key .. ":more",ws.reference)
            table.insert(children,ui.row({key=key,height=s.icon_size+2,align="center",
                onHover="onInlineHover",onClick=api.pageClick(ws.reference,ws.page,ws.pageCount),
                tooltip=api.tr("windows.next_page") .. " " .. tostring(ws.page+1) .. "/" .. tostring(ws.pageCount)}, {
                ui.label({text="+"..tostring(ws.hiddenWindows),fontSize=11,color="on_surface_variant",maxLines=1}),
            }))
        end
        target(ws.key,ws.reference)
        table.insert(capsules,ui.row({key=ws.key,height=height,gap=pad+2,paddingH=s.capsule_padding,paddingV=pad,
            align="center",radius=height/2,borderWidth=1,onHover="onInlineHover",
            fill=ws.active and "primary/0.16" or ws.hovered and "on_surface/0.08" or "surface/0",
            border=ws.urgent and "error" or ws.active and "primary" or ws.hovered and "on_surface_variant/0.32" or "on_surface_variant/0.18"},children))
    end
    return (model.vertical and ui.column or ui.row)({key="workspaces",gap=s.workspace_spacing,align="center"},capsules),targets
end
return M
