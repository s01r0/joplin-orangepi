# セットアップガイド：OrangePi5 Joplin Server

このガイド一本を上から順に実行すれば、ゼロからJoplin Server環境が完成します。
詳細な補足は各 `01_〜04_` ドキュメントを参照してください。

---

## 必要なもの

### ハードウェア
- OrangePi5（RAM 8GB推奨）
- NVMe SSD（250GB以上推奨）
- SDカード（初回起動用、16GB以上）
- Wi-Fiドングル または LANケーブル

### ソフトウェア・アカウント
- [OrangePi5 Ubuntu 22.04イメージ](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-5.html)（SDカードに書き込む）
- Windows PC（SSH接続用）
- ScanSnap（PDF取り込みを使う場合）
- Googleアカウント（Gmail通知を使う場合）

### 手元に控えておくもの
- PostgreSQLパスワード（自分で決める）
- JoplinのログインID・パスワード（自分で決める）
- GmailアプリパスワードまたはSMTP設定情報

---

## STEP 1：OrangePi5の初期設定

> 詳細: `01_os-setup.md`

### 1-1. SDカードからNVMe SSDへ移行

```bash
# OrangePi5にSSHして実行（初回はSDカードで起動）
sudo wipefs -a /dev/nvme0n1
sudo dd if=/dev/mmcblk1 of=/dev/nvme0n1 bs=4M status=progress
sync
sudo e2fsck -f /dev/nvme0n1p2
sudo tune2fs -U random /dev/nvme0n1p2

# NVMeのUUIDを確認してブートローダーに反映
sudo blkid /dev/nvme0n1p2
sudo vi /boot/extlinux/extlinux.conf   # root=UUID=<確認したUUID> に書き換え
sudo vi /etc/fstab                     # UUID=<確認したUUID>  /  ext4  defaults  0 1

sudo reboot  # SSDから再起動
```

### 1-2. ネットワーク設定（Wi-Fi）

```bash
sudo vi /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  wifis:
    wlx90de80709951:        # ip link で確認したIF名
      dhcp4: true
      access-points:
        "Wi-FiのSSID":
          password: "Wi-Fiパスワード"
```

```bash
sudo netplan generate && sudo netplan apply
```

> ルーターでMACアドレスによる固定IP割り当てを設定しておくと安定します。

### 1-3. セキュリティ設定

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ufw fail2ban

sudo ufw allow ssh
sudo ufw enable

sudo systemctl enable --now fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
# [sshd] の enabled = true を確認
sudo systemctl restart fail2ban
```

### 1-4. SSH公開鍵認証（Windowsで実行）

```powershell
# 鍵生成
ssh-keygen -t ed25519 -C "your_email@example.com"

# 公開鍵をOrangePi5に転送
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@<IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

```bash
# OrangePi5側：パスワード認証を無効化
sudo vi /etc/ssh/sshd_config
# PasswordAuthentication no
# PermitRootLogin no
sudo systemctl restart sshd
```

`~/.ssh/config` に追加（Windows側）：

```
Host orangepi5
    HostName <OrangePi5のIPアドレス>
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519
```

### 1-5. 基本ソフトウェア

```bash
sudo apt install -y \
  build-essential git curl wget unzip htop vim \
  net-tools ca-certificates apt-transport-https \
  software-properties-common python3 python3-pip

sudo timedatectl set-timezone Asia/Tokyo
```

---

## STEP 2：Joplin Server構築

> 詳細: `02_joplin-server.md`

### 2-1. Node.js（nvm経由）

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install --lts
```

### 2-2. PostgreSQL

```bash
sudo apt install -y postgresql
sudo systemctl enable --now postgresql

sudo -u postgres psql -c "CREATE ROLE joplin WITH LOGIN PASSWORD '<パスワード>';"
sudo -u postgres psql -c "CREATE DATABASE joplindb OWNER joplin;"
sudo -u postgres psql -c "ALTER ROLE joplin SET client_encoding TO 'UTF8';"
sudo -u postgres psql -c "ALTER ROLE joplin SET default_transaction_isolation TO 'read committed';"
sudo -u postgres psql -c "ALTER ROLE joplin SET timezone TO 'UTC';"
```

### 2-3. Docker

```bash
sudo apt install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
echo "deb [arch=arm64] https://download.docker.com/linux/ubuntu jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# 再ログインして反映
```

### 2-4. Joplin Serverコンテナ起動

```bash
sudo docker pull joplin/server:latest

sudo docker run -d --name joplin-server \
  -e APP_PORT=22300 \
  -e APP_BASE_URL=http://orangepi5.local:22300 \
  -e POSTGRES_PASSWORD=<パスワード> \
  -e POSTGRES_DATABASE=joplindb \
  -e POSTGRES_USER=joplin \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_HOST=<OrangePi5のIP> \
  -p 22300:22300 \
  --restart unless-stopped \
  joplin/server:latest

# 確認
curl -i http://orangepi5.local:22300/api/ping
```

### 2-5. 管理ユーザー作成

ブラウザで `http://orangepi5.local:22300` を開く。
`admin@localhost` / `admin` でログイン → Users → アカウント作成。

### 2-6. Joplin Desktopの接続設定

設定 → 同期：
- サービス: **Joplin Server**
- URL: `http://orangepi5.local:22300`
- メールアドレス・パスワード: 作成したアカウント

---

## STEP 3：バックアップ・監視スクリプトの配置

```bash
# このリポジトリをOrangePi5上でclone
git clone https://github.com/s01r0/soi-channel.git ~/soi-channel
cd ~/soi-channel/projects/202508_Joplin_orangepi

# 環境変数ファイル配置（IPアドレス・メールアドレスを実際の値に書き換えてから実行）
sudo mkdir -p /etc/joplin
sudo cp env.example /etc/joplin/env
sudo vi /etc/joplin/env          # SERVER_IP と ALERT_MAIL_TO を設定
sudo chmod 600 /etc/joplin/env
sudo chown root:root /etc/joplin/env

# スクリプト配置
sudo install -m 0755 -o root -g root scripts/joplin-pg-backup.sh    /usr/local/sbin/
sudo install -m 0755 -o root -g root scripts/check-joplin-server.sh /usr/local/sbin/
sudo install -m 0755 -o root -g root scripts/check-joplin-backup.sh /usr/local/sbin/
sudo install -m 0755 -o root -g root scripts/alert-on-fail.sh       /usr/local/sbin/

# バックアップ先ディレクトリ
sudo mkdir -p /var/backups/joplin /var/lib/joplin-backup
sudo chown postgres:postgres /var/backups/joplin /var/lib/joplin-backup

# systemdユニット配置
sudo install -m 0644 systemd/joplin-backup.service         /etc/systemd/system/
sudo install -m 0644 systemd/joplin-backup.timer           /etc/systemd/system/
sudo install -m 0644 systemd/joplin-backup-check.service   /etc/systemd/system/
sudo install -m 0644 systemd/joplin-backup-check.timer     /etc/systemd/system/
sudo install -m 0644 systemd/joplin-server-check.service   /etc/systemd/system/
sudo install -m 0644 systemd/joplin-server-check.timer     /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now joplin-backup.timer
sudo systemctl enable --now joplin-backup-check.timer
sudo systemctl enable --now joplin-server-check.timer

# 確認
systemctl list-timers | grep joplin
```

---

## STEP 4：Gmail通知設定（msmtp）

> 詳細: `03_monitoring.md`

```bash
sudo apt install -y msmtp
```

`~/.msmtprc` を作成：

```
account gmail
host smtp.gmail.com
port 465
protocol smtp
auth on
user <Gmailアドレス>
from <Gmailアドレス>
password <Googleアプリパスワード>
tls on
tls_starttls off
logfile ~/.msmtp.log

account default: gmail
```

```bash
chmod 600 ~/.msmtprc

# テスト送信
echo "Test from OrangePi5" | msmtp -a gmail <Gmailアドレス>
```

> Googleアプリパスワードの取得: Googleアカウント → セキュリティ → 2段階認証 → アプリパスワード

---

## STEP 5：ScanSnap自動取り込み設定

> 詳細: `04_scansnap.md`

### 5-1. ディレクトリ・スクリプト準備

```bash
sudo mkdir -p /srv/scansnap/{inbox,done,error,processing,logs}
sudo chown -R ubuntu:ubuntu /srv/scansnap
sudo chmod -R 775 /srv/scansnap

sudo install -m 0755 -o ubuntu -g ubuntu \
  scripts/scansnap_to_joplin_cli.sh /srv/scansnap/

sudo install -m 0644 systemd/scansnap-to-joplin.service /etc/systemd/system/
sudo install -m 0644 systemd/scansnap-to-joplin.timer   /etc/systemd/system/
```

### 5-2. rclone インストール・Google Drive 認証

```bash
sudo apt install -y rclone
```

OrangePi5 はヘッドレスのため `rclone config` の対話フローは使えない。Windows でトークンを取得し設定ファイルを直接作成する。

**Windows側**（rclone 未インストールなら `winget install Rclone.Rclone`）:

```powershell
rclone authorize "drive"
# ブラウザで認証 → {"access_token":...} のJSONトークンをコピー
```

**OrangePi5側**:

```bash
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
token = ここにコピーしたJSONトークンを貼り付け
EOF
```

動作確認とフォルダパスの確認：

```bash
# 実際のフォルダ名を確認（大文字・小文字を区別する）
rclone ls gdrive:ScanSnap/Inbox
```

> **注意:** Google Drive のフォルダ名は大文字・小文字を区別する。
> ScanSnap Home で設定したフォルダ名は環境によって異なるため、`rclone ls gdrive:` で確認し、
> `systemd/rclone-scansnap-sync.service` の `gdrive:` パスを自分の環境に合わせて修正すること。

### 5-3. rclone 同期タイマー有効化

```bash
sudo install -m 0644 systemd/rclone-scansnap-sync.service /etc/systemd/system/
sudo install -m 0644 systemd/rclone-scansnap-sync.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now rclone-scansnap-sync.timer
```

### 5-4. Joplin CLI 認証設定・取り込みタイマー有効化

```bash
npm install -g joplin

joplin config sync.target 10
joplin config sync.10.path     "http://orangepi5.local:22300"
joplin config sync.10.username "<JoplinのメールID>"
joplin config sync.10.password "<Joplinパスワード>"
joplin sync

sudo systemctl daemon-reload
sudo systemctl enable --now scansnap-to-joplin.timer

# 動作確認（PDFをinboxに置いて手動実行）
sudo systemctl start scansnap-to-joplin.service
tail -f /srv/scansnap/logs/scansnap_to_joplin.log
```

### 5-5. ScanSnap Home の設定（Windows）

1. ScanSnap Home → プロファイル設定 → 対象プロファイルを選択
2. 保存先クラウド: **Google Drive** → フォルダ `ScanSnap/inbox`
3. Windows タスクスケジューラの転送タスクは**削除**（rclone が代替するため不要）

---

## 最終確認チェックリスト

```bash
# Joplin Serverが動いているか
docker ps | grep joplin
curl -s http://orangepi5.local:22300/api/ping

# タイマーが全部動いているか
systemctl list-timers | grep -E "joplin|scansnap"

# バックアップが作られているか
ls -lh /var/backups/joplin/

# ディスク残量
df -h
```

- [ ] Joplin Desktop から同期できる
- [ ] スマホの Joplin アプリから同期できる
- [ ] PDFを inbox に置いたら Joplin に取り込まれる
- [ ] バックアップファイルが `/var/backups/joplin/` にある
- [ ] 毎朝 4:00 のバックアップチェックメールが届く
