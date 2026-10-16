# FX505GT 原生构建、部署和接线记录（2026-10-17）

本轮在实际 FX505GT_FX95GT 上完成 AsusSMC、菜单栏应用、fxprofile 和 fxradio 的原生编译与链接；新 AsusSMC 已从内置硬盘 EFI 加载，静音档请求得到固件成功回执。**这不代表全部 14 个 Fn 键已经可用**。专用 Fn 合同仍关闭，下面明确区分已经执行的结果和待接入部分。

## 输入与环境

- 源码基线：`14ea9f3aad2c1467fe5abb91a71d7a3b98e011eb`，加本 PR 小修复。
- 目标：i5-9300H、UHD630 + GTX1650、x86_64 macOS 26.5.2 / build 25F84。
- 原生工具链：Xcode 26.5 / 17F42；`xcrun --show-sdk-version` 为 26.5。
- AsusSMC、Lilu、VirtualSMC、MacKernelSDK 按现有固定输入准备；实际运行 Lilu 1.7.2、VirtualSMC 1.3.8。
- 本轮分别原生构建组件；没有宣称 `BUILD_COHORT.md` 固定入口的整套验收通过。实机反汇编 DSDT 使用 ACPICA 20260408，而整套入口另有固定版本要求。
- 源码、构建产物、完整成功日志、完整 DSDT 仍保存在 196 的 `G:/macOS-HyperV/Codex-work/mac38-integration-20261017`。本目录只提供当前接线需要的记录和片段。

## 本 PR 的小修复

1. AppKit 应用在 ARC 下不能直接把强引用实例变量地址作为 autoreleasing 输出参数传给 helper 校验函数；改用局部 NSString，再赋值给实例变量。解决实际原生编译错误。
2. FX505GT 的 WMxx 请求需要完整 20 字节参数缓冲区；原结构只有 8 字节。补三个零初始化 reserved 字段，与此前实机已发现的调用约定一致。
3. 仅在 FX505GT profile bridge 已启用时，发布只读 `FX505GTDSDT` 属性，取得内核当前可见的 DSDT，用于匹配实际 Fn 接线。它不是已证明的原始 BIOS 表。
4. Windows 准备脚本使用 POSIX 相对路径核 manifest，避免反斜杠误判。另恢复整理中产生的 UTF-8 版权字符；该字符恢复晚于现场构建，不影响接线逻辑。同步更新可重放补丁与哈希；补丁已经在干净的固定 AsusSMC 源码上重放并通过源码哈希核验。

## 已执行与结果

- AsusSMC 完整原生编译、链接成功；应用、CLI、fxradio 原生构建成功。
- 新应用安装到 `/Applications/FX505GT Control.app`，通过 `open -g` 启动并观察到进程。未把进程存在等同于界面和所有操作可用。
- helper 安装到 `/Library/PrivilegedHelperTools/org.fx505gt.fxprofile`，root 所有、0755；二进制 SHA256：`20c1f584a7f8b791b5fb87274c466df07e63c0fcddb49efddcac5adfc9537901`。
- 新加载 AsusSMC UUID：`E19246A5-E727-3814-AC3D-A34BB575B71E`；部署后二进制 SHA256：`4fb306ded6bdb454d1444792979995ebea201425f5a79a81bfab27fe1641d0dc`。
- 实机 CLI 回执见 [profile-live.txt](profile-live.txt)：bridge ready、WMI verified、supported mask 0x7。
- 执行一次 `sudo fxprofile set silent`：raw=1、IOReturn=0、accepted_count=1。这里只证明请求被固件接受，**没有物理风扇 RPM、噪声或当前档位读回结果**。`current_profile` 仍为 unknown。
- 现场启用 `FX505GTProfileBridgeEnabled`、FnF5；`DedicatedFnContractEnabled` 仍 false。仓库默认配置与这次现场启用变体有区别。
- 没有物理按键验收；记录 fn_events=0。新应用没有新增开机自启，也没有启用专用 Fn listener / Bluetooth companion。
- `system_profiler SPAudioDataType -json` 的音频设备列表为空，因此音量和麦克风功能还依赖音频接入；本轮没有扩大成 AppleHDA 修复任务。
- 与无线驱动合批只重启一次。只改内置 EFI；U 盘回退未改。此前用户确认的合盖唤醒未重复测试。

## 当前 Fn / ACPI 接线阻点

实际**内核可见、已经加载的** DSDT 为 291262 字节，SHA256：
`2a872978e36c86480ca6981249b65bc68f30906a444e40732690b4d7750b21d6`，校验和为零。
现有 BIOS303 fixture 是 291231 字节，SHA256：
`f1b78256c05a9dc8d31b33631d2d91c4a3490335f4a5025a9ca1f495043b3eda`。

整表相差 31 字节，但选出的 **14/14 个 _Q 方法原字节哈希与 BIOS303 fixture 一致**。不能仅凭整表哈希不同断言 BIOS 或热键协议不同；加载表可能包含 OpenCore 既有修改。也不能把这个加载表冒充未修改的原始固件表。

- [DSDT-loaded-hotkeys.json](DSDT-loaded-hotkeys.json)：表头、长度、checksum、14 个方法的偏移及哈希。
- [DSDT-loaded-hotkeys.dsl.txt](DSDT-loaded-hotkeys.dsl.txt)：带命名空间和上下文的 22 个相关方法摘录，包含 14 个 _Q 和关联通知/亮度方法。
- 完整 AML、2 MB DSL 保留在 196；本 PR 不重复上传整份固件反汇编。

本轮没有向不匹配的整表直接套用 BIOS303 替换文件，没有盲目取消精确哈希检查。下一步应根据这些现有相同热键方法，为当前加载表准备匹配的 ACPI rename / SSDT 部署方案，同时保留其他已有 ACPI 修改，然后开启 Fn ABI2 应用消费路径。**不需要重新逆向全部 14 个键**。

## 建议接续

先完成匹配当前 ACPI 表的专用 Fn 接线和原生应用事件消费，再一次性做实际按键确认。音量/麦克风要另接实际音频设备。HDMI 无外接屏，本轮未测；GPU-PV 与本机原生 NVIDIA 驱动进度独立计算。
