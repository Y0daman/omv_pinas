# Freenove control scripts

This project includes wrappers for the Freenove FNK0107 control code.

## Script layout

- `scripts/fan_control/set_fan_percent.sh`
- `scripts/led_control/led_control.sh`
- `scripts/oled_control/oled_control.sh`
- `scripts/screen_control/screen_control.sh`
- `scripts/hw/common.sh` (shared resolver helpers)

Set `FREENOVE_CODE_DIR` if your Freenove `Code/` path is non-standard.

Example:

```bash
export FREENOVE_CODE_DIR="/path/to/Freenove_Computer_Case_Kit_Pro_for_Raspberry_Pi/Code"
```

## Fans

Set all case fan channels to one percentage:

```bash
./scripts/fan_control/set_fan_percent.sh 60
```

Use `--persist` to save to controller flash.

Additional fan modes:

```bash
# Follow case temperature (controller auto mode)
./scripts/fan_control/set_fan_percent.sh follow-case \
  --low-temp 30 --high-temp 50 --schmitt 3 \
  --low-speed 30 --mid-speed 50 --high-speed 70

# Follow Raspberry Pi PWM duty
./scripts/fan_control/set_fan_percent.sh follow-rpi --min-speed 20 --max-speed 100

# Show current fan configuration
./scripts/fan_control/set_fan_percent.sh status
```

## LEDs

Examples:

```bash
./scripts/led_control/led_control.sh rainbow
./scripts/led_control/led_control.sh floating-rainbow
./scripts/led_control/led_control.sh preset blue
./scripts/led_control/led_control.sh preset orange
./scripts/led_control/led_control.sh list-presets
./scripts/led_control/led_control.sh breathing 0 180 255
./scripts/led_control/led_control.sh manual 255 80 0
./scripts/led_control/led_control.sh off
./scripts/led_control/led_control.sh demo-wheel 20
./scripts/led_control/led_control.sh demo-palette 20

# Temperature-following color (blue=cold, red=hot)
./scripts/led_control/led_control.sh temp-follow --sensor cpu --cold 35 --hot 75 --interval 1

# Case sensor variant for 10 minutes
./scripts/led_control/led_control.sh temp-follow --sensor case --cold 30 --hot 60 --duration 600
```

Demo modes mirror `task_led.py` examples:

- `demo-wheel`: continuous rainbow wheel
- `demo-palette`: color stepping through a fixed palette

Preset colors available:

- `red`, `green`, `blue`, `orange`, `yellow`, `white`, `purple`, `cyan`
- `magenta`, `pink`, `teal`, `indigo`, `lime`, `gold`, `amber`
- `warmwhite`, `coolwhite`

## OLED pages (from `task_oled.py`)

Available pages:

1. `time`  - date/time/weekday
2. `usage` - IP + CPU/MEM/DISK usage
3. `temp`  - Pi temperature + case temperature
4. `fan`   - Pi/C1/C2 PWM dials

Show only one page (for example usage):

```bash
./scripts/oled_control/oled_control.sh show usage --restart-task
```

Show all pages again:

```bash
./scripts/oled_control/oled_control.sh show all --restart-task
```

List and inspect current OLED setup:

```bash
./scripts/oled_control/oled_control.sh list
./scripts/oled_control/oled_control.sh status
```

## Large screen dashboard (4.3 inch display)

The large UI apps are PyQt5 programs (`app_ui.py`, `app_ui_monitor.py`).

- On systems with desktop/X11/Wayland, they run normally.
- On headless systems, GUI output is not visible over plain SSH.
- Without a desktop, you may still run Qt directly on framebuffer/KMS (`eglfs` or `linuxfb`) from a local TTY if the graphics stack is available.

Check what is possible on your host:

```bash
./scripts/screen_control/screen_control.sh info
```

Launch dashboard:

```bash
./scripts/screen_control/screen_control.sh run-dashboard --backend auto
```

Launch monitor-only UI:

```bash
./scripts/screen_control/screen_control.sh run-monitor --backend auto
```
