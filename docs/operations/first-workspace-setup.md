# 首个共享空间操作说明

本文适用于当前首版 Android 客户端与 Web 客户端。Android 使用带有生产 API
入口的 APK，Web 使用公开 HTTPS 站点；浏览器不能绕过 Android 设备授权，也不能
直接输入账号登录。

## 操作顺序

1. 使用带 `API_BASE_URL=https://muyu.bkverse.space` 的 Android APK 登录手机号。
2. 已有 ACTIVE membership 的账户直接进入任务页；没有 membership 的账户看到
   `创建共享空间`。
3. 点击一次 `创建共享空间` 并等待任务页出现。网络失败使用 `重试`，不要反复
   安装、清数据或手工插入数据库记录。
4. 在任务页点击扫描入口，扫描 `https://muyu.bkverse.space` 的 Web QR code，并
   在 Android 上明确批准。
5. 浏览器获得短期 Web session 后加载 Workspace；若仍显示
   `workspace membership required`，停止扫码并先在 Android 完成上一步创建。
6. 添加第二位成员仍使用现有邀请、接受和对方设备批准协议；本文不把短信验证或
   用户手机号当作自动成员授权。

## 运行边界

- Android APK 的构建产物位于
  `client/build/app/outputs/flutter-apk/app-debug.apk`；构建时必须显式使用上面的
  `API_BASE_URL`。
- Web 只通过 `https://muyu.bkverse.space` 访问；Web QR 登录由已认证的 Android
  设备批准，Web 浏览器不持有 Android 私钥或长期移动会话令牌。
- 首个 Workspace 创建成功后，客户端从云端读取同一个 Workspace；重复点击由客户
  端状态控制，服务端仍负责成员和 Workspace 约束。
- 本文不提供数据库、服务端 shell、生产令牌、短信验证码或其他绕过成员校验的操作。

