# PostgreSQL Production Stack for Prisma

Production-ready Docker Compose stack with PostgreSQL, PgBouncer, backups and monitoring.

## Start
```bash
cp docker/.env.example docker/.env
# edit passwords

docker compose -f docker/docker-compose.yml up -d
```

## Add project and get Prisma URLs
```bash
export VPN_HOST=10.8.0.1
./docker/scripts/add-project.sh myapp
```
