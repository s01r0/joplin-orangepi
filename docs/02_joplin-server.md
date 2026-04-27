# Joplin Server 構築手順

## 1. Node.js（nvm 経由）

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install --lts

# 確認
node -v
npm -v
```

---

## 2. PostgreSQL セットアップ

```bash
sudo apt install -y postgresql
sudo systemctl enable --now postgresql

# ロール・DB 作成
sudo -u postgres psql -c "CREATE ROLE joplin WITH LOGIN PASSWORD '<パスワード>';"
sudo -u postgres psql -c "CREATE DATABASE joplindb OWNER joplin;"
sudo -u postgres psql -c "ALTER ROLE joplin SET client_encoding TO 'UTF8';"
sudo -u postgres psql -c "ALTER ROLE joplin SET default_transaction_isolation TO 'read committed';"
sudo -u postgres psql -c "ALTER ROLE joplin SET timezone TO 'UTC';"
```

> `could not change directory` エラーは無害（権限の問題なので動作に影響なし）。

### 外部接続設定

`/etc/postgresql/14/main/postgresql.conf`:
```
listen_addresses = '*'
```

`/etc/postgresql/14/main/pg_hba.conf`:
```
host    joplindb    joplin    192.168.0.0/24    md5
```

```bash
sudo systemctl restart postgresql
```

---

## 3. Docker セットアップ

```bash
sudo apt install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
echo "deb [arch=arm64] https://download.docker.com/linux/ubuntu jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# → 反映には再ログインが必要

# 確認
docker --version
docker compose version
docker run --rm hello-world
```

---

## 4. Joplin Server コンテナ起動

```bash
sudo docker pull joplin/server:latest

sudo docker run -d --name joplin-server \
  -e APP_PORT=22300 \
  -e APP_BASE_URL=http://<SERVER_IP>:22300 \
  -e POSTGRES_PASSWORD=<パスワード> \
  -e POSTGRES_DATABASE=joplindb \
  -e POSTGRES_USER=joplin \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_HOST=<SERVER_IP> \
  -p 22300:22300 \
  --restart unless-stopped \
  joplin/server:latest

# 確認
curl -i http://<SERVER_IP>:22300/api/ping
docker ps | grep joplin
```

> `docker/joplin-run.sh` を使えば `.env` から自動読み込みして起動できる。

---

## 5. Joplin 管理ユーザー作成

ブラウザで `http://<SERVER_IP>:22300` にアクセスし、**Admin** でログイン。

`Users` メニューからアカウントを作成する。

---

## 6. クライアント（Joplin Desktop）接続設定

設定 → 同期：
- サービス: **Joplin Server (Beta)**
- URL: `http://<SERVER_IP>:22300`
- メールアドレス・パスワード: 作成したユーザーのもの
- 「現在の設定を確認」で成功すれば完了

---

## 7. バックアップ（systemd timer）

```bash
# スクリプト配置
sudo install -m 0755 -o root -g root scripts/joplin-pg-backup.sh /usr/local/sbin/

# ディレクトリ準備
sudo mkdir -p /var/backups/joplin /var/lib/joplin-backup
sudo chown postgres:postgres /var/backups/joplin /var/lib/joplin-backup

# systemd ユニット配置
sudo install -m 0644 systemd/joplin-backup.service /etc/systemd/system/
sudo install -m 0644 systemd/joplin-backup.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now joplin-backup.timer

# 確認
systemctl list-timers | grep joplin
```

バックアップ先: `/var/backups/joplin/joplindb_YYYY-MM-DD_HHMMSS.sql.gz`（14日分保持）
