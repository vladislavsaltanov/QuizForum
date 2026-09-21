# Security review — feat/auth-confirmation vs main

Метод: bigpowers `security-review`, фазы scope → context → assessment → FP-filter.
Brakeman: 0 warnings. Ручной разбор ниже, находки < 8/10 отсеяны.

## Проверено

- `ConfirmationsController#accept` (GET со сменой состояния): токен — signed,
  high-entropy, single-purpose (purpose включает класс+назначение+expiry),
  payload привязан к email (смена почты инвалидирует старые ссылки), expiry 3 дня.
  CSRF не применим как атака: подтверждение чужой почты в браузере жертвы
  атакующему ничего не даёт. OK.
- Разделение назначений: `password_reset` vs `email_confirmation` — разные
  purpose, кросс-использование невозможно. OK.
- Google: требуется `uid` + `info.email` + `email_verified == true`;
  привязка по email только после verified; отклонённые — на sign in без утечек.
  POST-only callback + rails_csrf_protection + rate_limit сохранены. OK.
- `ConfirmationsController#create`: нейтральный редирект в обоих случаях,
  письмо только неподтверждённым. OK (не раскрывает наличие почты).
- Пароль: серверная валидация min 12 + `allow_nil` (апдейт профиля не ломается);
  клиентский `minlength` — только хинт. OK.
- Фиксация сессии: сессия создаётся только после accept / verified OAuth /
  confirmed login; регистрация больше не логинит. OK.
- `after_authentication_url` — только same-origin из сессии. OK (pre-existing).

## Follow-ups (не блокеры)

1. Смена почты в профиле не сбрасывает `email_confirmed_at` — аккаунт остаётся
   «подтверждённым» под новый адрес. Предложение: сбрасывать флаг при смене
   email и слать новое письмо. Отдельный тикет.
2. `SessionsController#create` редиректит неподтверждённых на `new_confirmation_path`,
   а неверные креды — на `new_session_path`: различимый редирект раскрывает факт
   свежей регистрации. Риск низкий (только unconfirmed-окно), выравнивать —
   только если понадобится строже.

Вердикт: HIGH-находок нет, ветка к merge готова после решения по релизу.
