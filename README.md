# 彩票账本

这是一个原生 SwiftUI iOS 17 应用，用于记录福彩3D和排列3的投注、开奖和结算。

## 打开与运行

1. 在 macOS 上安装 Xcode 16 或更高版本。
2. 双击 LotteryLedger.xcodeproj 打开工程。
3. 在 Xcode 的 Signing & Capabilities 中选择自己的 Apple Developer Team。
4. 连接 iPhone，选择真机 Scheme LotteryLedger，执行 Build & Run。
5. 在“设置 → 开奖接口”中填写接口 URL 模板和 JSON 字段路径；没有接口时可在“开奖”页手动录入。

当前工作区运行在 Windows，不能在这里执行 Xcode 构建。准备安装到真机时，请先把 iPhone 通过 USB 连接到 Mac，并在手机上信任该 Mac；随后在 Xcode 选择开发团队和已连接的 iPhone，执行 Build & Run。到达这一步时需要连接手机，我会在安装前提醒。

工程最低部署版本是 iOS 17，数据使用 SwiftData 保存，图表使用 Swift Charts。投注金额按分存储，规则修改后历史投注仍使用保存的规则快照结算。

## 接口格式

默认字段路径为：

- data.period
- data.digits
- data.drawDate

URL 可以包含 {period} 占位符。请求参数和请求头使用 JSON 对象填写，例如 {"token":"demo"}。Authorization token 单独保存在 Keychain。

## 规则

图片中的和值、跨度、直选、组三、组六、独胆、双飞、定位和复式规则已经作为两个彩种的默认规则种子。规则设置页可修改名称、输入格式、匹配方式、本金和奖金。未写明的赔率小数按分四舍五入保存；历史记录不会随着规则编辑自动变化。

复式投注会根据选号集合展开基础组合数并校验最低金额，结算时按命中的基础组合、投注倍数和单位奖金计算。期号和三位号码都按字符串处理，前导零会保留。
