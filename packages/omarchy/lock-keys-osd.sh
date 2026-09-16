#!/usr/bin/env bash
# Show an Omarchy OSD when Caps Lock or Num Lock changes state.
# Omarchy has no lock-key indicator, and its Caps Lock key is Compose (real
# Caps Lock is both Shifts), so a stray toggle is easy to miss.
# Reads the keyboard LED class files, which the compositor keeps in sync; no
# LED uevents exist, so it polls. Run by the lock-keys-osd systemd user service
# (nix/home/omarchy.nix).
set -u

interval="${LOCK_KEYS_OSD_INTERVAL:-0.3}"

# Prints 1 when any keyboard has that LED on, else 0. Several keyboards (an
# external one plugged in) each expose their own LED; the compositor sets all.
led_state() {
  local f state=0
  for f in /sys/class/leds/*::"$1"/brightness; do
    [[ -r $f ]] || continue
    if [[ $(<"$f") != 0 ]]; then
      state=1
      break
    fi
  done
  echo "$state"
}

show() {
  local label=$1 state=$2
  if [[ $state == 1 ]]; then
    omarchy-osd -i keyboard -m "$label on" || true
  else
    omarchy-osd -i keyboard -m "$label off" || true
  fi
}

caps=$(led_state capslock)
num=$(led_state numlock)

while sleep "$interval"; do
  new_caps=$(led_state capslock)
  new_num=$(led_state numlock)
  if [[ $new_caps != "$caps" ]]; then
    show "Caps Lock" "$new_caps"
    caps=$new_caps
  fi
  if [[ $new_num != "$num" ]]; then
    show "Num Lock" "$new_num"
    num=$new_num
  fi
done
