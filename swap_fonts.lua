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
            -- "FontName=Netflix Sans,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Bold=-1,Outline=2,Shadow=0,Blur=7",
            -- "FontName=Gandhi Sans,Bold=1,Outline=1.3,Shadow=0.5,ShadowX=2,ShadowY=2",
            -- ""
            "FontName=Netflix Sans,Bold=1,Outline=2,Shadow=0,Blur=7",
            "FontName=Gandhi Sans,Bold=1,Outline=1.3,Shadow=0.5,ShadowX=2,ShadowY=2",
            "FontName=Trebuchet MS,Bold=1,Outline=1.8,Shadow=1,ShadowX=2,ShadowY=2",
            ""
        },
        non_ass = {
            {
                name = "Netflix Style",
                font = "Netflix Sans", 
                bold = true,
                blur = 3,
                -- border_color = "#000000",
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

local function apply_ass_style()
    local style = state.styles.ass[state.ass_index]
    if not style then return end
    
    local scaled_style = scale_ass_style(style)
    if state.ass_small_font then
        scaled_style = scaled_style .. string.format(",FontSize=%d", 
            math.floor(23 * get_playres_scale()))
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

local function print_script_info()
    local sub_data = mp.get_property("sub-ass-extradata", "")
    local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)")) or DEFAULT_PLAYRESX
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)")) or 360
    print(sub_data)
    local video_path = mp.get_property("path", "N/A")
    local current_track = mp.get_property_native("current-tracks/sub", {})
    
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
            mp.get_property("sub-ass-style-overrides", "None")
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