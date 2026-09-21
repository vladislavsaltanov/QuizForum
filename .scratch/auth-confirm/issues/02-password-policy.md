# 02 — Политика пароля 12+

`validates :password, length: { minimum: 12 }, allow_nil: true` в `User`
(allow_nil чтобы апдейт профиля без смены пароля не ломался).
Обновить фикстуры/тесты (пароль `password` = 8 символов станет невалидным —
заменить на 12+ во всех тестах и сидах). Тексты форм без изменений логики.

Verify: `bin/rails test test/models/user_test.rb`
