class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const webOrigin = String.fromEnvironment(
    'WEB_ORIGIN',
    defaultValue: 'https://muyu.example',
  );
}
