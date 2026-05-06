# PostgreSQL Production Stack for Prisma

Docker Compose стек: PostgreSQL 16 + PgBouncer + Backup + Prometheus.

Образ PgBouncer: `bitnamilegacy/pgbouncer:1.22.1-debian-12-r9` (тег закріплений; `bitnami/pgbouncer:latest` на Docker Hub часто недOSTUPний).

## Перед першим запуском (коротко)

- У репозиторії тільки шаблони без секретів: `docker/.env.example`, `docker/pgbouncer/userlist.txt` з `CHANGE_ME_*`.
- Після `cp .env.example .env` заповни **всі** `CHANGE_ME_*` у `docker/.env` і **скопіюй той самий пароль суперюзера** в `docker/pgbouncer/userlist.txt` для рядка `"pgadmin"` (або зміни ім’я скрізь однаково).
- У `docker/docker-compose.yml` за замовчуванням bind для прикладу: `91.239.232.91:6432:6432` — **заміни на свій публічний IP або VPN IP** перед продом; обов’язково обмеж 6432 firewall-ом.
- У Prisma-проєктах `VPN_HOST` = той хост, з якого додаток дійсно дістається до сервера (зараз у прикладах: `91.239.232.91`).
- Файл `docker/.env` на сервері не коміть; реальний `userlist.txt` на сервері теж тримай локально (у шаблоні репо — лише заглушки).

## Автоматичний install/deploy

### Швидкий install на сервер

```bash
cd /root/apps
git clone https://github.com/Makmillerme/postgressserver-prisma-postgres-stack-v2.git postgres-prisma-stack
cd postgres-prisma-stack/docker
cp .env.example .env
# заповни паролі в .env

chmod +x scripts/install.sh scripts/deploy.sh scripts/*.sh backup/*.sh
./scripts/install.sh --local --vpn-host 91.239.232.91 --vpn-bind-ip 91.239.232.91
```

### Оновлення після змін

```bash
cd /root/apps/postgres-prisma-stack/docker
./scripts/deploy.sh --stack-dir /root/apps/postgres-prisma-stack/docker
```

## Структура

```
docker/
├── docker-compose.yml          # Оркестратор
├── .env.example                # Шаблон змінних (скопіювати в .env)
├── postgres/
│   └── postgresql.conf         # Тюнінг Postgres
├── pgbouncer/
│   ├── pgbouncer.ini           # Конфіг пулера
│   └── userlist.txt            # Паролі для PgBouncer (тримати у .gitignore)
├── init/
│   ├── 01-create-project-dbs.sql   # Ролі та БД per-project
│   └── 02-init-extensions.sql      # PostgreSQL extensions
├── backup/
│   ├── backup.sh               # Щоденний pg_dump + ротація
│   └── restore.sh              # Відновлення БД
├── monitoring/
│   ├── prometheus.yml          # Конфіг Prometheus
│   └── grafana-datasource.yml  # Auto-provisioning datasource
└── scripts/
    ├── add-project.sh          # Додати новий проєкт (БД + user + URL)
    └── list-connections.sh     # Перевірити активні з'єднання
```

---

## Швидкий старт

### 1. Підготовка сервера

```bash
# Docker + Compose plugin
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

# Перевірка
docker --version && docker compose version
```

### 2. Клонувати репо та налаштувати .env

```bash
git clone <your-repo-url> pg-stack && cd pg-stack/docker

# Скопіювати шаблон
cp .env.example .env

# Заповнити ОБОВ'ЯЗКОВО:
#   POSTGRES_PASSWORD    — strong password для pgadmin
#   PROJECT_APP1_PASS    — пароль для першого проєкту
#   (і далі per-project)
nano .env
```

### 3. Запустити стек

```bash
docker compose up -d

# Перевірити статус
docker compose ps

# Перевірити healthchecks
docker inspect postgres | grep -A 10 '"Health"'
docker inspect pgbouncer | grep -A 10 '"Health"'
```

### 4. Додати новий проєкт

```bash
# Задати VPN-хост (IP або hostname твого VPN-інтерфейсу)
export VPN_HOST=91.239.232.91

chmod +x scripts/add-project.sh
./scripts/add-project.sh myapp
```

Скрипт виведе готові рядки підключення:

```
DATABASE_URL="postgresql://myapp_user:PASS@91.239.232.91:6432/myapp?schema=public&pgbouncer=true&connect_timeout=10"
DIRECT_URL="postgresql://myapp_user:PASS@91.239.232.91:5432/myapp?schema=public&connect_timeout=10"
```

### 5. Додати URLs у Prisma

```env
# .env вашого Next.js / Node.js проєкту
DATABASE_URL="postgresql://myapp_user:PASS@91.239.232.91:6432/myapp?schema=public&pgbouncer=true&connect_timeout=10"
DIRECT_URL="postgresql://myapp_user:PASS@91.239.232.91:5432/myapp?schema=public&connect_timeout=10"
```

```prisma
// schema.prisma
datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")
  directUrl = env("DIRECT_URL")
}
```

```bash
# Перша міграція (через DIRECT_URL, минаючи PgBouncer)
npx prisma migrate deploy
```

---

## Операційні команди

### Перевірити стек

```bash
docker compose ps
docker compose logs -f postgres
docker compose logs -f pgbouncer
```

### Перевірити підключення

```bash
chmod +x scripts/list-connections.sh
./scripts/list-connections.sh
```

### Ручний backup зараз

```bash
docker exec pg_backup /usr/local/bin/backup.sh
```

### Переглянути backup-логи

```bash
docker exec pg_backup cat /backups/backup.log
```

### Відновлення однієї БД

```bash
# Скопіювати dump файл у контейнер
docker cp myapp_20260506.dump pg_backup:/backups/full/

# Відновити
docker exec -it pg_backup /usr/local/bin/restore.sh myapp /backups/full/myapp_20260506.dump
```

### Перезавантажити PgBouncer (після зміни конфігу)

```bash
docker restart pgbouncer
# або без даунтайму:
docker exec pgbouncer pkill -HUP pgbouncer
```

---

## Безпека

### Firewall (UFW)

```bash
# Заблокувати всі PostgreSQL-порти ззовні
sudo ufw deny 5432
sudo ufw deny 6432

# Дозволити тільки VPN-підмережу (наприклад 10.8.0.0/24)
sudo ufw allow from 10.8.0.0/24 to any port 6432 proto tcp

# Перевірити
sudo ufw status verbose
```

### .gitignore

```gitignore
# Додай у .gitignore репозиторію
.env
docker/pgbouncer/userlist.txt
docker/backup/*.log
backups/
```

### SSH Tunnel для DIRECT_URL під час міграцій (без відкривання 5432)

```bash
# На локальній машині:
ssh -L 5432:localhost:5432 user@your-server -N &

# Тоді DIRECT_URL на локалці:
DIRECT_URL="postgresql://myapp_user:PASS@localhost:5432/myapp?schema=public"
npx prisma migrate dev
```

---

## Моніторинг

- Prometheus: `http://YOUR_VPN_IP:9090` (тільки VPN-доступ)
- Grafana: підключи до Prometheus як datasource і завантаж дашборд [#9628](https://grafana.com/grafana/dashboards/9628) — PostgreSQL Statistics.

---

## Checklist перед production

- [ ] `.env` заповнений, паролі сильні (≥32 символи)
- [ ] `.env` та `userlist.txt` у `.gitignore`
- [ ] Порти 5432/6432 закриті Firewall ззовні
- [ ] VPN-доступ до сервера налаштований і перевірений
- [ ] `docker compose ps` — всі сервіси `healthy`
- [ ] `./scripts/add-project.sh` відпрацював, URL збережений
- [ ] Перша `prisma migrate deploy` пройшла успішно
- [ ] Ручний backup запущений і `backup.log` без помилок
- [ ] Test restore перевірений (відновив БД, перевірив дані)
- [ ] Моніторинг доступний і показує метрики
