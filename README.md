# mpv-lua-scripts

## toggle_autocrop

An mpv script for automatic letterbox/pillarbox cropping. Uses FFmpeg's `cropdetect` filter to detect black borders in real time and removes them via the `video-crop` property. Primarily designed for ultrawide (21:9) monitors to remove letterboxing. Automatically adjusts cropping on the fly for content with dynamic aspect ratios, such as IMAX scenes.

Based on [mpv's built-in autocrop.lua](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autocrop.lua), heavily modified.

### Features

- Real-time black border detection and automatic cropping via `cropdetect`
- Commit delay (2 poll cycles) to prevent abrupt crop changes
- Minimum crop area threshold to prevent excessive cropping
- Automatic crop reset and detection on playback
- Detection paused during pause, seek or non-1x playback speed
- Mutual exclusion with `toggle_rtxvsr` (optional auto-disable), since `video-crop` / FFmpeg crop filters are incompatible with the RTX VSR filter
- Automatic hwdec mode switching (copyback mode for `cropdetect` filter compatibility)

### Installation

Copy `toggle_autocrop.lua` to mpv's `scripts/` directory.

### Usage

#### input.conf key bindings

```
KEY script-message toggle_autocrop
KEY script-message-to toggle_autocrop enable
KEY script-message-to toggle_autocrop disable
```

- `toggle_autocrop` — toggle on/off
- `enable` — enable (no OSD message, intended for inter-script communication)
- `disable` — disable (no OSD message, intended for inter-script communication)

### Options

Configure via `script-opts/toggle_autocrop.conf` (recommended over editing the script defaults directly).

| Option | Default | Description |
|---|---|---|
| `hwdec_enable` | `no` | Enable hwdec mode switching. When `no`, forces `hwdec=no` while autocrop is active |
| `hwdec_zerocopy` | `auto` | hwdec mode when autocrop is inactive |
| `hwdec_copyback` | `auto-copy` | hwdec mode when autocrop is active (must be copyback) |
| `rtxvsr_disable` | `no` | Automatically disable RTX VSR when autocrop is enabled, since `video-crop` / FFmpeg crop filters are incompatible with the RTX VSR filter |
| `rtxvsr_label` | `rtxvsr` | Filter label of the RTX VSR script |
| `osd` | `Autocrop` | Display name shown in OSD |
| `label` | `autocrop` | Label for vf filter and user-data |
| `cropdetect_limit` | `24/255` | Cropdetect threshold (higher = more sensitive) |
| `cropdetect_round` | `16` | Crop area rounding unit in pixels |
| `min_apply_width` | `0.5` | Minimum crop width ratio relative to source. Crop is ignored if below this |
| `min_apply_height` | `0.5` | Minimum crop height ratio relative to source. Crop is ignored if below this |

#### Example configuration

```
hwdec_enable=yes
hwdec_zerocopy=d3d11va
hwdec_copyback=d3d11va-copy
rtxvsr_disable=yes
cropdetect_limit=18/255
cropdetect_round=10
min_apply_width=1.0
min_apply_height=0.7
```

These values are tuned for 21:9 ultrawide monitors to remove top/bottom letterboxing, and are more suitable than the defaults in `toggle_autocrop.lua`.

#### menu.conf example

For use with mpv's built-in context menu:

```
Autocrop	script-message toggle_autocrop	checked=p["user-data/autocrop"]	disabled=not p["current-tracks/video"] or p["current-tracks/video/image"]
```

When autocrop is active, a checkmark appears next to the menu item via `user-data/autocrop`.

---

## toggle_rtxvsr

An mpv script for toggling NVIDIA RTX Video Super Resolution (VSR). Uses the `d3d11vpp` filter with NVIDIA scaling mode to enable hardware-accelerated video upscaling on D3D11 GPU context.

### Features

- Hardware-accelerated video upscaling via NVIDIA RTX VSR
- Automatic scale calculation based on display-to-video height ratio
- Optional auto-apply on file load (`autoload_enable`)
- Max height and minimum scale guards to prevent unnecessary application
- Mutual exclusion with `toggle_autocrop` (optional auto-disable), since the RTX VSR filter is incompatible with `video-crop` / FFmpeg crop filters
- D3D11 GPU context only (Windows)

### Requirements

- NVIDIA RTX GPU with VSR support
- Windows with D3D11 GPU context (`gpu-context=d3d11`)
- `vo=gpu-next`

### Installation

Copy `toggle_rtxvsr.lua` to mpv's `scripts/` directory.

### Usage

#### input.conf key bindings

```
KEY script-message toggle_rtxvsr
KEY script-message-to toggle_rtxvsr enable
KEY script-message-to toggle_rtxvsr disable
```

- `toggle_rtxvsr` — toggle on/off
- `enable` — enable (no OSD message, intended for inter-script communication)
- `disable` — disable (no OSD message, intended for inter-script communication)

#### Auto-load

With `autoload_enable=yes`, RTX VSR is automatically applied on file load when conditions are met.

#### Activation conditions

RTX VSR is only applied when all of the following are met:

1. GPU context is `d3d11`
2. Current track is a video (not an image)
3. Video height is below `max_height`
4. Calculated scale (display height / video height) exceeds `min_scale`

### Options

Configure via `script-opts/toggle_rtxvsr.conf` (recommended over editing the script defaults directly).

| Option | Default | Description |
|---|---|---|
| `autoload_enable` | `no` | Automatically apply on file load |
| `autocrop_disable` | `no` | Automatically disable autocrop when RTX VSR is enabled, since the RTX VSR filter is incompatible with `video-crop` / FFmpeg crop filters |
| `autocrop_label` | `autocrop` | Filter label of the autocrop script |
| `osd` | `RTX VSR` | Display name shown in OSD |
| `label` | `rtxvsr` | Label for vf filter and user-data |
| `max_height` | `2160` | Skip videos at or above this height |
| `min_scale` | `1.0000` | Skip if calculated scale is at or below this value |
| `precision` | `4` | Decimal places for scale calculation |

#### Example configuration

```
autoload_enable=yes
autocrop_disable=yes
max_height=2160
min_scale=1.0100
precision=4
```

A `min_scale` of `1.0100` is recommended. Scaling differences below 1% may cause rendering artifacts.

#### menu.conf example

For use with mpv's built-in context menu:

```
RTX VSR		script-message toggle_rtxvsr	checked=p["user-data/rtxvsr"]	disabled=p["current-gpu-context"] ~= "d3d11" or not p["current-tracks/video"] or p["current-tracks/video/image"]
```

When RTX VSR is active, a checkmark appears next to the menu item via `user-data/rtxvsr`.
