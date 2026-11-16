Capture Access for macOS · v0.2.0
=================================

功能
- 使用 macOS 自带窗口选择器选择单个窗口并截图。
- 预览、再次截图、保存 PNG、复制图片。
- Retina 像素尺寸；超大窗口等比缩小，限制单张图像的内存开销。
- 处理取消选择、截图超时、系统授权和窗口失效。
- 内置独立演示应用，可切换旧式 NSWindow.sharingType 保护。
- 不录制音频，不自动保存图片，不上传窗口内容。

系统要求
macOS 14 Sonoma 或更新版本，Intel x86_64 / Apple Silicon arm64。
构建需要 Xcode 15+ 或带 macOS 14+ SDK 的 Command Line Tools，以及 Swift 5.9+。
依赖均为系统框架，不依赖第三方 Swift 包。

构建和运行
在项目根目录执行：
  bash macos/build.sh
脚本默认构建当前 Mac 架构，在 macos/dist 下生成：
  CaptureAccess.app
  CaptureAccess-macOS-<架构>.zip
演示应用内置于 CaptureAccess.app/Contents/Resources/CaptureAccessDemo.app。
双击 CaptureAccess.app 启动，或执行：
  open macos/dist/CaptureAccess.app

通用二进制
  bash macos/build.sh --arch universal
也支持 --arch arm64 或 --arch x86_64。

签名
默认使用本地 ad-hoc 签名，无需开发者账户；这不等于 Apple 公证。
正式分发时需使用自己的 Developer ID 签名并另行公证。
例如提供现有签名身份：
  SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash macos/build.sh --arch universal
签名身份属于本机钥匙串配置，项目不包含证书或凭据。

使用
1. 启动完整的 .app 包，点击“选择窗口并截图”。
2. 在系统选择器中选择目标窗口并确认。
3. 若系统要求屏幕录制权限，按提示授权；也可点击界面中的授权或系统设置按钮。
   某些系统版本需要授权后完全退出并重新启动应用。
4. 在预览区查看实际图像，再保存 PNG 或复制图片。
5. “再次截图”重新获取同一已选择窗口；窗口关闭或选择失效后，需要重新选择。
6. “清除预览与选择”释放选择并清除本次预览，不清空此前主动复制到剪贴板的图片。

快捷键
Command+Shift+1  选择窗口并截图
Command+Shift+2  再次截图
Command+S        保存 PNG
Command+Shift+C  复制图片

与 Windows 版的区别
此实现采用用户确认的“直接截图”方案。
它不会取消其他进程的窗口保护，也不承诺系统快捷键或其他截图软件获得相同结果。
旧的 NSWindow.sharingType = .none 在较新 macOS 中可能不影响 ScreenCaptureKit。
截图是否可用须以实际预览为准；DRM 视频或应用主动隐藏的内容仍可能不可见。
截图 API 返回图像不表示图像一定含有目标内容，保存前请查看预览。
旧版本 macOS 上设置保护的窗口也可能无法选取，或截图为空白。
应用启动时不主动读取桌面；仅在用户选窗后请求单帧截图。
系统选择器的授权与系统级屏幕录制授权并不在所有 macOS 版本中等价。
若单帧截图 API 返回拒绝访问，请按系统提示授权，不应将选择器确认视为已经获得全部权限。

源码
Package.swift                         Swift Package Manager 项目
Sources/CaptureAccessMac/             SwiftUI 主应用、系统选择器与截图逻辑
Sources/CaptureCore/                  尺寸与 PNG 编码
Sources/CaptureAccessDemo/            独立的保护测试窗口
Resources/                           应用及演示应用的 Info.plist
Tests/CaptureCoreTests/               尺寸边界、Retina 尺寸、PNG 解码与像素测试
Tests/MANUAL-TESTS.txt                系统权限与真实截图手动验收步骤
build.sh                             构建、签名和 ZIP 打包脚本

测试
  cd macos
  swift test
测试只检查图像处理与尺寸行为，不会开启屏幕录制。
界面、授权、目标窗口和旧式保护行为需要按 Tests/MANUAL-TESTS.txt 在 Mac 上实测。
不要直接用 swift run 代替正式 .app 验收：无 Bundle 时，权限身份、演示路径和启动行为可能不同。

当前验证状态
本次开发主机是 Windows，没有 macOS SDK。
macOS 原生编译、单元测试、权限流程和截图效果均尚未执行。
已执行的静态检查记录在 TEST-REPORT.txt。

GitHub macOS 构建
仓库根目录的 .github/workflows/build-macos.yml 支持手动触发。
在 GitHub Actions 中选择 Build macOS app，选择 universal / arm64 / x86_64。
它在 macos-15 主机运行 swift test 和本目录的 build.sh，再上传应用 ZIP 与校验值。
整个原生编译和打包过程在 Mac 上执行；当前尚未触发构建。

接口参考（官方）
https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker
https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none
https://www.electronjs.org/docs/latest/api/browser-window#winsetcontentprotectionenable-macos-windows
