
-- Styles in the ASS format, you can copy them from the subtitle file. These are some examples
-- They will scale based on PlayRes
-- You can also specify FontSize to override the one in the config (as some fonts are bigger than others)
local styles = {
    "FontName=Trebuchet MS,Bold=0,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=2,Shadow=1",
    "FontName=LTFinnegan Medium,Bold=0,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=1,Shadow=0.23,MarginV=20",
    "FontName=Gandhi Sans,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H00FFFFFF,OutlineColour=&H00211211,BackColour=&H7F000000,Outline=1.1,Shadow=0.5,MarginV=20",
    "FontName=SinaNovaW01-Regular,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H00FFFFFF,OutlineColour=&H002b2524,BackColour=&H80161010,Outline=1.45,Shadow=0.75,MarginV=20",
    ""
}


-- Transform from Visual Basic Hex to RGB
local function vb_to_argb(c)
    -- Visual Basic Hex: &HAABBGGRR -> ARGB Hex: #AARRGGBB
    if not c then return nil end
    local a, b, g, r = c:match("&H(%x%x)(%x%x)(%x%x)(%x%x)")
    if a and b and g and r then
        local alpha = tonumber(a, 16)
        local inv_alpha = 255 - alpha
        return string.format("#%02X%s%s%s", inv_alpha, r, g, b)
    end
    return c
end

local non_ass = {}

-- Generate non_ass dynamically from the styles
for _, style in ipairs(styles) do
    if style ~= "" then
        local params = {}
        for k, v in style:gmatch("([%w]+)=([^,]+)") do
            params[k] = v
        end

        if params.FontName then
            local new_style = {
                name = params.FontName,
                font = params.FontName,
                bold = (params.Bold == "1"),
                border_color = vb_to_argb(params.OutlineColour),
                shadow_color = vb_to_argb(params.BackColour),
                border_size = params.Outline and (tonumber(params.Outline) * 2) or nil,
                shadow_offset = params.Shadow and (tonumber(params.Shadow) * 2) or nil,
                font_size = params.FontSize and (tonumber(params.FontSize) * 2) or nil,
            }
            
            if params.PrimaryColour and params.PrimaryColour ~= "&H00FFFFFF" then
               new_style.color = vb_to_argb(params.PrimaryColour)
            end

            table.insert(non_ass, new_style)
        end
    end
end

return {
    ass = styles,
    non_ass = non_ass
}