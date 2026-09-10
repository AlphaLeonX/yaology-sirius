# Sirius

> **Native, zero-permission Mac backlight governor that automatically dims your MacBook display when using external monitors.**  
> Dim the noise. Protect your focus. Prolong hardware lifespan.

**English** · [简体中文](README_CN.md)

[![Release](https://img.shields.io/github/v/release/AlphaLeonX/yaology-sirius?style=flat-square&color=38bdf8)](https://github.com/AlphaLeonX/yaology-sirius/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple)](https://github.com/AlphaLeonX/yaology-sirius)
[![License](https://img.shields.io/badge/License-MIT-emerald?style=flat-square)](LICENSE)

[🌐 Official Website (sirius.yaology.com)](https://sirius.yaology.com) · [⬇️ Download Latest (.dmg)](https://github.com/AlphaLeonX/yaology-sirius/releases/latest/download/Sirius-latest.dmg)

---

## 🎯 Why Sirius? The Problem & Pain Points

When using a MacBook alongside an external monitor, most developers and creators face an annoying set of trade-offs:

1. **Dual-Screen Distraction**: Your primary visual focus is on the large monitor, but the adjacent MacBook screen sits at full brightness. Its glare and motion constantly intrude on your peripheral vision, fragmenting deep focus.
2. **Clamshell Mode Frustrations**:
   - Closing the lid sacrifices the MacBook's native trackpad, keyboard, and Touch ID;
   - The keyboard area acts as an essential passive thermal exhaust—closing the lid traps heat and accelerates fan noise or CPU throttling under sustained load.
3. **Open-Lid Heat & Battery Drain**: Keeping the built-in screen at 100% brightness needlessly drains battery power, increases chassis temperatures, and wears down the backlight array.
4. **The Flaw of "Dimming" Apps (Fake Overlays)**: Most existing dimming apps merely draw a semi-transparent black overlay window (`NSWindow`). The physical Mini-LED / LCD backlight remains 100% powered on—providing **zero thermal relief, zero power reduction**, and corrupting system screenshots and color accuracy.

---

## ✨ Key Features & Technical Highlights

### 1. Hardware PWM Backlight Governor
Sirius communicates directly with macOS display hardware controllers (`DisplayServices`) to dial down the physical backlight:
- **True Cooling & Battery Savings**: Turns down the actual LEDs from the hardware layer, keeping your Mac cool and preserving battery health;
- **Zero Screenshot Interference**: No virtual overlay windows are drawn—your screenshots and macOS color management stay pixel-perfect.

### 2. Sub-Millisecond Cursor Sensing
- **Instant Wake (0ms)**: The millisecond your cursor crosses back onto your MacBook screen, brightness smoothly eases in within 0.15s. By the time your eyes shift focus, the screen is already fully restored;
- **Anti-Jitter Cooldown**: Moving your cursor back to your external monitor initiates a 3.0s grace period (configurable), preventing annoying flicker from accidental edge brushes, before smoothly easing down in 0.4s.

### 3. Ambient Floor
- Defaults to a comfortable 12% ambient glow (customizable from 0% to 30%), preventing the jarring disorientation of an abrupt pitch-black void;
- Slack, WeChat, and system notification banners remain readable at a glance.

### 4. Zero Permissions Required (Zero-Permission)
- Built entirely with native Cocoa APIs (`NSEvent.mouseLocation` and Carbon hotkeys);
- **Never asks for sensitive Accessibility, Screen Recording, or Input Monitoring permissions**;
- Pure Swift + AppKit: ~15MB RAM footprint, virtually 0.00% idle CPU usage.

### 5. Seamless Shortcuts & Controls
- **Global Hotkey**: Press `⌥ + S` (Option + S) at any time to toggle dimming on/off;
- **Timed Pauses**: One-click "Pause for 30m / 1h" during meetings or screen-sharing presentations.

---

## ⬇️ Download & Installation

### Option 1: Direct DMG Download
Download the latest `Sirius-latest.dmg` from the [Releases page](https://github.com/AlphaLeonX/yaology-sirius/releases/latest), open it, and drag Sirius into your `Applications` folder.

> **Prompted with "Unidentified Developer"?**  
> Because this open-source project does not carry a paid Apple enterprise signing certificate, macOS Gatekeeper may present a security prompt on first launch. Run this one-liner in Terminal to permanently clear it:
> ```bash
> xattr -cr /Applications/Sirius.app
> ```

### Option 2: Terminal One-Liner Install
```bash
curl -fsSL https://raw.githubusercontent.com/AlphaLeonX/yaology-sirius/main/scripts/install.sh | bash
```

---

## 🛠️ Building from Source (Optional)

Sirius is built with zero third-party dependencies using the standard macOS Swift toolchain:

```bash
# 1. Clone the repository
git clone https://github.com/AlphaLeonX/yaology-sirius.git
cd yaology-sirius

# 2. Run locally in debug mode
make run

# 3. Build standalone macOS application (.app)
make app
```

---

## ❓ FAQ

**Q: Why does Sirius only activate when an external display is connected?**  
A: Sirius is purpose-built for dual-display workflows. It engages only when an external display is active and the MacBook screen is open. When running standalone on your laptop, your MacBook retains standard macOS brightness controls.

**Q: What happens if I set the Ambient Floor to 0%?**  
A: At 0%, the internal backlight completely powers off (true pitch black) when you shift away. If you wish to keep notification badges and window outlines visible, we recommend keeping the default 10%~15%.

**Q: Why doesn't Sirius require Accessibility permissions?**  
A: Sirius only queries the global cursor coordinates using public macOS mouse APIs to check whether the cursor lies within the MacBook's screen bounds. It does not monitor keystrokes, capture pixels, or intercept system events.

---

## 📄 License

Distributed under the [MIT License](LICENSE). Free of charge, no ads, no in-app purchases, zero telemetry.
