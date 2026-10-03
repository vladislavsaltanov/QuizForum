# Deploy за одну команду

Сервер с Docker + Compose plugin, открыты порты 80 (и 443 для HTTPS).
Локально ничего ставить не надо: Postgres, Redis и AI-sidecar едут
контейнерами.

## Старт

```bash
git clone <repo> quizforum && cd quizforum
cp .env.deploy.example .env.deploy
nano .env.deploy   # минимум: POSTGRES_PASSWORD (+ дубль),
                   # RAILS_MASTER_KEY, SMTP/Gmail для писем
docker compose --env-file .env.deploy up -d --build
```

Что заполнить:

| Ключ | Зачем | Где взять |
| --- | --- | --- |
| `POSTGRES_PASSWORD` = `QUIZ_FORUM_DATABASE_PASSWORD` | пароль Postgres | сгенерировать (`openssl rand -hex 16`) |
| `RAILS_MASTER_KEY` | расшифровка `config/credentials.yml.enc` | локальный `config/master.key` |
| `SMTP_LOGIN` + `GMAIL_APP_PASSWORD` | письма регистрации/сброса | Google App Password |
| `APP_HOST` | хост в письмах, pin `config.hosts` | IP или домен; пусто = открыто |
| `GOOGLE_CLIENT_ID` / `SECRET` | вход через Google | Google Cloud Console; пусто = только пароль |

Проверка: `curl -sf http://<server>/up` → `Max age ...`. Миграции
применяет entrypoint (`db:prepare`, создаёт `*_cache/queue/cable` базы).

## Первый запуск и sidecar

Модерация (Laya) и жюри (OpenJev 0.8B) живут в сервисе `sidecar`
на CPU. Первый старт качает ~4 ГБ весов в volume `weights` — до
15 минут. Готовность:

```bash
docker compose ps                           # sidecar healthy = модели загружены
docker compose exec sidecar curl -sf http://127.0.0.1:8000/up
```

Web sidecar не ждёт: пока он холодный, публикации и оценки
откладываются (`try_later` / `pending`), остальное работает.
Демо-данные: `docker compose exec web bin/rails db:seed`.

Логи: `docker compose logs -f web sidecar`.

## HTTPS через домен

DNS домена → IP сервера, в `.env.deploy`:

```env
TLS_DOMAIN=quiz.example.com
APP_HOST=quiz.example.com
FORCE_SSL=true
```

Перезапуск: `docker compose --env-file .env.deploy up -d`.
Thruster сам выпустит Let's Encrypt и редиректит HTTP→HTTPS
(сертификаты в volume `storage`). Без `TLS_DOMAIN` — чистый HTTP
на :80, `FORCE_SSL` должен быть `false`.

## Обновление и бэкап

```bash
git pull
docker compose --env-file .env.deploy up -d --build
```

Данные: volumes `db_data` (Postgres), `storage` (файлы + TLS),
`weights` (модели, перекачивать не надо), `redis_data`.
Бэкап базы: `docker compose exec db pg_dump -U quiz_forum
quiz_forum_production > backup.sql`.
