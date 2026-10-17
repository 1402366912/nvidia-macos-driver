# FX505GT 音频现场

当前 PCI 控制器 Intel8086:A348，不等于 codecID。OpCore-Simplify 的实际 selector 对这个 controller-only 输入不选择 AppleALC/SimpleHDA，也不进入 Tahoe 音频菜单。真实 codec 待驱动附着后读取，不能填推测的 Realtek ID。依据见 ../field-20261017/OpCore-ALC235-selection.json。

官方 VoodooHDA Release368：
https://github.com/CloverHackyColor/VoodooHDA/releases/tag/Release368

官方资产 VoodooHDA.kext-368.zip 原包 SHA256：
9aaa01b245f4827b2de5edfdc028700b9bc8823f03bfb1daf280b8571f88adb0

本目录只保存现场必要 Info.plist：限制 IntelA348 单一 personality，启用源码已有 mute/volume-change 修正，Verbose1；不混入 AMD HDMI。此文件不是原包，不上传驱动二进制。使用前与原包结合，按本机权限与签名要求安装。

现场位置 /Library/Extensions/VoodooHDA.kext。旧 EFI 的同名3.1.2 已禁用，避免与 AuxKC 的368冲突。原生 kmutil load 最初返回未批准；用户要求 CLI 处理后使用当前 kmutil 自带 --no-authorization，返回需要重启。现有 SIP 已为 custom（kext signing/filesystem/NVRAM restrictions disabled，authenticated-root disabled）；本轮未再修改 SIP/TCC，也没有修改系统卷。命令回显还列出既有待处理 Synology/RVI 扩展；本轮没有复制或更改它们。

安装、重启或正确 PCI 匹配都不等于扬声器/麦克风可用。最终附着与 codec、CoreAudio 结果以现场回执为准。

## 原生路线

实测 codec10EC:0235；OpCore选择 AppleALC+SimpleHDA、layout24。原始输入、选择与引脚摘录在 field-20261017。

资产：
- AppleALC1.9.8 RELEASE：https://github.com/acidanthera/AppleALC/releases/tag/1.9.8，zip SHA256 d4d36cd2da7863cf7cbfcb0892d45c08457f4f4ddd065a073dd010e46bd63bcb。
- SimpleHDA1.0.0 RELEASE：https://github.com/laobamac/SimpleHDA/releases/tag/v1.0.0，zip SHA256 89198256664078c91155d673ee7cebb08134dad1b71d5e34b0aa4ef0d4877f8f。包含 HAL安装包，已在目标安装。

Lilu→AppleALC→SimpleHDA；keepsyms=1；layout24。旧 VoodooHDA从 /Library/Extensions 移至现场 native/VoodooHDA368-inactive.kext，并只重建既有成员的 AuxKC，排除VoodooHDA，避免同时附着。

configure_native_audio.py 仅生成本机候选config，不安装驱动、不重启。传入原config与新输出路径，之后用匹配版本ocvalidate检查。此脚本不是任何FX505通用EFI。

原生栈已实际启动：AppleALC1.9.8、SimpleHDA1.0.0 加载，VoodooHDA未加载；内建麦克风和内置扬声器成为默认。详见 AUDIO-NATIVE-POSTBOOT.json；真实录音效果未由设备枚举代替。
