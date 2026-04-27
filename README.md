# OrangePi5 Joplin Server

## このシステムの目的

紙の書類や PDF をスキャンしてデジタル管理し、どこからでも検索・参照できる**自前のドキュメント管理基盤**を作ること。

クラウドサービス（Evernote 等）に依存せず、自宅の OrangePi5 をサーバーにすることでデータを手元に置いたまま運用する。

### やりたいこと・できること

```
ScanSnap でスキャン
    ↓ PDF が /srv/scansnap/inbox/ に保存される
    ↓ 1分おきに自動取り込み
Joplin のノートになる（PDF 添付・タイトルはファイル名）
    ↓ Joplin Server（OrangePi5）と自動同期
PC・スマホの Joplin アプリからいつでも参照・検索
```

- **紙 → デジタル**: ScanSnap でスキャンするだけで Joplin に自動取り込み
- **過去資産の移行**: Evernote の全ノート（5000件超）を Joplin に移行済み
- **全文検索**: Recoll WebUI でローカルの全 PDF・ノートを横断検索
- **自前サーバー**: データが手元にある。クラウド課金なし

OrangePi5 上に構築した Joplin Server の設定ファイルと復旧手順。

## 構成

```
├── docs/
│   ├── 00_setup-guide.md            # ★ ゼロから構築する手順書（これを見れば再現できる）
│   ├── 01_os-setup.md               # OS初期設定（SSD移行・ネットワーク・SSH・セキュリティ）
│   ├── 02_joplin-server.md          # Joplin Server構築（PostgreSQL・Docker）
│   ├── 03_monitoring.md             # 監視・ヘルスチェック・Gmail通知
│   └── 04_scansnap.md               # ScanSnap→Joplin自動取り込み
├── docker/
│   ├── joplin-run.sh                # Joplin Server コンテナ起動
│   ├── .env.example                 # joplin-run.sh 用 環境変数テンプレート
│   └── .env.joplin.example          # /srv/joplin/.env のテンプレート
├── scripts/
│   ├── joplin-pg-backup.sh          # PostgreSQL 差分バックアップ（DB変更検知付き）
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
│   ├── recoll-webui.service         # Recoll 全文検索 WebUI 常駐
│   ├── scansnap-to-joplin.service   # ScanSnap 取り込み
│   └── scansnap-to-joplin.timer     # 1分おき
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
| バックアップ先 | `/var/backups/joplin/`（14日分保持） |
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
cp docker/.env.example docker/.env
nano docker/.env  # SERVER_IP と POSTGRES_PASSWORD を設定
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

### 状態確認

```bash
# コンテナ
docker ps | grep joplin
docker logs joplin-server --tail 50

# タイマー
systemctl list-timers | grep joplin
systemctl list-timers | grep scansnap

# バックアップ
ls -lh /var/backups/joplin/
sudo systemctl start joplin-backup-check.service
journalctl -u joplin-backup-check.service -n 50 --no-pager

# ScanSnap 取り込みログ
tail -f /srv/scansnap/logs/scansnap_to_joplin.log
```

### 設定変更後の push

```bash
# Windows 側で実行
git add .
git commit -m "変更内容"
git push origin main    # GitHub（メインバックアップ）
git push orangepi main  # OrangePi5（ローカルバックアップ）
```
