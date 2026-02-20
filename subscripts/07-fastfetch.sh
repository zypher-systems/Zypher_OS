#!/bin/bash
echo "📝 [7/10] Installing Fastfetch Config..."

mkdir -p "$HOME/.config/fastfetch"
cat >"$HOME/.config/fastfetch/config.jsonc" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "builtin",
        "height": 15,
        "width": 30,
        "padding": {
            "top": 5,
            "left": 3
        }
    },
    "modules": [
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;32m╭──────────────────────── \u001b[1;97mHardware\u001b[1;32m ────────────────────────╮"
        },
        {
            "type": "host",
            "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mPC",
            "keyColor": "bright_green"
        },
        {
            "type": "cpu",
            "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mCPU",
            "keyColor": "bright_green"
        },
        {
            "type": "gpu",
            "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mGPU",
            "keyColor": "bright_green"
        },
        {
            "type": "memory",
            "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mRAM",
            "keyColor": "bright_green"
        },
        {
            "type": "disk",
            "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mStorage",
            "keyColor": "bright_green"
        },
        {
            "type": "custom",
            "format": "\u001b[1;32m╰──────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;33m╭──────────────────────── \u001b[1;97mSoftware\u001b[1;33m ────────────────────────╮"
        },
        {
            "type": "os",
            "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mOS",
            "keyColor": "bright_yellow"
        },
        {
            "type": "kernel",
            "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mKernel",
            "keyColor": "bright_yellow"
        },
        {
            "type": "bios",
            "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mBIOS",
            "keyColor": "bright_yellow"
        },
        {
            "type": "packages",
            "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mPackages",
            "keyColor": "bright_yellow"
        },
        {
            "type": "shell",
            "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mShell",
            "keyColor": "bright_yellow"
        },
        {
            "type": "custom",
            "format": "\u001b[1;33m╰──────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;34m╭─────────────────── \u001b[1;97mDesktop Environment\u001b[1;34m ──────────────────╮"
        },
        {
            "type": "de",
            "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mDE",
            "keyColor": "bright_blue"
        },
        {
            "type": "lm",
            "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mLogin Manager",
            "keyColor": "bright_blue"
        },
        {
            "type": "wm",
            "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mWindow Manager",
            "keyColor": "bright_blue"
        },
        {
            "type": "wmtheme",
            "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mTheme",
            "keyColor": "bright_blue"
        },
        {
            "type": "terminal",
            "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mTerminal",
            "keyColor": "bright_blue"
        },
        {
            "type": "custom",
            "format": "\u001b[1;34m╰──────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;35m╭─────────────────── \u001b[1;97mNetwork & System\u001b[1;35m ───────────────────╮"
        },
        {
            "type": "localip",
            "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mLocal IP",
            "keyColor": "bright_magenta"
        },
        {
            "type": "wifi",
            "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mWiFi",
            "keyColor": "bright_magenta"
        },
        {
            "type": "command",
            "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mOS Age",
            "keyColor": "bright_magenta",
            "text": "birth_install=$(stat -c %W /); current=$(date +%s); time_progression=$((current - birth_install)); days_difference=$((time_progression / 86400)); echo $days_difference days"
        },
        {
            "type": "uptime",
            "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mUptime",
            "keyColor": "bright_magenta"
        },
        {
            "type": "datetime",
            "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mDateTime",
            "keyColor": "bright_magenta"
        },
        {
            "type": "custom",
            "format": "\u001b[1;35m╰────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;90m                    ╭─ \u001b[1;97mPowered by Zypher Systems\u001b[1;90m ─╮"
        },
        {
            "type": "custom",
            "format": "\u001b[1;90m                    ╰─ \u001b[1;97mCustom Fastfetch Config\u001b[1;90m ───╯"
        }
    ]
}
EOF

echo "✅ ZypherOS Configuration Complete!"
echo "   Running fastfetch to verify..."
