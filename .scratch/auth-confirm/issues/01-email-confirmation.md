# 01 — Подтверждение почты со строгим гейтом

Добавить `users.email_confirmed_at` (миграция) + `generates_token_for :email_confirmation`.
`RegistrationMailer.confirmation(user)` с ссылкой на подтверждение.
`ConfirmationsController`: `new` (форма повторной отправки), `create` (всегда редирект
с нейтральным нотисом — не раскрывать наличие почты), `accept` по токену
(`find_by_email_confirmation_token!`, rescue InvalidSignature → алерт).
`RegistrationsController#create`: не логинить сразу — слать письмо, редирект на
страницу «проверьте почту». `SessionsController#create`: если `!confirmed?` —
редирект на `new_confirmation_path` с алертом.
Google: при `extra.raw_info.email_verified` ставить `email_confirmed_at`.

Verify: `bin/rails test test/controllers/registrations_controller_test.rb test/controllers/sessions_controller_test.rb`
