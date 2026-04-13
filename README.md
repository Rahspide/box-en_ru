# Box for Root

`Box for Root` is a transparent proxy toolbox module for Android root environments (Magisk / KernelSU / APatch).

The project draws significant inspiration from the following repositories and continues to evolve based on them:
- [CHIZI-0618/box4magisk](https://github.com/CHIZI-0618/box4magisk)
- [taamarin/box_for_magisk](https://github.com/taamarin/box_for_magisk)

## Project Overview

This repository primarily provides:
- Unified management of core proxy operations (mihomo / sing-box / xray / v2fly / hysteria)
- Transparent proxy rule orchestration in multi-network modes (TProxy / Redirect / Tun / Mixed / Enhance)
- Unified maintenance scripts for subscriptions, Geo resources, core binaries, and the WebUI
- Modular directory and service lifecycle management tailored for the Android root ecosystem

## Main Directory

Module Working Directory: `/data/adb/box/`

```text
/data/adb/box/
├── bin/                # Proxy core and tool binaries
├── mihomo/             # mihomo configuration directory
├── sing-box/           # sing-box configuration directory
├── xray/               # xray configuration directory
├── v2fly/              # v2fly configuration directory
├── hysteria/           # hysteria configuration directory
├── scripts/            # Core scripts
│   ├── box.service     # Service lifecycle management
│   ├── box.iptables    # Transparent proxy rule management
│   └── box.tool        # Update and maintenance toolset
├── run/                # Runtime status and logs
└── settings.ini        # Global configuration file
```

## Core Scripts

- `box.service`: Control for starting, stopping, restarting, status, and scheduled tasks
- `box.iptables`: Enable, rebuild, and clean up transparent proxy rules
- `box.tool`: Subscription updates, Geo updates, core updates, configuration checks, and WebUI-related maintenance

## Documentation and Community

- Wiki: <https://github.com/boxproxy/box/wiki>
- Changelog: [CHANGELOG.md](./CHANGELOG.md)
- Companion app / notification channel: <https://t.me/zero_o0>

## Acknowledgments

We would like to thank the open-source community and the authors of the above projects for their design ideas and implementation references.