# Срез: Trustee (наблюдатель на один вопрос)

Решение (2026-09-22): Trustee обещан в CONTEXT/README, в коде ноль (`git log -S trustee` пуст, в `schema.rb` только `questions.author_id`). Причина отсутствия — spec-first глоссарий без тикета; админ (`privileged?` = author-or-admin) закрыл демо-нужду. Реализовать как join, не как флаг: доступ к одному вопросу, не глобальная роль.

## Scope

1. Хранилище: `question_trustees(question_id, user_id)` + unique-индекс, модель с валидацией (автор себе не trustee, дубли запрещены).
2. Гейт: `privileged?` и `@is_author` включают trustee (`question.trustee?(user)`); каскад на 4 места: `visible_attempts`, `respondent_names`, `visible_comments`, `stats` + `edit/update/destroy` + `CommentsController#approve`. Одна предикат-точка, без веток в видах.
3. Выдача/отзыв: только автор (и админ) грантит/отзывает на странице вопроса, минимальный UI (поле email/user + список с кнопкой отзыва). Trustee не может грантить дальше, не может удалять вопрос.
4. Проверка: `bin/rails test`, `bin/rubocop`, `bin/brakeman`.

## Не scope

Временные гранты с expiry, self-service заявки, нотификации trustee, аудит-лог, trustee для leaderboard/profile — добавить когда будет реальная нужда.

## Конфликт с bigpowers

bigpowers пишет память в `specs/`, репо — в `.scratch/` (AGENTS.md + `docs/agents/issue-tracker.md`). Источник правды здесь — `.scratch/`. GitHub-зеркало пропущено сознательно: bigpowers запрещает skills создавать GitHub issues.
