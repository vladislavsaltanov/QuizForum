# 04 — Финальная проверка среза

`bin/rails test`, `bin/rubocop`, `bin/brakeman --quiet --no-pager --exit-on-warn`,
скилл `security-review` по диффу ветки (допуск: находки ниже confidence 8/10 гасятся).
Затем `release-branch`: решение merge/PR.

Verify: полный `bin/ci`
