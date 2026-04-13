# Box for Root

> 🌐 **Unofficial translation fork** of [boxproxy/box](https://github.com/boxproxy/box).
> The original project is written in Chinese. This fork provides:
> 🇬🇧 **English** — you are here (`translate/en`) | 🇷🇺 **Русский** — [README on translate/ru](https://github.com/Rahspide/box-en_ru/blob/translate/ru/README.md)

---

`Box for Root` is a transparent proxy toolbox module designed for Android root environments (Magisk / KernelSU / APatch).

This project is heavily inspired by and continues the work of:
- [CHIZI-0618/box4magisk](https://github.com/CHIZI-0618/box4magisk)
- [taamarin/box_for_magisk](https://github.com/taamarin/box_for_magisk)

## Project Overview

This repository primarily provides:
- Unified management of core proxy services (mihomo / sing-box / xray / v2fly / hysteria)
- Transparent proxy rule configuration in multi-network mode (TProxy / Redirect / Tun / Mixed / Enhance)
- Unified scripts for subscription maintenance, Geo resources, core binaries, and WebUI
- Modular directory structure and service lifecycle management adapted to the Android Root ecosystem

## Main Directory

Module working directory: `/data/adb/box/`

```text
/data/adb/box/
├── bin/                # Proxy core and utility binaries
├── mihomo/             # mihomo configuration directory
├── sing-box/           # sing-box configuration directory
├── xray/               # xray configuration directory
├── v2fly/              # v2fly configuration directory
├── hysteria/           # hysteria configuration directory
├── scripts/            # Core scripts
│   ├── box.service     # Service lifecycle management
│   ├── box.iptables    # Transparent proxy rule management
│   └── box.tool        # Update and maintenance toolkit
├── run/                # Runtime state and logs
└── settings.ini        # Global configuration file
```

## Core Scripts

- `box.service`: manage start, stop, restart, status, and scheduled tasks
- `box.iptables`: enable, rebuild, and clear transparent proxy rules
- `box.tool`: update subscriptions, update Geo, update core, verify configuration, maintain WebUI

## Documentation & Community

- Wiki: <https://github.com/boxproxy/box/wiki>
- Changelog: [CHANGELOG.md](./CHANGELOG.md)
- Companion app / notification channel: <https://t.me/zero_o0>

## Acknowledgements

Thanks to the original [boxproxy/box](https://github.com/boxproxy/box) project and all contributors.

## License

This project is licensed under the [GPL-3.0 License](./LICENSE).
