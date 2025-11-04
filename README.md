# customise_font

A script for MPV that allows you to modify the font easily, cycling between your favourite fonts.
Supports scaling for PlayRes, adding LayoutRes, and only modifying the default font.
Saves your changes as well.

## Installation

Git clone the repository inside your scripts folder.

## Usage

After installing, modify `styles.lua`:

```lua
        ass = {
            "FontName=Netflix Sans,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Bold=-1,Outline=1.3,Shadow=0,Blur=7",
            "FontName=Gandhi Sans,Bold=1,Outline=1.2,Shadow=0.6666,ShadowX=2,ShadowY=2",
            "FontName=Trebuchet MS,Bold=1,Outline=1.8,Shadow=1,ShadowX=2,ShadowY=2",
            ""
        },

        non_ass = {
            ...
        }
```

Those are simply the ones I'm currently using. Change them to your favourite fonts overrides.
You can also modify the first few options in the `.conf` file that is created.

After doing that, simply press `k` to cycle forwards, `K` to cycle backwards, and `Ctrl+k` to cycle between Normal and Smaller font.
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

To try to guess the default font, it gets all the styles from the property `sub-ass-extradata`, and after discarding some blacklisted names, it gets the most popular
font + size combination, which is usually the main font (and if it isn't, then either open a bug report with info about the fonts in the file, or try to fix it yourself by adding
a blacklist)
