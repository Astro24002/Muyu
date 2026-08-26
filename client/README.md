# Muyu Android Client

Flutter 客户端只负责 Android。浏览器功能由仓库根目录的 `web/` TypeScript
应用提供。

## 检查

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## 构建

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

模拟器使用 `10.0.2.2` 访问宿主机 API；真机请替换为局域网 API 地址。Android
登录使用短信验证码，设备审批和扫码授权由服务端 API 完成。
