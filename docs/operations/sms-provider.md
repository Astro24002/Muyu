# SMS Provider Operations

Android account registration uses the `SmsProvider` abstraction. Development
and automated tests use `OTP_PROVIDER=fake`; production must use
`OTP_PROVIDER=production` with provider credentials injected at runtime.

Required production values are `SMS_PROVIDER_ACCOUNT_SID`,
`SMS_PROVIDER_AUTH_TOKEN`, and `SMS_PROVIDER_FROM_NUMBER`. Keep these values
in the deployment secret store. Never pass them as Flutter `--dart-define`
values or commit them to an environment file.

The API normalizes phone numbers to E.164, stores only a keyed OTP digest, and
never logs the six-digit code. Configure provider-side fraud controls in
addition to API controls. API defaults allow five requests per phone window,
twenty per IP window, five verification attempts, and a five-minute challenge;
review these limits with the provider and adjust through deployment settings.

Monitor delivery failure rate, provider latency, `429` responses, and unusual
per-phone/IP spikes. A provider outage should fail closed with a generic
delivery error; operators must not reveal whether a phone is registered.
