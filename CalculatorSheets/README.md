# 计算器 / Google Sheets 隐藏入口

自用 iOS 16 App。正常启动是可用计算器；依次点击 `1`、`×`、`1`、`=` 后进入 Google Sheets。

## 隐私行为

- Google 登录 Cookie 保存在本 App 的 `WKWebsiteDataStore.default()`，与 Safari 隔离。
- App 进入后台、锁屏或失去活动状态时立即回到计算器。
- 后台快照会在状态切换后显示计算器，不展示表格页面。
- 表格顶部锁形按钮可以立即返回计算器。

注意：Google 可能随时调整对嵌入式网页登录的限制。如果登录页提示浏览器不安全，完整 Google Sheets 网页和“绝不经过 Safari”这两个要求无法同时保证，需要改用系统浏览器完成首次授权。

## 构建 IPA

推荐把 `CalculatorSheets` 单独推送到 GitHub，然后在 Actions 中手动运行 `Build TrollStore IPA`。下载产物并解压，得到 `Calculator.ipa`，用 TrollStore 导入。

也可以在 macOS 上安装 XcodeGen 后运行：

```sh
xcodegen generate
xcodebuild -project Calculator.xcodeproj -scheme Calculator -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir Payload
cp -R build/Build/Products/Release-iphoneos/Calculator.app Payload/
zip -qry Calculator.ipa Payload
```

## 验收

1. 普通四则运算可用。
2. 只有连续输入 `1 × 1 =` 才打开 Google Sheets。
3. Google 账号登录后，杀掉并重开 App 仍保留网页登录状态。
4. 从表格页切到后台，再回来时只显示计算器。
5. 多任务切换器中不出现表格内容。

