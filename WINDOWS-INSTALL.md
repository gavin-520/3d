# Windows 真机安装流程

这台电脑已经通过 USB 识别到 iPhone。由于 iOS 应用必须用 Apple 的 Xcode 工具链编译，Windows 本机不能直接产出 iPhone 可安装包；仓库附带的 GitHub Actions 工作流会在 GitHub 的 macOS runner 上编译未签名 IPA，再由 Windows 上的 Sideloadly 使用你的 Apple ID 签名并安装到已连接的 iPhone。整个过程中不要把 Apple ID 密码或双重认证验证码发给他人。

## 1. 在 GitHub 上运行云端构建

1. 将此文件夹解压到 Windows 上一个容易找到的位置。
2. 在 PowerShell 中进入解压后的 `LotteryLedger` 文件夹，然后运行：

   ```powershell
   git init
   git add .
   git commit -m "Add LotteryLedger iOS app"
   ```

3. 在 GitHub 创建一个空仓库，然后按 GitHub 页面给出的命令添加 `origin` 并推送当前分支。
4. 打开仓库的 **Actions** 页面，选择 **Build iOS IPA**，按 **Run workflow**。
5. 等任务成功后，在该次运行页面的 **Artifacts** 区下载 `LotteryLedger-unsigned-ipa` 并解压，得到 `LotteryLedger-unsigned.ipa`。

工作流只在 GitHub 上构建并保存 7 天，不会发布到 App Store，也不会上传投注数据。

## 2. 在 Windows 上签名并安装

1. 从 [Sideloadly 官方网站](https://sideloadly.io/)下载并安装 Sideloadly。
2. 保持 iPhone 通过 USB 连接；在手机上解锁并确认“信任此电脑”。
3. 打开 Sideloadly，选择检测到的设备和下载的 IPA，在 Apple ID 输入框中输入自己的 Apple ID，然后开始侧载。若 Apple 要求双重认证，只在 Sideloadly 或 Apple 的验证窗口中输入验证码。
4. 安装完成后，如果 iPhone 提示开发者未受信任，前往 **设置 → 通用 → VPN 与设备管理**，信任对应的开发者证书，再打开应用。

免费 Apple ID 的个人签名通常约 7 天后过期，需要重新签名安装；付费 Apple Developer Program 可使用更长效的开发签名。iPhone 需要运行 iOS 17 或更高版本。

## 故障排查

- **GitHub Actions 构建失败**：打开失败任务，复制首条 Xcode 错误信息；不要发 Apple ID 凭据。
- **Sideloadly 看不到设备**：解锁 iPhone，重新连接 USB 并确认信任提示；Windows 需要 Apple Mobile Device 驱动。
- **应用无法打开**：确认 iOS 版本至少为 17，并在 VPN 与设备管理中信任签名证书。
