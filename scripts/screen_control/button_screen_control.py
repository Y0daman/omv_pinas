#!/usr/bin/env python3
import argparse
import glob
import os
import subprocess
import threading
from gpiozero import Button
from signal import pause


class ScreenPowerController:
    def __init__(self, on_cmd, off_cmd, force_brightness):
        self.on_cmd = on_cmd
        self.off_cmd = off_cmd
        self.force_brightness = force_brightness
        self.backlight_path = self._find_backlight_path()
        self._saved_brightness = None

    def _find_backlight_path(self):
        candidates = sorted(glob.glob("/sys/class/backlight/*"))
        return candidates[0] if candidates else None

    def _run_cmd(self, cmd):
        if not cmd:
            return
        try:
            subprocess.run(["/bin/bash", "-lc", cmd], check=False)
        except Exception:
            pass

    def _write_file(self, path, value):
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(str(value))
            return True
        except Exception:
            return False

    def _read_int(self, path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return int(f.read().strip())
        except Exception:
            return None

    def set_on(self):
        self._run_cmd(self.on_cmd)

        if not self.backlight_path:
            return

        bl_power = os.path.join(self.backlight_path, "bl_power")
        brightness = os.path.join(self.backlight_path, "brightness")
        max_brightness = os.path.join(self.backlight_path, "max_brightness")

        self._write_file(bl_power, 0)

        if self.force_brightness is not None:
            self._write_file(brightness, self.force_brightness)
        elif self._saved_brightness is not None:
            self._write_file(brightness, self._saved_brightness)
        else:
            max_val = self._read_int(max_brightness)
            if max_val is not None:
                self._write_file(brightness, max_val)

    def set_off(self):
        self._run_cmd(self.off_cmd)

        if not self.backlight_path:
            return

        bl_power = os.path.join(self.backlight_path, "bl_power")
        brightness = os.path.join(self.backlight_path, "brightness")

        current = self._read_int(brightness)
        if current is not None and current > 0:
            self._saved_brightness = current

        self._write_file(brightness, 0)
        self._write_file(bl_power, 1)


def parse_args():
    p = argparse.ArgumentParser(
        description="Button-based screen/backlight control with short/long press behavior"
    )
    p.add_argument("--gpio-pin", type=int, default=17, help="BCM GPIO pin for button input")
    p.add_argument("--active-low", action="store_true", default=True, help="Button is active-low (default)")
    p.add_argument("--active-high", action="store_true", help="Button is active-high")
    p.add_argument("--pull-up", action="store_true", default=True, help="Enable pull-up resistor (default)")
    p.add_argument("--pull-down", action="store_true", help="Use pull-down resistor")
    p.add_argument("--hold-seconds", type=float, default=0.8, help="Long-press threshold in seconds")
    p.add_argument("--debounce-seconds", type=float, default=0.05, help="Button debounce seconds")
    p.add_argument(
        "--on-cmd",
        default="vcgencmd display_power 1",
        help="Command run when turning screen on",
    )
    p.add_argument(
        "--off-cmd",
        default="vcgencmd display_power 0",
        help="Command run when turning screen off",
    )
    p.add_argument(
        "--force-brightness",
        type=int,
        default=None,
        help="Force specific backlight brightness when turning on",
    )
    return p.parse_args()


def main():
    args = parse_args()

    active_low = True
    if args.active_high:
        active_low = False
    elif args.active_low:
        active_low = True

    pull_up = True
    if args.pull_down:
        pull_up = False
    elif args.pull_up:
        pull_up = True

    button = Button(
        args.gpio_pin,
        pull_up=pull_up,
        active_state=not active_low,
        hold_time=args.hold_seconds,
        bounce_time=args.debounce_seconds,
    )

    screen = ScreenPowerController(args.on_cmd, args.off_cmd, args.force_brightness)

    lock = threading.Lock()
    state = {
        "screen_on": True,
        "hold_mode": False,
    }

    def on_press():
        with lock:
            state["hold_mode"] = False

    def on_held():
        with lock:
            state["hold_mode"] = True
        screen.set_on()

    def on_release():
        with lock:
            hold_mode = state["hold_mode"]
            if hold_mode:
                state["hold_mode"] = False

        if hold_mode:
            screen.set_off()
            with lock:
                state["screen_on"] = False
            return

        with lock:
            state["screen_on"] = not state["screen_on"]
            target_on = state["screen_on"]

        if target_on:
            screen.set_on()
        else:
            screen.set_off()

    button.when_pressed = on_press
    button.when_held = on_held
    button.when_released = on_release

    print(
        f"Button screen controller running on GPIO{args.gpio_pin} "
        f"(hold={args.hold_seconds}s debounce={args.debounce_seconds}s)"
    )
    pause()


if __name__ == "__main__":
    main()
