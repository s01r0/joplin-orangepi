# OrangePi5 Joplin Server

## このシステムの目的

紙の書類や PDF をスキャンしてデジタル管理し、どこからでも検索・参照できる**自前のドキュメント管理基盤**を作ること。

クラウドサービス（Evernote 等）に依存せず、自宅の OrangePi5 をサーバーにすることでデータを手元に置いたまま運用する。

### やりたいこと・できること

```
ScanSnap でスキャン
    ↓ Google Drive の ScanSnap/Inbox/ に保存（ScanSnap Home の設定）
    ↓ rclone（2分おき）が Google Drive から /srv/scansnap/inbox/ へ転送
    ↓ 1分おきに自動取り込み
Joplin のノートになる（PDF 添付・タイトルはファイル名）
    ↓ Joplin Server（OrangePi5）と自動同期
PC・スマホの Joplin アプリからいつでも参照・検索
```

> Google Drive がバッファになるため、OrangePi5 がオフラインでもスキャンは必ず成功する。

- **紙 → デジタル**: ScanSnap でスキャンするだけで Joplin に自動取り込み
- **過去資産の移行**: Evernote の全ノート（5000件超）を Joplin に移行済み
- **全文検索**: Recoll WebUI でローカルの全 PDF・ノートを横断検索
- **自前サーバー**: データが手元にある。クラウド課金なし

## 構成

```
├── docs/
│   ├── 00_setup-guide.md            # ★ ゼロから構築する手順書（これを見れば再現できる）
│   ├── 01_os-setup.md               # OS初期設定（SSD移行・ネットワーク・SSH・セキュリティ）
│   ├── 02_joplin-server.md          # Joplin Server構築（PostgreSQL・Docker）
│   ├── 03_monitoring.md             # 監視・ヘルスチェック・Gmail通知
│   └── 04_scansnap.md               # ScanSnap→Joplin自動取り込み（rclone含む）
├── docker/
│   ├── joplin-run.sh                # Joplin Server コンテナ起動
│   ├── .env.example                 # joplin-run.sh 用 環境変数テンプレート
│   └── .env.joplin.example          # /srv/joplin/.env のテンプレート
├── scripts/
│   ├── joplin-menu.sh               # TUI 管理メニュー（状態確認・サービス操作・ログ閲覧）
│   ├── joplin-pg-backup.sh          # PostgreSQL 差分バックアップ（DB変更検知・MD5重複排除）
│   ├── check-joplin-server.sh       # サーバーヘルスチェック・自動再起動
│   ├── check-joplin-backup.sh       # バックアップ整合性チェック（gzip・鮮度・サイズ）
│   ├── alert-on-fail.sh             # 失敗時 Gmail 通知ラッパー
│   └── scansnap_to_joplin_cli.sh    # ScanSnap PDF → Joplin ノート自動取り込み
├── systemd/
│   ├── joplin-backup.service        # DB バックアップ（oneshot）
│   ├── joplin-backup.timer          # 毎日 03:15 JST
│   ├── joplin-backup-check.service  # バックアップ整合性チェック（oneshot）
│   ├── joplin-backup-check.timer    # 毎日 04:00 JST
│   ├── joplin-server-check.service  # サーバーヘルスチェック（oneshot）
│   ├── joplin-server-check.timer    # 10分おき
│   ├── rclone-scansnap-sync.service # Google Drive → inbox 転送（oneshot）
│   ├── rclone-scansnap-sync.timer   # 2分おき
│   ├── recoll-webui.service         # Recoll 全文検索 WebUI 常駐
│   ├── scansnap-to-joplin.service   # ScanSnap 取り込み
│   └── scansnap-to-joplin.timer     # 1分おき
├── env.example                      # /etc/joplin/env のテンプレート（SERVER_IP・ALERT_MAIL_TO）
└── restore.sh                       # 一括復旧スクリプト
```

## サーバー情報

| 項目 | 値 |
|------|----|
| ハードウェア | OrangePi5 (aarch64) |
| OS | Ubuntu 22.04.5 LTS |
| SSH | `ssh orangepi5`（~/.ssh/config 参照） |
| Joplin URL | `http://orangepi5.local:22300` |
| DB | PostgreSQL 14 / joplindb |
| バックアップ先 | `/var/backups/joplin/`（14日保持・MD5重複排除） |
| ScanSnap inbox | `/srv/scansnap/inbox/` |
| Recoll WebUI | `http://orangepi5.local:8080` |

## 復旧手順

### 1. リポジトリを取得

```bash
git clone https://github.com/s01r0/soi-channel.git
cd soi-channel/projects/202508_Joplin_orangepi
```

### 2. 環境変数ファイルを作成

```bash
# Docker 用
cp docker/.env.example docker/.env
nano docker/.env   # SERVER_IP と POSTGRES_PASSWORD を設定

# 監視スクリプト用（SERVER_IP と ALERT_MAIL_TO を設定）
sudo mkdir -p /etc/joplin
sudo cp env.example /etc/joplin/env
sudo nano /etc/joplin/env
sudo chmod 600 /etc/joplin/env
```

### 3. 一括復旧スクリプトを実行

```bash
sudo POSTGRES_PASSWORD=<パスワード> bash restore.sh
```

restore.sh が行うこと：
1. パッケージ更新・必要ソフトインストール
2. PostgreSQL ロール・DB 作成
3. Docker インストール・有効化
4. scripts/ を `/usr/local/sbin/` に配置
5. systemd/ を `/etc/systemd/system/` に配置・有効化
6. Joplin Server コンテナ起動

### 4. 手動で追加が必要なもの

restore.sh に含まれない設定（認証情報を含むため）：

```bash
# Gmail 通知（msmtp）
nano ~/.msmtprc   # docs/03_monitoring.md を参照

# rclone Google Drive 認証（ヘッドレス環境向け手順）
# → docs/04_scansnap.md の「rclone インストール・Google Drive 認証」を参照

# ScanSnap → Joplin の Joplin CLI 認証設定
joplin config sync.target 10
joplin config sync.10.path     "http://orangepi5.local:22300"
joplin config sync.10.username "<メールアドレス>"
joplin config sync.10.password "<パスワード>"

# /srv/joplin/.env
cp docker/.env.joplin.example /srv/joplin/.env
nano /srv/joplin/.env  # POSTGRES_PASSWORD を設定
```

### 5. Joplin クライアントを再接続

Joplin Desktop → 設定 → 同期
- サービス: **Joplin Server**
- URL: `http://orangepi5.local:22300`

## 日常運用

### 管理メニュー

SSH してメニューを起動する：

```bash
ssh orangepi5
joplin-menu
```

- **サーバー状態確認**: 全サービスの稼働状況・最終バックアップ日時を一覧表示
- **サービス操作**: 起動・停止・再起動・状態確認
- **ログ閲覧**: 各サービスの直近ログを表示

### 設定変更後の push

```bash
# Windows 側で実行
git add .
git commit -m "変更内容"
git push origin main    # GitHub
git push orangepi main  # OrangePi5

# OrangePi5 側で反映
ssh orangepi5 "cd ~/joplin-orangepi/projects/202508_Joplin_orangepi && git pull"
```
