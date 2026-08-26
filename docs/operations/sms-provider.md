# SMS Provider Operations

Android account registration uses the `SmsProvider` abstraction. Development
and automated tests use `OTP_PROVIDER=fake`; production uses the Guoyangyun
SMS API purchased through the Aliyun marketplace with
`OTP_PROVIDER=production`.

Required production values are injected through the deployment secret store:

- `OTP_PROVIDER_URL=https://gyytz.market.alicloudapi.com/sms/smsSend`
- `OTP_PROVIDER_API_KEY` contains the provider AppCode;
- `SMS_SIGN_ID` contains the approved SMS sign identifier (`2e65b1bb3d054466b82f0c9d125465e2` in the supplied template);
- `SMS_TEMPLATE_ID` contains the approved verification template identifier
  (`908e94ccf08b4476ba6c876d13f084ad` in the supplied template).

The supplied template text is `验证码：**code**，**minute**分钟内有效，请勿泄漏于他人！`.

The API request uses `Authorization: APPCODE <AppCode>` and sends
`mobile`, `smsSignId`, `templateId`, and `param` as query parameters on a
POST request, matching the provider's Aliyun-market example. The service
keeps phones in E.164 form internally and converts mainland Chinese numbers
to the provider's 11-digit format only at this boundary. It sends the
generated six-digit code and the configured validity in minutes. It accepts a
delivery only when the provider response is JSON with `code` equal to the
string `0`.

Never put the AppCode in Flutter `--dart-define` values, source control, Web
assets, APKs, or logs. The server does not log the request body, recipient,
code, authorization header, or provider response body.

The API normalizes phone numbers to E.164, stores only a keyed OTP digest, and
never logs the six-digit code. Configure provider-side fraud controls in
addition to API controls. API defaults allow five requests per phone window,
twenty per IP window, five verification attempts, and a five-minute challenge;
review these limits with the provider and adjust through deployment settings.

Monitor delivery failure rate, provider latency, `429` responses, quota
exhaustion, and unusual per-phone/IP spikes. A provider outage or a non-zero
business response must fail closed with a generic delivery error; operators
must not reveal whether a phone is registered.
