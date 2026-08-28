# 设备与 Web 会话操作

本文记录首版账号、两人 Workspace、Android 设备和临时 Web 会话的实际运行
规则。服务端 PostgreSQL 是唯一事实源；Android 和 Web 都通过 FastAPI 读取和
提交变更。

## 账号与 Workspace

- 手机号是登录入口，数据库保存规范化后的 E.164 值。首个手机号登录后必须填写
  另一位共同使用人的手机号，不能创建只有一个成员的正式双人空间。
- 一个 Workspace 最多两个成员，成员是两个独立账号。邀请接受后，邀请手机号对应
  的账号加入 slot 2；已有其他 Workspace 的账号不会被静默换绑。
- 首次登录没有 Workspace 是正常的 `NEEDS_PARTNER` 状态，不是故障。已发出邀请
  等待接受是 `WAITING_FOR_PARTNER`，受邀账号看到的是 `INVITED`，两人加入后是
  `READY`。

## Android 设备

每个账号的第一台 Android 设备自动为“已验证”（数据库状态 `ACTIVE`），后续设备
先为“未验证”（数据库状态 `PENDING`）。未验证设备可以刷新移动会话、读取
Workspace、任务、评论和同步游标；创建、修改、状态流转、评论、延期、冲突解决和
设备审批等写入由服务端统一返回 `device_not_verified`。

另一位 Workspace 成员的已验证 Android 设备可以批准待验证设备。批准只改变设备
能力，不创建新账号，也不改变已有移动会话的设备 ID。服务端会在每个写请求再次
检查设备状态，客户端按钮禁用不是安全边界。

在 Android 的“我的”页面：

- 只列出 AndroidDevice，不显示 WebSession；设备状态显示为“已验证”“未验证”或
  “已撤销”。
- 当前设备永远没有撤销按钮。即使构造请求绕过客户端，服务端也返回稳定的
  `approval_not_allowed`。
- 可以撤销本账号的其他设备。撤销会立即使该设备的移动会话和待处理设备审批请求
  失效；设备记录保留用于审计。

## Web 登录与会话

Web 只能通过二维码登录。浏览器生成一次性 challenge，已验证 Android 设备扫描并
签名授权，服务端验证 challenge、签名、设备和 Workspace 后写入 HttpOnly Cookie。
浏览器不持有 Android 私钥，也不会创建 AndroidDevice。

WebSession 的最长生命周期是 18 小时。服务端只保存随机 Cookie 的 digest；Web
页面只展示来源、创建时间和过期时间，不展示 Cookie、签名或 digest。

- 已验证 Android 设备可以查看当前 Workspace 的有效 WebSession，并撤销单个或
  全部会话。
- 浏览器的会话页面可以读取当前浏览器会话并结束自己的会话；撤销其他浏览器会话
  仍必须从已验证 Android 设备发起。
- WebSession 不计入 Android 设备数量，不出现在 `/api/v1/devices`，也不会触发
  Android 设备审批或撤销记录。
- Android 设备撤销时，其发起的有效 WebSession 也会被撤销。后续请求返回 401，
  Web 页面回到二维码登录界面。

## 清理任务

每日清理命令只处理已过期或已撤销并超过保留窗口（默认 30 天）的 WebSession，
以及已消费、已过期的二维码 challenge：

```sh
docker compose --env-file deploy/.env -f deploy/docker-compose.yml \
  run --rm web-session-cleanup python -m app.web_login.cleanup --retention-days 30
```

命令可以重复执行，第二次不会删除新的记录，也不会影响 ACTIVE 会话。生产 Compose
包含同样命令的 `web-session-cleanup` 常驻服务，每 24 小时执行一次。

## 常见排查

- `workspace membership required`：当前账号还没有接受两人 Workspace 邀请，先在
  Android 完成绑定或接受邀请。
- `device_not_verified`：当前设备是第二台或之后的 Android 设备，等待另一位成员
  的已验证设备批准。
- `web_session_expired`：Web 会话过期、被撤销，或批准它的 Android 设备被撤销；
  重新打开页面并扫码即可。
