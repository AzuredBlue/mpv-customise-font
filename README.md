# customise_font

A script for MPV that allows you to modify the font easily, cycling between your favourite fonts.
Supports scaling for PlayRes, adding LayoutRes, and only modifying the default font.
Works for both ASS and non-ASS (SRT, etc.) subtitles. Saves your changes as well.

## Installation

Git clone the repository inside your scripts folder:

```sh
cd ~/.config/mpv/scripts
git clone https://github.com/AzuredBlue/mpv-customise-font.git
```

`ffmpeg` should be available in your `PATH` for the most accurate default font detection. Without it, only the heuristic is used (see [How it works](#how-it-works)).

## Usage

Press `k` to cycle forwards, `K` to cycle backwards, and `Ctrl+k` to toggle between the normal and alternate font size (the normal size multiplied by `alternate_font_scale`). You can also press `Ctrl+r` to reload the styles and apply any modifications you made to `custom-styles.lua` on-the-fly.

### Custom styles

To add your own fonts and custom styles without them being overwritten when updating the script, create a file named `custom-styles.lua` in the script's directory and add your font styles there. It replaces the built-in list from `styles.lua`.

Example `custom-styles.lua`:

```lua
return {
    "FontName=Netflix Sans,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Bold=-1,Outline=1.3,Shadow=0,Blur=7",
    "FontName=Gandhi Sans,Bold=1,Outline=1.2,Shadow=0.6666,ShadowX=2,ShadowY=2",
    "FontName=Trebuchet MS,Bold=1,Outline=1.8,Shadow=1,ShadowX=2,ShadowY=2",
    ""
}
```

- Styles use the ASS style format, so you can copy them from a subtitle file. Values are written for the default PlayRes (640x360) and get scaled to each file's PlayRes.
- You can add `FontSize=` to a style to override `ass_font_size` for that font (some fonts are bigger than others).
- The empty entry `""` means "use my own `sub-ass-style-overrides` from `mpv.conf`" (or no override at all). It is added automatically to the end of the list if you leave it out.
- For non-ASS subtitles, the same styles are converted to `sub-font`, `sub-bold`, `sub-color`, `sub-border-color`, `sub-shadow-color`, `sub-border-size`, `sub-shadow-offset` and `sub-blur`. Only entries with a `FontName` are used for them.

### Key bindings

The default keys can be changed in your `input.conf`, using the script's name (the name of its folder, with `-` replaced by `_`):

```
k       script-binding mpv_customise_font/cycle_styles_forward
K       script-binding mpv_customise_font/cycle_styles_backward
Ctrl+k  script-binding mpv_customise_font/toggle_font_size
Ctrl+r  script-binding mpv_customise_font/reload
```

### Options

Options can be set in `script-opts/customise_font.conf`. This file is also created automatically to save the selected style and size.

| Option | Default | Description |
| --- | --- | --- |
| `debug` | `no` | Print which fonts and styles are detected and replaced. |
| `set_sub_pos` | `yes` | Raise the subtitles slightly by setting `sub-pos=98`. |
| `only_modify_default_font` | `yes` | Only override the styles used for dialogue, leaving signs, songs, etc. untouched. If `no`, every style is overridden. |
| `ass_font_size` | `0` | ASS font size (at 640x360, scaled by PlayRes). `0` keeps the subtitle's own size unless the style sets `FontSize`. Around `26` works well. |
| `conserve_style_color` | `yes` | When the dialogue styles use several outline colours (e.g. a different colour per character), keep the original colours instead of replacing them. |
| `default_font_size` | `44` | Font size for non-ASS subtitles. |
| `alternate_font_scale` | `0.95` | Multiplier applied to the font size when the alternate size is enabled with `Ctrl+k`. Values between 0.9 and 1.1 are recommended. |
| `blacklist` | `sign;song;^ed;^op;title;^os;ending;opening;kfx;karaoke;eyecatch` | Lua patterns (separated by `;` or `,`, matched against the lowercase style name) for styles that are never considered the default font. Style names containing `OP` or `ED` in capitals are also ignored. |

`ass_index`, `non_ass_index` and `alternate_size` are saved by the script when mpv closes, so there is no need to modify them manually.

## How it works

The disadvantage of simply using an override, is that it won't work on all files. This is because not all files have the same PlayRes.
To fix this, we can simply get the PlayRes it uses, and divide it by the default PlayRes values. This gives us a scale factor that we can use
to multiply the overrides values. If the video isn't 16:9, `LayoutResX`/`LayoutResY` are also reset, since they can mess up the subtitles.

For guessing the default font, first it uses a heuristic approach, picking the most popular font + size combination among the styles (ignoring blacklisted and small styles). If there is more than one combination, it then uses `ffmpeg` to analyse 45 seconds of the subtitles, starting at 65% of the video to avoid the opening and ending, and picks the font + size used by the most dialogue lines. Only the styles matching that font are overridden.
