# 华硕风扇与睡眠界面

复用现场华硕控制应用，不安装第二套电源策略。

- 合盖保持运行：AsusAwake --lid-hold 通过现有 AsusSMC selector 4 禁用 clamshell 睡眠；不写 pmset disablesleep。客户端关闭时恢复合盖行为。
- 一直保持运行：AsusAwake --hold 设置 SleepDisabled=1；关闭选项或退出应用时释放。两项偏好独立。
- Fn+F11 与菜单“立即睡眠”都由 org.fx505gt.sleep-request 进入同一 sleepNow 方法，手动睡眠临时释放全局保持；唤醒后恢复原一直运行选择。合盖保持不阻止手动睡眠。
- sudoers.rule 为现场用户名和固定绝对路径，只允许列出的固定命令。不可作为不检查用户名的通用安装器。

原生构建：
```sh
xcrun clang -arch x86_64 -fobjc-arc -Wno-deprecated-declarations platform/AsusControl.m -framework Cocoa -framework IOKit -o AsusControl
xcrun clang -arch x86_64 -fobjc-arc -Wno-deprecated-declarations -Iinclude platform/AsusAwake.m -framework Foundation -framework IOKit -o AsusAwake
```

沿用 /Applications/华硕控制.app，bundle ID local.asus.platform.ui；AsusAwake 安装至 /Library/PrivilegedHelperTools/ASUSPlatform/。先安装支持 selector 4 的配套 AsusSMC，重启后再启用合盖保持；不要仅替换界面而沿用旧内核模块。

无线辅助程序 fxradio 需安装为 root:wheel 0755 的 /Library/PrivilegedHelperTools/org.fx505gt.fxradio（普通非 setuid 程序）。/Applications 为原生 root:admin 0775，原来的 bundle 内路径无法通过固定程序的祖先目录可写性校验；无需修改 /Applications 权限。
