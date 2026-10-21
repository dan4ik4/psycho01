# Oakle backend

FastAPI + PostgreSQL. Актуальный контракт для приложения: [frontend-contract-2026-10-21.md](docs/frontend-contract-2026-10-21.md). OpenAPI доступен на `/openapi.json`, Swagger — `/docs`.

## Обновление

Установить `requirements.txt`, сделать резервную копию PostgreSQL, выполнить `alembic upgrade head`, перезапустить приложение. Миграция `d17b40a269ce` сбрасывает старые ставки в RUB; психологи должны указать ставки в USD заново. Исторические платежи не конвертируются. Для отката сначала восстановить прежние ставки из резервной копии: downgrade намеренно не выдумывает суммы для `null`.

Добавить в окружение:

```dotenv
BILLING_CURRENCY=USD
SUBSCRIPTION_PRICE_MINOR=900
SUBSCRIPTION_DAYS=30
PASSWORD_RESET_URL=oakle://reset-password
PUBLIC_BASE_URL=https://api.oakle.app
AVATAR_STORAGE_DIR=/var/lib/psycho01/avatars
```

Каталог фотографий должен быть постоянным, доступным пользователю сервиса для записи и включённым в резервное копирование. В reverse proxy разрешить multipart до 6 MiB (сам файл ограничен 5 MiB). Для локального запуска указать локальный `PUBLIC_BASE_URL`.

Флаги `EMAIL_TEST_MODE`, `AI_TEST_MODE`, `BILLING_TEST_MODE`, `AGORA_TEST_MODE` независимы. `TEST_MODE` задаёт только значения по умолчанию для отсутствующих флагов. Изменение валюты не включает реальные платежи. Для live-биллинга отдельно настроить USD-комиссии, Stripe и цену подписки в магазинах/RevenueCat.

## Проверки

```sh
pip install -r requirements-dev.txt
python scripts/run_tests.py --env-file /path/to/database.env
```

Runner читает только DB-параметры, создаёт и удаляет отдельную тестовую БД; почта, платежи, ИИ и звонки работают в тестовом режиме. Нужны PostgreSQL на loopback и право CREATEDB. Не запускать pytest напрямую против рабочей базы.
