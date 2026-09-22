# 02 — Выдача/отзыв trustee автором на странице вопроса

Blocked by: 01

Только автор и админ: форма на `questions/show` (авторский блок) — грант по email (`User.find_by(email)` normalized, ошибки: «не найден», «уже trustee», «автору не нужен грант»). Список trustee с кнопкой отзыва (`destroy`). Trustee не видит блок управления, не может грантить/отзывать, не может `destroy` вопрос (destroy — только author/admin, отдельный предикат).

Маршруты: nested `resources :trustees, only: %i[create destroy]` под `questions`. Контроллер `QuestionTrusteesController` (или `TrusteesController`): `create`/`destroy` с `head(:forbidden)` для неавторов.

Тесты: автор грантит/отзывает; trustee не может грантить (403); отозванный trustee снова слепой до дедлайна.

Verify: `bin/rails test test/controllers/questions_flow_test.rb && bin/rubocop app/controllers app/models && bin/brakeman -q`
