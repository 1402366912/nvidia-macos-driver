#!/usr/bin/env python3
"""Prepare this measured FX505GT ALC235/25.x audio config; does not install or reboot."""
import plistlib
import sys
from pathlib import Path
source, output = map(Path, sys.argv[1:3])
d = plistlib.loads(source.read_bytes())
for entry in d["Kernel"]["Add"]:
    if entry["BundlePath"] == "VoodooHDA.kext":
        entry["Enabled"] = False
entries = [e for e in d["Kernel"]["Add"] if e["BundlePath"] not in ("AppleALC.kext", "SimpleHDA.kext")]
for name in ("AppleALC", "SimpleHDA"):
    entries.append({"Arch": "x86_64", "BundlePath": name+".kext", "Comment": "ALC235 native audio "+name,
        "Enabled": True, "ExecutablePath": "Contents/MacOS/"+name, "MaxKernel": "25.99.99",
        "MinKernel": "25.0.0", "PlistPath": "Contents/Info.plist"})
d["Kernel"]["Add"] = entries
for e in d["Kernel"].get("Block", []):
    if e.get("Identifier") in ("com.apple.driver.AppleHDA", "com.apple.iokit.IOHDAFamily"):
        e["Enabled"] = False
p = d["DeviceProperties"]["Add"].setdefault("PciRoot(0x0)/Pci(0x1F,0x3)", {})
p["layout-id"] = (24).to_bytes(4, "little")
p.pop("alc-layout-id", None)
n = d["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]
args = [x for x in n.get("boot-args", "").split() if not x.startswith("alcid=")]
if "keepsyms=1" not in args:
    args.append("keepsyms=1")
n["boot-args"] = " ".join(args)
output.write_bytes(plistlib.dumps(d, sort_keys=False))
print("Prepared AppleALC -> SimpleHDA, ALC235 layout24; old VoodooHDA EFI entry disabled.")
