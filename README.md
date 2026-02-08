# customise_font

A script for MPV that allows you to modify the font easily, cycling between your favourite fonts.
Supports scaling for PlayRes, adding LayoutRes, and only modifying the default font.
Saves your changes as well.

## Installation

Git clone the repository inside your scripts folder.

## Usage

After installing, modify `styles.lua`:

```lua
        styles = {
            "FontName=Trebuchet MS,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=2,Shadow=1",
            "FontName=LTFinnegan Medium,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=1,Shadow=0.23,MarginV=20",
            "FontName=Gandhi Sans,Bold=1,PrimaryColour=&H00FFFFFF,OutlineColour=&H00211211,BackColour=&H7F000000,Outline=1.1,Shadow=0.5",
            ""
        }
```

These are just examples. Change them to your favourite fonts overrides. Colours use the Visual Basic Hex format `&HAABBGGRR`. 

Pressing `k` will cycle forwards, `K` will cycle backwards, and `Ctrl+k` will cycle between Normal and Smaller font.
You can change these controls in the script:

```lua
mp.add_key_binding("k", "cycle_styles_forward", function() cycle_styles(1) end)
mp.add_key_binding("K", "cycle_styles_backward", function() cycle_styles(-1) end)
mp.add_key_binding("Ctrl+k", "toggle_font_size", toggle_font_size)
mp.add_key_binding("Ctrl+r", "reload", reload)
```

After using, it will generate a `.conf` file in your `script-opts`, to save the changes you make.

## How it works

The disadvantage of simply using an override, is that it won't work on all files. This is because not all files have the same PlayRes.
To fix this, we can simply get the PlayRes it uses, and divide it by the default PlayRes values. This gives us a scale factor that we can use
to multiply the overrides values.

For guessing the default font, first it uses a heuristic approach, trying to guess it by the most popular font + size combination, then it uses `ffmpeg` to analyse 2 minutes of the anime.
