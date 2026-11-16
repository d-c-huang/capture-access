# 版本发布

两个平台使用仓库根目录 `VERSION` 中的同一个三段版本号，例如 `0.8.0`。

1. 同步更新 `VERSION`、Mac `Info.plist` 和 Windows 更新组件中的版本号。
2. 更新 `docs/RELEASE-NOTES.md`，执行 `python3 scripts/check-version.py`。
3. 执行 `python3 scripts/test-public-files.py` 和 `python3 scripts/check-public-files.py`，并人工检查每张新增说明图片；将确定要公开的文件加入暂存区后，再执行 `python3 scripts/check-public-files.py --staged` 检查实际将提交的内容。
4. 提交到 `codex/` 分支，等待 Windows 与 macOS 构建和测试通过。
5. 合并或快进到 `main`。发布工作流再次验证两个平台，成功后创建尚不存在的 `v<版本号>` 正式 Release。

已有同名 Release 不会被覆盖；修复已发布版本时需要提高版本号。未通过检查的构建不会发布。

## 固定下载文件名

更新组件只接受此仓库中与返回版本对应的以下资源：

- `CaptureAccess-Windows.zip`
- `CaptureAccess-macOS-universal.zip`

工作流一并生成 `SHA256SUMS.txt`。正式更新检测使用 GitHub 的 `/releases/latest` 接口；草稿、预发布、无效版本或不匹配的平台资源不会被当成可下载更新。

公开下载包由 GitHub Actions 构建。Mac 发布构建固定使用 `SIGN_IDENTITY=-`，不会上传开发机器的个人签名身份。

## 公开文件范围

- 本机 `dist`、`.build`、`obj`、真实截图、诊断日志、私人测试报告和签名文件在忽略范围内。
- README 使用 `docs/images/` 中的 SVG 示意图，须明确标注虚构数据，不嵌入真实截图、外链图片或脚本。
- 公开文件检查会阻止常见凭据、个人绝对路径及不应提交的二进制文件，但不能替代人工判断文字是否包含机密。
- 不从开发机器直接上传整个工作目录或发布文件夹；发布工作流只上传列明的压缩包。
