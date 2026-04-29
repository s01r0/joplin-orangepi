# 監視・ヘルスチェック・通知

## 1. Joplin Server ヘルスチェック

`/usr/local/sbin/check-joplin-server.sh` が 10 分おきに HTTP ステータスを確認し、
異常時は `docker restart` で自動回復する。

### スクリプト配置

```bash
sudo install -m 0755 -o root -g root scripts/check-joplin-server.sh /usr/local/sbin/
```

### systemd ユニット配置

```bash
sudo install -m 0644 systemd/joplin-server-check.service /etc/systemd/system/
sudo install -m 0644 systemd/joplin-server-check.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now joplin-server-check.timer
```

### 確認コマンド

```bash
# 手動実行
sudo systemctl start joplin-server-check.service
journalctl -u joplin-server-check.service -n 50 --no-pager

# タイマー確認
systemctl list-timers | grep joplin
```

---

## 2. バックアップ整合性チェック

`/usr/local/sbin/check-joplin-backup.sh` が最新バックアップを検証する。

チェック内容：
- 最終更新が 24 時間以内か
- ファイルサイズが規定値以上か
- gzip で展開可能か

### systemd ユニット配置

```bash
sudo install -m 0644 systemd/joplin-backup-check.service /etc/systemd/system/
sudo install -m 0644 systemd/joplin-backup-check.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now joplin-backup-check.timer
```

---

## 3. Gmail 通知（msmtp）

監視エラーを Gmail 経由で通知する。

### インストール

```bash
sudo apt install -y msmtp
```

### 設定ファイル `~/.msmtprc`

```
account gmail
host smtp.gmail.com
port 465
protocol smtp
auth on
user your-email@gmail.com
from your-email@gmail.com
password <Googleアプリパスワード>
tls on
tls_starttls off
logfile ~/.msmtp.log

account default: gmail
```

```bash
chmod 600 ~/.msmtprc
```

> Gmail の「2段階認証」を有効にし、「アプリパスワード」を発行して使用すること。
> ポート 587 (STARTTLS) は認証失敗するため、**465 (SSL/TLS) + アプリパスワード** を使う。

### テスト送信

```bash
echo "Test mail from OrangePi5" | msmtp -a gmail your-email@gmail.com
```

---

## 4. 全体的な状態確認コマンド

```bash
# コンテナ確認
docker ps | grep joplin
docker logs joplin-server --tail 50

# バックアップ確認
ls -lh /var/backups/joplin/
systemctl list-timers | grep joplin

# ディスク使用量
df -h
```
