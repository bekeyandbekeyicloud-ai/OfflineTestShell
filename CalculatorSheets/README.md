# 计算器 / 私有表格编辑器

自用 iOS 16 App。正常启动是可用计算器；依次点击 `1`、`×`、`1`、`=` 后进入固定 Google 表格的原生编辑器。

## 隐私行为

- App 不接收或保存 Google 账号、密码、Cookie 或 OAuth 令牌。
- App 通过受随机密钥保护的 Apps Script，只访问预先指定的一个表格。
- App 进入后台、锁屏或失去活动状态时立即回到计算器。
- 在多任务界面手动上滑结束 App 后，已加载的单元格数据随进程内存销毁。
- 新版本启动时会清除旧版本可能留下的网页 Cookie、缓存和网站数据。
- 后台快照会在状态切换后显示计算器，不展示表格页面。
- 表格顶部锁形按钮可以立即返回计算器。

原生编辑器支持三个工作表标签、读取和修改单元格、行列分页及手动刷新。它不提供 Google Sheets 的图表、批注、格式设计等高级能力。

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
3. Sheet1、Sheet2、Sheet3 均可切换、读取和编辑。
4. 短暂切到后台再回来时只显示计算器；重新解锁后内存中的表格页仍保留。
5. 从多任务界面上滑结束 App 后，重新打开不会恢复上次加载的单元格缓存。
5. 多任务切换器中不出现表格内容。
