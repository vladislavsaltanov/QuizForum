# Срез: регистрация с подтверждением почты + Google OAuth

Решения (2026-09-21): вход через Google = OAuth2 веб (omniauth-google-oauth2, уже в Gemfile);
email-gate строгий (вход блокируется до подтверждения, есть повторная отправка);
пароль минимум 12 символов без правил сложности; ветка `feat/auth-confirmation` без worktree.

## Scope

1. Подтверждение почты: `users.email_confirmed_at`, токен через `generates_token_for`,
   `RegistrationMailer` + `ConfirmationsController` (new/create/accept), строгий гейт
   в `SessionsController#create` (алерт + редирект на повторную отправку).
   Google-аккаунты с `verified_email=true` помечаются подтверждёнными сразу.
2. Пароль: `validates :password, length: { minimum: 12 }`, тексты ошибок в формах.
3. Google-хардининг без over-engineering: проверка `verified_email`, привязка
   существующего аккаунта по email только при verified, отклонение неверифицированных
   (редирект с алертом), существующие rate_limit + POST-only + CSRF-protection не ломать.
4. Проверка: `bin/rails test`, `bin/rubocop`, `bin/brakeman`, скилл `security-review`.

## Не scope

Play Games / Android ID-token, 2FA, капча, проверка пароля по блеклисту,
истечение сессий по таймауту — добавить когда будет реальная нужда.
