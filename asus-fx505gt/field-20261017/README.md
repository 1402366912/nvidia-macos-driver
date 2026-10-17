# FX505GT 原生接线与现场结果（2026-10-17）

## 当前结果

- 在实际 FX505GT 上完成14路 Fn 的 ACPI、AsusSMC 和登录应用接线，Fn ABI3 会话已取得；不再仅交接头文件。
- 用户已实按确认 F6 背光开关、F7/F8 亮度调节三键正常。
- 静音档通过新 profile bridge 获固件 raw=1、IOReturn=0；界面三档也改接这条实际成功路径，并保存登录恢复偏好。没有把固件接受写成当前转速或噪声测量。
- “合盖保持运行”和“一直保持运行”已独立：实机先核到 lid=true/global SleepDisabled=0，再按用户明确要求开启一直运行并核到global=1。
- 音频从零 CoreAudio 设备推进到原生 AppleALC+SimpleHDA 加载，默认输入为内建麦克风，默认输出为内置扬声器。**原生栈的实际录音和按键物理效果仍需单独观察，不能用枚举替代。**
- 用户确认 F1/F2/F3 三声音键正常的反馈发生在前一 VoodooHDA368 阶段；之后才按用户“选效果好的一条”切换原生栈，未冒用前阶段反馈。

## 机器与工具链

FX505GT_FX95GT，i5-9300H、UHD630+GTX1650，x86_64 macOS26.5.2/build25F84，实测Darwin25.5.0；Xcode26.5/17F42，官方SDK26.5。固定 AsusSMC 输入 c15d2f297c86b65a3cb866cc2bcece595c136417，其他输入沿用 build/inputs.json。

完整源码、产物、官方包和完整必要日志位于196：
`G:/macOS-HyperV/Codex-work/mac38-integration-20261017`。
Git 从196直接提交推送，PR由GitHub CLI维护。此次仅提交当前必要文本，不提交SDK、驱动二进制、完整缓存或已解决失败日志。U盘回退没有改动。

## Fn 与面板接线

1. 修复 AppKit ARC 强实例变量直接传入 autoreleasing 输出参数的原生编译问题。
2. WMI参数从8字节补齐为真实20字节，reserved零初始化；只读发布加载DSDT，以实际输入核对热键，不将公共BIOS表冒充实机输入。
3. tools/prepare_fx505gt_oc_fn.py 根据已记录加载DSDT与14方法原字节生成OpenCore Patch：匹配完整MethodOp，只改四字符名称，Count=1，限定DSDT/Notebook。
4. 内置EFI保留既有ACPI修改，追加_Q0A.._Q15、_Q6B/_Q6C的14项重命名和配套启用SSDT；不覆盖整张DSDT。实际加载表含对应XQ定义，专用开关true。
5. 登录应用保存 HardwareFnEnabled 与显式Bluetooth控制选择，LaunchAgent自动运行；不在每次启动关闭消费者。
6. 面板只有bklt，没有上游预期dsyp。F6优先合法dsyp，否则用唯一AppleBacklightDisplay的bklt关/恢复原值；它不是物理断电。F7/F8改走Fn ABI3有序亮度队列，每次调整范围1/16并读回；不再重复发送无效HID。实际CLI亮度升降成功，用户也确认三屏幕键正常。
7. F12适配现有itlwm POWER ABI1，与HeliPort同一控制路径，不建立raw/AWDL会话。读取power=1已验。fxradio从 /Applications 中移到 root-owned0755 的固定 /Library/PrivilegedHelperTools/org.fx505gt.fxradio；原 /Applications 是原生root:admin0775，bundle内路径无法通过既有祖先目录检查。未修改 /Applications 权限。
8. F4事件已到达，VoodooHDA阶段日志实际交替报告默认输入muted/unmuted；这只证明驱动属性。新增仅在成功读回时出现的麦克风静音/恢复浮层，不以图标冒充录音效果。

## 风扇、合盖与手动睡眠

原软件把“合盖不睡”实现为全局SleepDisabled=1，用户选择后 F11 的 IOPMSleepSystem 返回0xe00002e2。根因是策略设计，不能归为用户错误。

现有AsusSMC增加受限 selector4：管理员客户端通过RootDomain的disable/enable clamshell控制合盖；客户端退出/驱动停止释放，完整唤醒时重申仍持有的合盖选择，不写全局禁睡。

华硕控制提供两项独立选择：
- 合盖保持运行：仅持有clamshell控制，仍允许手动睡眠。
- 一直保持运行：固定AsusAwake --hold 设置全局1；关闭或退出释放为0。该选择已按用户要求启用。

F11向现有华硕控制发统一请求，与菜单“立即睡眠”共用sleepNow。手动睡眠临时释放一直运行，唤醒后按原选择恢复；合盖选择保持独立。两个偏好独立保存。只读状态见 POWER-INSTALL.json。完整F11睡眠/唤醒物理循环尚未冒称已验。

旧界面asus-platform调用在新AsusSMC上返回unsupported，已改为固定fxprofile set silent/normal/overboost。实际静音回执成功，并保存PreferredFanProfile=2，登录时先恢复档位再顺序恢复两项电源选择。仅增加固定sudoers命令，非setuid、非任意root命令入口。

## 音频：真实codec与原生方案

旧已装VoodooHDA3.1.2仅匹配AMD0xAB381002，而控制器实际为Intel8086:A348。修正匹配仍受原生加载批准流程阻塞。用户要求CLI处理后使用kmutil自带 --no-authorization，安装官方Release368并按系统要求重启，出现扬声器、耳机、数字麦克风。默认输出最初误选耳机，已通过CoreAudio改成扬声器并读回，解除静音；随后用户确认三声音键正常。

官方getdump实际读得 **Realtek ALC235/10EC:0235**，subvendor1AB11043，DMIC pin0x12、speaker pin0x14。完整dump保留196，只提交关键摘录。

将控制器8086:A348交给OpCore-Simplify时不进入音频选择，因为它按codecID匹配；输入真实10EC:0235后实际进入Tahoe分支。选择AppleALC+SimpleHDA，needs_oclp=false；真实layout selector返回24。layout24含本机的DMIC0x12和speaker0x14拓扑。另一社区FX505的layout30并非本机ALC235支持值，没有盲抄。

原生配置：Lilu现有1.7.2→AppleALC1.9.8→SimpleHDA1.0.0 RELEASE，原签名HAL插件，layout24，必需keepsyms=1；没有增加verbose/debug屏幕滚动。audio/configure_native_audio.py仅生成本机候选配置；匹配OpenCore1.0.9 ocvalidate无问题。旧VoodooHDA移出/Library/Extensions，只重建AuxKC并保留既有7项、移除VoodooHDA，未写系统卷。原有SIP为custom、authenticated-root disabled；本轮未再更改SIP或TCC。

**原生启动已通过**：AppleALC与SimpleHDA均加载，VoodooHDA未加载。Apple的内建麦克风为默认输入，内建输出/内置扬声器为默认和系统输出，均2声道44.1kHz；microphone_mute=1能力可用。详见 AUDIO-NATIVE-POSTBOOT.json。实际录音输入仍与属性读回区分，没有采集或上传用户录音。

## 原生构建与核验

- AsusSMC、应用、fxprofile、fxradio、华硕控制及AsusAwake完成原生编译/链接。
- Fn队列针对性测试更新并通过；固定上游补丁在干净输入重放、源码hash核验通过；Windows manifest路径比较已修复。
- 现场启用SSDT用ACPICA20260408编译，0errors/0warnings/0remarks；不将其冒称另一固定版本完整build_cohort验收。
- 当前AsusSMC UUID：1B8C6438-740D-3078-84DF-CB8075D4476F。
- 匹配fxprofile SHA256：fec1eb33100f077a9dc97ed3b118c8cd5584740cb563f878a2d9f37646bd88bc。
- AppleALC UUID：34DB8015-25BF-36A8-AA54-19C4C35CC625；SimpleHDA UUID：8803BC2B-EC4E-3FE8-BFF3-EFF1EBD6B5DA。

## ACPI原始依据

追加前内核可见加载DSDT：291262字节，checksum0，SHA256
`2a872978e36c86480ca6981249b65bc68f30906a444e40732690b4d7750b21d6`。
公共BIOS303 fixture：291231字节，SHA256
`f1b78256c05a9dc8d31b33631d2d91c4a3490335f4a5025a9ca1f495043b3eda`。
14/14热键方法原字节hash完全一致；整表31字节差异不能据此断言协议不同。修改后加载DSDT SHA256：
`5c2af2e46eb3fdd805c5f9bda6d0dd010a2432fc45f7cfb0d137d7a65d371dfe`。

DSDT-loaded-hotkeys.json、相关DSL摘录和SSDT-FX505GT-Fn-live.dsl保存必要依据，完整AML/DSL保留196。OpenCore官方定义先Patch后Add，原有XOSI修改不改写新添加表中的Darwin检查：
https://github.com/acidanthera/OpenCorePkg/blob/master/Docs/Configuration.tex

## 未验与简短接续

当前原生栈的录音、F4物理静音效果及输入增益需按最新现场结果继续；F9无外屏，F10/键盘灯等依实际反馈区分；完整F11睡眠唤醒与F12无线开关不冒充已验。GPU-PV与本机原生NVIDIA/Metal结果独立。

后续先处理有实机依据的麦克风小问题，再继续单项Fn适配；不重复已确认正常的屏幕键测试，不将接线完成写成全部14键已可用。

最终非录音读数：默认输入device69未静音，左右输入增益0.5079；输出device78未静音，左右输出增益0.6474。最新原生阶段的物理F4事件已在09:15日志中出现，交替muted/unmuted均成功读回；见AUDIO-NATIVE-LEVELS.txt、FN-NATIVE-EVENTS.txt。POWER-NATIVE-STATE.txt再次核得SleepDisabled=1。这里仅保留已完成读数，不上传命令链后续超时或早期失败日志。
