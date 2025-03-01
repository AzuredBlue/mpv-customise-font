local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local CONFIG_FILENAME = "subtitle_style.conf"
local DEFAULT_PLAYRESX = 640
local DEFAULT_PLAYRESY = 360
local DEFAULT_FONT_SIZE = 44
local SMALL_FONT_SIZE = 42
local OSD_DURATION = 2

local state = {
    ass_index = 1,
    non_ass_index = 1,
    font_size = DEFAULT_FONT_SIZE,
    ass_small_font = false,
    styles = {
        ass = {
            "FontName=Netflix Sans,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Bold=-1,Outline=1.3,Shadow=0,Blur=7",
            -- "FontName=Gandhi Sans,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Bold=1,Outline=1.3,Shadow=0.5,ShadowX=2,ShadowY=2",
            -- ""
            -- "FontName=Netflix Sans,Bold=1,Outline=2,Shadow=0,Blur=7",
            "FontName=Gandhi Sans,Bold=1,Outline=1.2,Shadow=0.6666,ShadowX=2,ShadowY=2",
            "FontName=Trebuchet MS,Bold=1,Outline=1.8,Shadow=1,ShadowX=2,ShadowY=2",
            ""
        },
        non_ass = {
            {
                name = "Netflix Style",
                font = "Netflix Sans", 
                bold = true,
                blur = 3,
                border_color = "#000000",
                border_size = 2,
                shadow_color = "#000000",
                shadow_offset = 0
            },
            {
                name = "Gandhi Style",
                font = "Gandhi Sans",
                bold = true,
                blur = 0,
                -- border_color = "#000000",
                border_size = 2.5,
                shadow_color = "#000000",
                shadow_offset = 1
            },
            {
                name = "CR",
                font = "Trebuchet MS",
                bold = true,
                blur = 0,
                -- border_color = "#000000",
                border_size = 3,
                shadow_color = "#000000",
                shadow_offset = 1.5
            }
        }
    }
}

local function get_config_path()
    if package.config:sub(1,1) == '\\' then
        -- Windows
        local appdata = os.getenv("APPDATA")
        if appdata then
            return utils.join_path(utils.join_path(appdata, "mpv"), "script-opts")
        else
            local home = os.getenv("USERPROFILE")
            if home then
                return utils.join_path(
                    utils.join_path(
                        utils.join_path(
                            utils.join_path(home, "AppData"),
                        "Roaming"),
                    "mpv"),
                "script-opts")
            end
        end
    else
        -- Unix-like systems
        local home = os.getenv("HOME")
        if home then
            return utils.join_path(utils.join_path(home, ".config"), "mpv")
        end
    end
    return nil
end

local function ensure_config_directory()
    local config_path = get_config_path()
    if not config_path then return false end
    
    local success, err = utils.file_info(config_path)
    if not success then
        msg.verbose("Creating config directory:", config_path)
        return utils.subprocess({
            args = {"mkdir", "-p", config_path},
            cancellable = false
        })
    end
    return true
end

local function get_playres_scale()
    local sub_data = mp.get_property("sub-ass-extradata", "")

    local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)")) or DEFAULT_PLAYRESX
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)")) or DEFAULT_PLAYRESY

    local xRatio = playresx / DEFAULT_PLAYRESX
    local yRatio = playresy / DEFAULT_PLAYRESY
    if xRatio >= yRatio then
        return xRatio
    else
        return yRatio
    end
end

local function scale_ass_style(style)
    local scale = get_playres_scale()
    if scale == 1 then return style end
    
    return style:gsub("([%w]+)=([%d%.]+)", function(key, val)
        local scaled_properties = {
            Outline = true, Shadow = true, 
            ShadowX = true, ShadowY = true
        }
        
        if scaled_properties[key] then
            return string.format("%s=%.1f", key, tonumber(val) * scale)
        end
        return string.format("%s=%s", key, val)
    end)
end

-- Approach one: Get the first one
-- local function get_default_font_and_styles(sub_data)
--     local in_styles_section = false
--     local default_font = nil
--     local styles = {}
--     local target_font = nil
    
--     -- Add more blacklist terms here (lowercase)
--     local blacklist = {
--         "sign",  
--         "song",
--         "ed",
--         "op",
--         "title",
        
--     }

--     for line in sub_data:gmatch("[^\r\n]+") do
--         if line:match("Styles%]$") then
--             in_styles_section = true
--         elseif in_styles_section then
--             if line:match("^Style:") then
--                 local params = {}
--                 for param in line:sub(7):gmatch("([^,]+)") do
--                     table.insert(params, param:match("^%s*(.-)%s*$"))
--                 end
                
--                 if #params >= 2 then
--                     local style_name = params[1]
--                     local font_name = params[2]
--                     local lower_name = style_name:lower()

--                     -- Check against blacklist
--                     for _, term in ipairs(blacklist) do
--                         if lower_name:find(term) then
--                             goto continue
--                         end
--                     end
                    
--                     -- Set target font from first style
--                     if not target_font then
--                         target_font = font_name
--                         default_font = style_name
--                     end
                    
--                     -- Collect all styles using target font
--                     if font_name == target_font then
--                         table.insert(styles, style_name)
--                     end
--                 end
--                 ::continue::
--             end
--         end
--     end
    
--     return default_font, styles
-- end

-- Approach two: Get the most popular one
local function get_default_font_and_styles(sub_data)
    local blacklist = {
        "sign", "song", "^ed", "^op", "title", "^os"
    }
    
    local valid_styles = {}  -- Stores {name, font, size}
    local font_counts = {}  -- Tracks font+size popularity
    
    for line in sub_data:gmatch("[^\r\n]+") do
        if line:match("Styles%]$") then
            for style_line in sub_data:gmatch("Style:([^\r\n]+)") do
                local params = {}
                for param in style_line:gmatch("([^,]+)") do
                    table.insert(params, param:match("^%s*(.-)%s*$"))
                end
                
                if #params >= 3 then  -- Need at least 3 params (name, font, size)
                    local style_name = params[1]
                    local font_name = params[2]
                    local font_size = params[3]
                    local lower_name = style_name:lower()

                    -- Check blacklist patterns
                    local skip = false
                    for _, pattern in ipairs(blacklist) do
                        if lower_name:find(pattern) then
                            skip = true
                            break
                        end
                    end
                    
                    if not skip then
                        local font_key = font_name .. "|" .. font_size
                        table.insert(valid_styles, {
                            name = style_name,
                            font = font_name,
                            size = font_size,
                            key = font_key
                        })
                        font_counts[font_key] = (font_counts[font_key] or 0) + 1
                    end
                end
            end
            break
        end
    end

    -- Find most popular font+size combination
    local max_count, popular_key = 0, nil
    for key, count in pairs(font_counts) do
        if count > max_count or (count == max_count and not popular_key) then
            max_count = count
            popular_key = key
        end
    end

    -- Extract font name and size from popular key
    local popular_font, popular_size
    if popular_key then
        popular_font, popular_size = popular_key:match("([^|]+)|(.+)")
    end

    -- Collect all styles using the popular font+size
    local styles = {}
    if popular_key then
        for _, style in ipairs(valid_styles) do
            if style.key == popular_key then
                table.insert(styles, style.name)
            end
        end
    end
    
    return popular_font, popular_size, styles
end

local function prefix_style_with_styles(style_names, scaled_style)
    local all_parts = {}
    
    for _, style_name in ipairs(style_names) do
        local parts = {}
        for param in scaled_style:gmatch("([^,]+)") do
            local key, value = param:match("^([^=]+)=(.+)$")
            if key and value then
                table.insert(parts, string.format("%s.%s=%s", style_name, key, value))
            else
                table.insert(parts, param)
            end
        end
        table.insert(all_parts, table.concat(parts, ","))
    end
    
    return table.concat(all_parts, ",")
end

local function apply_ass_style()
    local style = state.styles.ass[state.ass_index]
    if not style then return end
    
    local scaled_style = scale_ass_style(style)

    -- if state.ass_small_font then
    --     scaled_style = scaled_style .. string.format(",FontSize=%d", 
    --         math.floor(23 * get_playres_scale()))
    -- end

    -- Try to only apply to the default font
    local sub_data = mp.get_property("sub-ass-extradata", "")

    local default_style_name, default_size, matching_styles = get_default_font_and_styles(sub_data)

    if state.ass_small_font then
        scaled_style = scaled_style .. string.format(",FontSize=%d", math.floor((0.95*default_size) + 0.5))
    end

    if #matching_styles > 0 then
        scaled_style = prefix_style_with_styles(matching_styles, scaled_style)
    end

    -- print("Scaled style is now: " .. scaled_style)
    -- Fix LayoutRes
    local layoutResY = tonumber(sub_data:match("LayoutResY:%s*(%d+)")) or ""
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)"))

    if layoutResY == "" and playresy < 720 then
        local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)"))
        if playresx ~= "" then
            local layoutresString = string.format("LayoutResX=%s,LayoutResY=%s", playresx, playresy)
            scaled_style =  layoutresString .. ',' .. scaled_style
        end
    end

    
    mp.set_property("sub-ass-style-overrides", scaled_style)
    mp.set_property("sub-pos", 98)
end

local function apply_non_ass_style()
    local style = state.styles.non_ass[state.non_ass_index]
    if not style then return end
    
    mp.set_property_native("sub-font", style.font)
    mp.set_property_native("sub-bold", style.bold)
    mp.set_property_native("sub-font-size", state.font_size)
    mp.set_property_native("sub-blur", style.blur)
    -- mp.set_property_native("sub-border-color", style.border_color)
    mp.set_property_native("sub-border-size", style.border_size)
    mp.set_property_native("sub-shadow-color", style.shadow_color)
    mp.set_property_native("sub-shadow-offset", style.shadow_offset)
    mp.set_property("sub-pos", 100)
end

local function load_config()
    local config_path = utils.join_path(get_config_path(), CONFIG_FILENAME)
    local file = io.open(config_path, "r")
    if not file then return end
    
    for line in file:lines() do
        local key, value = line:match("^([^=]+)=(.+)$")
        if key and value then
            if key == "ass_index" then state.ass_index = tonumber(value)
            elseif key == "non_ass_index" then state.non_ass_index = tonumber(value)
            elseif key == "font_size" then state.font_size = tonumber(value)
            elseif key == "ass_small_font" then state.ass_small_font = value == "true"
            end
        end
    end
    file:close()
end

local function save_config()
    if not ensure_config_directory() then return end
    
    local config_path = utils.join_path(get_config_path(), CONFIG_FILENAME)
    local file = io.open(config_path, "w")
    if not file then return end
    
    file:write(string.format(
        "ass_index=%d\nnon_ass_index=%d\nfont_size=%d\nass_small_font=%s",
        state.ass_index,
        state.non_ass_index,
        state.font_size,
        tostring(state.ass_small_font)
    ))
    file:close()
end

local function is_ass_subtitle()
    local track = mp.get_property_native("current-tracks/sub")
    return track and track.codec == "ass"
end

local function show_feedback(message)
    mp.osd_message(message, OSD_DURATION)
    -- msg.info(message)
end

local function format_style_overrides(override_str)
    local attr_order = {}  -- Maintain insertion order
    local attrs = {}
    local fonts = {}
    local seen_styles = {}

    -- First pass: collect attributes in order and track fonts
    for param in override_str:gmatch("([^,]+)") do
        local style, attr, value = param:match("([^.]+)%.([^=]+)=(.+)")
        if attr then
            -- Track attribute order (only first occurrence)
            if not attrs[attr] then
                table.insert(attr_order, attr)
                attrs[attr] = {
                    value = value,
                    multiple = false
                }
            else
                -- Mark as multiple if values differ
                if attrs[attr].value ~= value then
                    attrs[attr].multiple = true
                end
            end

            -- Track font changes
            if attr == "FontName" and not seen_styles[style] then
                table.insert(fonts, style)
                seen_styles[style] = true
            end
        end
    end

    -- Build output in original order
    local parts = {}
    for _, attr in ipairs(attr_order) do
        local val = attrs[attr].multiple and "multiple" or attrs[attr].value
        table.insert(parts, string.format('%s="%s"', attr, val))
    end

    -- Add font changes
    if #fonts > 0 then
        table.insert(parts, "\nFonts Changed: " .. table.concat(fonts, ", "))
    end

    return table.concat(parts, ", ")
end

local function print_script_info()
    local sub_data = mp.get_property("sub-ass-extradata", "")
    local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)")) or DEFAULT_PLAYRESX
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)")) or 360

    print(sub_data)
    local video_path = mp.get_property("path", "N/A")
    local current_track = mp.get_property_native("current-tracks/sub", {})
    local style_overrides = format_style_overrides(mp.get_property("sub-ass-style-overrides", "None"))

    local style_info = ""
    if is_ass_subtitle() then
        local current_style = state.styles.ass[state.ass_index] or "Default"
        style_info = string.format([[
ASS Style Information:
--------------------
Current style index: %d
Small font mode: %s
Scale factor: %.2f
PlayResX: %d
PlayResY: %d
Style overrides: %s]],
            state.ass_index,

            tostring(state.ass_small_font),
            get_playres_scale(),
            playresx,
            playresy,
            style_overrides
        )
    else
        local current_style = state.styles.non_ass[state.non_ass_index] or {}
        style_info = string.format([[
SRT Style Information:
--------------------
Current style index: %d
Style name: %s
Font: %s
Font size: %d
Bold: %s
Blur: %.1f
Border color: %s
Border size: %.1f
Shadow color: %s
Shadow offset: %.1f]],
            state.non_ass_index,
            current_style.name or "N/A",
            mp.get_property("sub-font", "N/A"),
            state.font_size,
            tostring(mp.get_property_bool("sub-bold")),
            tonumber(mp.get_property("sub-blur")) or 0,
            mp.get_property("sub-border-color", "N/A"),
            tonumber(mp.get_property("sub-border-size")) or 0,
            mp.get_property("sub-shadow-color", "N/A"),
            tonumber(mp.get_property("sub-shadow-offset")) or 0
        )
    end

    local info = string.format([[
%s
]],
        style_info
    )

    mp.osd_message(info, 7)
    msg.info(info)
end

local function toggle_font_size()
    if is_ass_subtitle() then
        state.ass_small_font = not state.ass_small_font
        apply_ass_style()
        show_feedback("ASS Font Size: " .. (state.ass_small_font and "Small" or "Normal"))
    else
        state.font_size = state.font_size == DEFAULT_FONT_SIZE 
            and SMALL_FONT_SIZE 
            or DEFAULT_FONT_SIZE
        apply_non_ass_style()
        show_feedback("SRT Font Size: " .. state.font_size)
    end
    save_config()
end

local function cycle_styles(direction)
    if is_ass_subtitle() then
        state.ass_index = (state.ass_index + direction - 1) % #state.styles.ass + 1
        apply_ass_style()
        show_feedback("ASS Style: " .. state.ass_index)
    else
        state.non_ass_index = (state.non_ass_index + direction - 1) % #state.styles.non_ass + 1
        apply_non_ass_style()
        show_feedback("SRT Style: " .. state.styles.non_ass[state.non_ass_index].name)
    end
    save_config()
end

mp.register_event("file-loaded", function()
    load_config()
    if is_ass_subtitle() then
        apply_ass_style()
    else
        apply_non_ass_style()
    end
end)

-- Key Bindings
mp.add_key_binding("k", "cycle_styles_forward", function() cycle_styles(1) end)
mp.add_key_binding("K", "cycle_styles_backward", function() cycle_styles(-1) end)
mp.add_key_binding("Ctrl+k", "toggle_font_size", toggle_font_size)
mp.add_key_binding("i", "print_script_info", print_script_info)

local function print_fonts()
    local sub_data = mp.get_property_native("sub-ass-extradata", "")
    local in_styles_section = false

    for line in sub_data:gmatch("[^\r\n]+") do
        -- Enter styles section
        if line:match("Styles%]$") then
            in_styles_section = true
        elseif in_styles_section then
            -- Exit section if we hit a new section header
            if line:match("^%[") then
                in_styles_section = false
            elseif line:match("^Style:") then
                -- Extract style parameters
                print(line)
            end
        end
    end
end

mp.add_key_binding("I", "print_fonts", print_fonts)
