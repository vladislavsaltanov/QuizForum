# 01 — Хранилище trustee + гейт author-or-trustee-or-admin

Миграция `question_trustees`: `question_id`, `user_id`, unique-индекс `[question_id, user_id]`, FK на обе таблицы. Модель `QuestionTrustee`: валидации уникальности пары + запрет гранта автору (`validate: author_cannot_be_trustee`). `Question has_many :trustees, through: :question_trustees`; `User` — зеркально. Предикат `Question#trustee?(user)`.

Гейт: `privileged?` → `author == user || trustee?(user) || admin?`; `@is_author` в `show` — тот же предикат (имя переменной не менять, веток в видах ноль). Каскад автоматом: `visible_attempts`, `respondent_names`, `visible_comments`, `stats`, `edit/update/destroy`, `CommentsController#approve` (вынести общий предикат в `Question#privileged?(user)` и переиспользовать в обоих контроллерах).

Тесты: trustee видит тексты попыток + reference до дедлайна; чужой не видит; author не может быть своим trustee (валидация); дабл-грант отклоняется unique-индексом.

Verify: `bin/rails test test/controllers/questions_flow_test.rb test/models/question_test.rb`
