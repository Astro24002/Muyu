# Muyu Client

Flutter Android/Web 客户端。

## 检查

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## 构建

```bash
flutter build web --dart-define=API_BASE_URL=http://localhost:8080
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

本地 Web 调试固定使用 `http://localhost:3000`，后端允许 localhost/127.0.0.1 的开发端口跨域访问。生产部署应由反向代理提供同源 API。
