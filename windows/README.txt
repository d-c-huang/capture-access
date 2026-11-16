Capture Access for Windows · v0.8.0
==================================

用途
Windows 版为普通桌面应用处理 SetWindowDisplayAffinity 截图保护。
选中窗口并解除后，使用 Windows 系统截图或其他截图工具获取图片。
主界面采用简洁浅色布局：窗口列表、蓝色主要操作按钮、状态提示和操作日志。
Windows 版不提供 macOS 版的直接框选、截图预览或历史功能。

下载与使用
从本项目的 GitHub Releases 下载 CaptureAccess-Windows.zip：
https://github.com/d-c-huang/capture-access/releases/latest
完整解压 ZIP，保留 CaptureAccess.exe、bin 和 tests 文件夹的相对位置。
运行 CaptureAccess.exe，刷新窗口列表，选择目标窗口，点击“解除选中窗口”。
可按 Ctrl 多选。筛选或刷新列表不会自动修改其他窗口。
“持续解除”每秒检查已选择窗口。“恢复原设置”恢复本次记录的全部窗口，正常退出时也会尝试恢复。
目标应用以管理员身份运行时，可点击“以管理员重启”。
窗口重建、目标应用重启或出现新窗口后，需要重新刷新并选择。

设置
主窗口右上角点击“设置”：
- “登录 Windows 时启动 Capture Access”：默认关闭，仅为当前用户设置，不需要管理员权限。
  使用当前程序位置；移动解压文件夹后，请重新勾选以更新启动位置。
  关闭时只删除 Capture Access 自己的登录启动项，不影响其他应用。
- “启动时自动检查更新”：默认开启，每 24 小时最多在启动时检查一次。
  关闭后仍可随时点击“检查更新”。

版本检测与下载
主窗口和设置都提供“检查更新”。更新检查在后台运行，不阻塞窗口列表或解除/恢复操作。
仅查询本项目公开的 GitHub 最新正式版本，不检查草稿或预发布版本。
发现更高版本且存在 Windows 包时显示“下载更新”，点击后在默认浏览器打开该包的 GitHub 下载地址。
如果新版尚未提供 Windows 包，仅提供“查看发布页”，不会下载 macOS 或其他平台文件。
更新查询有超时和错误提示；网络故障或 GitHub 查询频率限制不会影响现有功能。
本版本不自动安装、不自动运行下载的文件，也不覆盖正在运行的旧版本。
下载完成后，先退出旧版以恢复窗口设置，再完整解压并运行新版。
更新查询仅请求 GitHub 版本信息，不发送截图、窗口标题、窗口列表或操作日志。
自动检查偏好及上次检查时间保存在当前用户本地应用数据中的 CaptureAccess/updates.json。

源码项目目录
src/App.cs              WinForms 主界面、窗口列表及保护操作
src/SettingsForm.cs     设置窗口、登录启动及更新偏好入口
src/Updates.cs          GitHub 正式版本检测、平台下载链接校验及本地偏好
src/WindowsStartup.cs  当前用户登录启动项
src/helper.cpp         校验目标窗口并调用线程钩子的原生辅助程序
src/hook.cpp           在目标窗口线程中修改并验证截图保护标志
src/protocol.h         x86/x64 共用的 IPC 协议
src/demo.cpp           带截图保护的测试窗口
src/app.manifest       Windows 兼容性与 DPI 配置
build.ps1              构建脚本
 tests/updates.ps1     更新、偏好和启动命令测试
 tests/integration.ps1 核心功能集成测试
TEST-REPORT.txt        实际验证结果和兼容性范围

构建环境与命令
Windows + Visual Studio 2022 C++ Build Tools（x86/x64 编译工具和 Windows SDK）。
主界面使用系统自带 .NET Framework C# 编译器，面向 C# 5 / .NET Framework 4.x；原生组件静态链接 C/C++ 运行库。
在本目录的 PowerShell 中执行：
  .\build.ps1
默认输出目录为 dist，启动程序为 dist\CaptureAccess.exe。
可指定输出目录：
  .\build.ps1 -OutDir D:\build\capture-access

测试
更新相关自动检查（不访问网络，也不修改登录启动项）：
  .\tests\updates.ps1
包括数字版本比较、草稿/预发布过滤、恶意下载 URL 拒绝、平台包选择、24 小时间隔、偏好持久化与启动路径引用。
主界面的“打开测试窗口”可启动自带演示程序。
核心集成测试（会启动并关闭项目自己的演示窗口）：
  .\tests\integration.ps1
集成测试默认要求 64 位 Windows，测试 x64 和 x86 两种目标进程。
更新的实际网络查询、浏览器下载、登录启动和不同 DPI 的界面需在 Windows 中人工核对。

兼容性
面向 Windows 10 x86/x64 与 Windows 11 x64，不支持 ARM64 Windows。
此前 Windows 11 核心功能已验证；Windows 10 实机尚未验证。
仅处理 SetWindowDisplayAffinity 的窗口保护，不保证解除 DRM 视频、驱动级保护或受保护进程限制。
持续解除采用定时检查，应用重新开启保护与下一次检查之间仍可能截图失败。
异常退出不保证恢复，可重新启动目标应用恢复其自身配置。
