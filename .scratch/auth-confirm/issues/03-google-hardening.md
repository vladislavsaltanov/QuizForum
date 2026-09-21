# 03 — Google OAuth хардининг

В `SessionsController#google_oauth2`: требовать `uid` + `info.email` из auth-хэша
(пустое → failure-редирект); требовать `extra.raw_info.email_verified` (ложь/отсутствие →
failure-редирект с алертом); привязку существующего юзера по email делать только
при verified; OAuth-юзерам ставить `email_confirmed_at`. Не добавлять новых гемов.
Сохранить rate_limit, POST-only callback, `omniauth-rails_csrf_protection`.

Verify: `bin/rails test test/controllers/sessions_controller_test.rb` + новые кейсы
(unverified email отклонён, привязка по verified email работает)
