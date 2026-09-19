# PSYCHO

FastAPI backend: психологи, расписание и звонки, ИИ-чаты, планы психолога и биллинг.

Пользовательского фронтенда и автоматического создания демо-аккаунтов нет.
Документация API: **http://127.0.0.1:8000/docs**; контракт: `/openapi.json`.
Корневой `/` возвращает 404; health: `/api/v1/health`.

Единый `TEST_MODE=true` включает mock ИИ и оплаты. Реальные деньги не списываются; почта не отправляется; Agora возвращает тестовый токен без видеосвязи.

Пользователей создавайте самостоятельно через API. Готовых аккаунтов с общим паролем нет.

Для уже подготовленного окружения, из корня проекта:

```powershell
docker start psycho01-local-db
python backend/scripts/local.py migrate
python backend/scripts/local.py serve
```

Проверки: `python backend/scripts/local.py test` (нужны `backend/requirements-dev.txt`).
Runner создаёт новую БД `psycho01_test_<случайный суффикс>` и удаляет её после прогона,
в том числе при провале тестов. Требуется локальный PostgreSQL и право CREATEDB.
Рабочая БД не очищается; внешние секреты не передаются тестам.
Прямой запуск pytest без изолирующего runner заблокирован.

На сервере/отдельном стенде из `backend`, в окружении с тестовыми зависимостями:

```shell
python scripts/run_tests.py --env-file .env
```

Runner читает из файла только `DB_*`. Секреты и `.env` не публикуются в Git.
Для локальной настройки скопируйте `backend/.env.example` в `backend/.env.local`,
укажите свою БД и два независимых случайных секрета `JWT_SECRET` / `REG_CODE_SECRET`.

Сервер разворачивает ветку `feature/backend`. Серверный `backend/deploy.sh` выполняет
`git pull --ff-only`, устанавливает `requirements.txt`, применяет `alembic upgrade head`
и перезапускает `psycho-backend`. Перед деплоем нужна резервная копия БД; после —
проверки API и фоновых задач. Реальные платежи дополнительно закрыты флагом
`BILLING_LIVE_ENABLED=false` до настройки провайдеров и проверки денежных операций.

Исходный `backend/.env` не используется локальным runner: он выбирает `backend/.env.local`.
