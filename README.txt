Capture Access
==============

项目结构
windows/  Windows 10 / 11 版本：选择窗口后取消 SetWindowDisplayAffinity 截图保护。
macos/    macOS 14+ 原生版本：使用系统窗口选择器，直接截图、预览、保存 PNG、复制图片。

Windows
在项目根目录的 PowerShell 中执行：
  .\windows\build.ps1
运行：windows\dist\CaptureAccess.exe
现有可运行程序、原生 x86/x64 组件、演示程序和构建中间文件均已移到 windows/。
详细说明：windows/README.txt
既有测试结果：windows/TEST-REPORT.txt

macOS
需要 Mac（macOS 14 或更新版本）以及 Xcode 15+ / 相应 Command Line Tools。
在项目根目录的终端中执行：
  bash macos/build.sh
运行：macos/dist/CaptureAccess.app
同时构建 Intel 和 Apple Silicon 通用应用：
  bash macos/build.sh --arch universal
运行单元测试：
  cd macos
  swift test
详细说明：macos/README.txt
手动验收：macos/Tests/MANUAL-TESTS.txt

远程打包（在 Mac 上执行，不在 Windows 上打包）
项目已提供 .github/workflows/build-macos.yml。
将项目放入自己的 GitHub 仓库后，在 Actions 中选择 Build macOS app，手动执行 Run workflow。
默认生成同时支持 Apple Silicon 与 Intel 的 universal 应用。
测试、编译、签名和 ZIP 打包均运行在 GitHub 的 macos-15 主机；main 分支中的 macOS 代码更新也会自动触发。
成功后从构建的 Artifacts 下载 ZIP；压缩包内是带应用包结构的 CaptureAccess.app。
默认本地 ad-hoc 签名，不等于 Developer ID 签名或 Apple 公证。
源码仓库：https://github.com/d-c-huang/capture-access
已成功构建：https://github.com/d-c-huang/capture-access/actions/runs/43838699586

两平台的实现差异
Windows 版修改所选窗口的保护标志，随后可使用其他截图工具捕获。
macOS 版按用户确认的方案，由本工具获取所选窗口的截图。它不提供跨进程解除 sharingType 的功能。
macOS 的系统窗口选择器和单帧截图由 ScreenCaptureKit 提供；仍须遵循系统权限提示。
旧式窗口保护在较新 macOS 中可能不阻止 ScreenCaptureKit，因此可以尝试对这类窗口直接截图。
DRM、应用主动隐藏内容或其他保护机制仍可能产生空白图像，不保证所有目标都可捕获。

验证范围
Windows：既有核心集成测试通过，用户此前已手动确认测试可用。
macOS：在 GitHub 的 macOS 15.8.2 ARM64 主机上完成原生构建，4 项 XCTest 全部通过。
已生成 arm64 + x86_64 通用 .app，codesign 验证通过；本地 Windows 仅编辑源码和下载云端成品。
系统窗口选择器、真实目标窗口、授权流程和剪贴板仍需在 Mac 上手动验收。
