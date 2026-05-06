# PostgreSQL + PgBouncer stack for Prisma (Docker Compose)

Усе в директорії **`docker/`**. Детальні інструкції: [docker/README.md](docker/README.md).

Швидко:

```bash
git clone https://github.com/Makmillerme/postgressserver-prisma-postgres-stack-v2.git
cd postgressserver-prisma-postgres-stack-v2/docker
cp .env.example .env
# заповни всі CHANGE_ME у .env і синхронізуй пароль pgadmin у pgbouncer/userlist.txt
chmod +x scripts/*.sh backup/*.sh
./scripts/install.sh --local --vpn-host YOUR_SERVER_IP --vpn-bind-ip YOUR_SERVER_IP
```

Репозиторій публічний: у `.env.example` і `userlist.txt` **немає реальних паролів**.
