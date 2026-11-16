截图保护助手 / Capture Access v0.1

源码项目目录
src/App.cs            中文 WinForms 主界面与进程架构选择
src/helper.cpp        校验目标窗口并调用线程钩子的原生辅助程序
src/hook.cpp          在目标窗口线程中修改并验证截图保护标志
src/protocol.h        x86/x64 共用的 IPC 协议
src/demo.cpp          带截图保护的测试窗口
src/app.manifest      Windows 兼容性与 DPI 配置
build.ps1             构建脚本
 tests/integration.ps1 核心功能集成测试
TEST-REPORT.txt       既有验证结果和兼容性范围

构建环境
Windows + Visual Studio 2022 C++ Build Tools（x86/x64 编译工具和 Windows SDK）。
主界面使用系统自带 .NET Framework C# 编译器；原生组件静态链接 C/C++ 运行库。

构建
在本项目目录的 PowerShell 中执行：
  .\build.ps1
默认输出目录：dist
启动程序：dist\CaptureAccess.exe
自定义输出目录：.\build.ps1 -OutDir D:\path\to\output

使用
打开主程序，刷新窗口列表，选择目标窗口，点击“解除选中窗口”。
“持续解除”每秒检查已选择的窗口。“恢复原设置”恢复本次记录的全部窗口，正常退出时也会尝试恢复。
目标应用以管理员身份运行时，工具可能也需要以管理员身份启动。
窗口重建、目标应用重启或出现新窗口后，需要重新刷新并选择。

手动测试
主界面的“打开测试窗口”按钮可启动自带演示应用。
也可使用任意普通桌面应用中的 SetWindowDisplayAffinity 保护窗口进行测试。
核心集成测试（会启动并关闭项目自己的演示窗口）：
  .\tests\integration.ps1
集成测试默认要求 64 位 Windows，测试 x64 和 x86 两种目标进程。

兼容性
实现面向 Windows 10 x86/x64 与 Windows 11 x64，不支持 ARM64。
Windows 11 已验证核心功能；用户已反馈手动测试可用。Windows 10 实机尚未验证。
仅处理 SetWindowDisplayAffinity 的窗口保护，不保证解除 DRM 视频、驱动级保护或受保护进程限制。
持续解除采用定时检查，应用重新开启保护与下一次检查之间仍可能截图失败。
异常退出不保证恢复，可重新启动目标应用恢复其自身配置。