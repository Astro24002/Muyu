# 首个共享空间操作说明

本文适用于当前首版 Android 客户端与 Web 客户端。Android 使用带有生产 API
入口的 APK，Web 使用公开 HTTPS 站点；浏览器不能绕过 Android 设备授权，也不能
直接输入账号登录。

## 操作顺序

1. 使用带 `API_BASE_URL=https://muyu.bkverse.space` 的 Android APK 登录手机号。
2. 没有 Workspace 的账号会看到 `绑定共同使用人`，填写另一位用户的手机号。
   11 位中国大陆号码会在服务端统一保存为 `+86` E.164 格式。
3. 绑定成功后显示 `等待对方加入`。另一位用户使用自己的手机号完成短信验证，
   在 `收到共享空间邀请` 页面点击 `接受邀请`；双方随后进入同一个两人 Workspace。
4. 每个账号的第一台 Android 设备自动为“已验证”，可以读写任务。第二台及之后
   的设备先显示“未验证”，可以刷新和查看数据，但写入会被服务端拒绝。
5. 另一位成员的已验证 Android 设备在设备授权页面批准后，未验证设备才获得写权限。
6. 在任务页点击扫描入口，扫描 `https://muyu.bkverse.space` 的 Web QR code，并
   在 Android 上明确批准。浏览器获得最长 18 小时的临时 Web session。
7. 若页面显示 `workspace membership required`，说明当前手机号还没有加入该两人
   Workspace；先完成邀请接受，再重新生成二维码。网络失败使用页面的重试操作，
   不要手工插入数据库记录。

## 运行边界

- Android APK 的构建产物位于
  `client/build/app/outputs/flutter-apk/app-debug.apk`；构建时必须显式使用上面的
  `API_BASE_URL`。
- Web 只通过 `https://muyu.bkverse.space` 访问；Web QR 登录由已认证的 Android
  设备批准，Web 浏览器不持有 Android 私钥或长期移动会话令牌。
- Workspace 绑定、邀请接受和设备授权均以云端事务为准；重复点击由请求幂等键和
  服务端约束保护。
- 本文不提供数据库、服务端 shell、生产令牌、短信验证码或其他绕过成员校验的操作。
