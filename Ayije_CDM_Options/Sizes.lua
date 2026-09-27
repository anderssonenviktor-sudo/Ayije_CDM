local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI

function ns.CreateIconSizeSlider(parent, label, key, field)
    return UI.CreateModernSlider(parent, label, 20, 100, CDM.db[key][field], function(value)
        local current = CDM.db[key]
        local updated = { w = current.w, h = current.h }
        updated[field] = value
        CDM.db[key] = updated
        API:Refresh("LAYOUT")
    end)
end
