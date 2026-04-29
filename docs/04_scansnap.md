# ScanSnap → Joplin 自動取り込み

ScanSnap でスキャンした PDF を `/srv/scansnap/inbox` に置くと、
Joplin CLI が自動でノートを作成・PDF を添付・タイトルを OCR から設定する。

systemd timer で定期的に処理する。

## フロー概要

```
ScanSnap でスキャン
    ↓
Google Drive の ScanSnap/Inbox/ に保存（ScanSnap Home の設定）
    ↓
rclone move（2分おき）が Google Drive から /srv/scansnap/inbox/ へ転送
    ↓
scansnap-to-joplin timer（1分おき）が検知・処理
    ↓
Joplin のノートになる（PDF 添付・タイトルはファイル名）
    ↓
Joplin Server と自動同期
```

> Google Drive がバッファになるため、OrangePi5 がオフラインでもスキャンは必ず成功する。
> 転送は OrangePi5 側の rclone が担うので Windows のタスクスケジューラ等の対応は不要。

---

## ディレクトリ構成

```
/srv/scansnap/
├── inbox/       # rclone が Google Drive から転送する受け取り場所
├── done/        # 処理済み PDF
├── error/       # 処理失敗 PDF
├── processing/  # 処理中（一時）
└── logs/        # ログ（rclone.log, scansnap_to_joplin.log）
```

---

## セットアップ

### ディレクトリ・スクリプト準備

```bash
sudo mkdir -p /srv/scansnap/{inbox,done,error,processing,logs}
sudo chown -R ubuntu:ubuntu /srv/scansnap
sudo chmod -R 775 /srv/scansnap
```

### rclone インストール・Google Drive 認証

```bash
sudo apt install -y rclone
```

OrangePi5 はヘッドレスのため、`rclone config` の対話フローはブラウザ認証が使えず動作しない。
代わりに **Windows側でトークンを取得し、設定ファイルを直接作成する**。

**① Windows側でトークン取得**（rclone が入っていない場合は `winget install Rclone.Rclone`）

```powershell
rclone authorize "drive"
```

ブラウザで Google Drive を認証すると、ターミナルに JSON トークンが表示される（`{"access_token":...}` の形式）。これをコピーする。

**② OrangePi5側で設定ファイルを直接作成**

```bash
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf << 'EOF'
[gdrive]
type = drive
scope = drive
token = ここに①でコピーしたJSONトークン全体を貼り付け
EOF
```

**③ 動作確認とフォルダパスの確認**

> **注意:** Google Drive のフォルダ名は**大文字・小文字を区別する**。
> 以下のコマンドで実際のフォルダ構造を確認し、`systemd/rclone-scansnap-sync.service` の
> パスを自分の環境に合わせて修正すること（このリポジトリでは `ScanSnap/Inbox` になっているが、
> ScanSnap Home で設定したフォルダ名を使っているため環境によって異なる）。

```bash
# Google Drive のルートを確認
rclone ls gdrive:

# ScanSnap の保存先フォルダを確認（正確なパスを確認してからサービスファイルに反映）
rclone ls gdrive:ScanSnap/Inbox
```

### rclone 同期 systemd ユニット

```bash
sudo install -m 0644 systemd/rclone-scansnap-sync.service /etc/systemd/system/
sudo install -m 0644 systemd/rclone-scansnap-sync.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now rclone-scansnap-sync.timer
```

> `rclone move` を使用しているため、Google Drive 側の inbox は転送後に空になる。
> ダウンロード済みのファイルが再取得されることはない。

### Joplin CLI 設定

```bash
# Joplin CLI インストール（nvm 環境で）
npm install -g joplin

# Joplin CLI の同期設定（ubuntu ユーザーで実行）
joplin config sync.target 10
joplin config sync.10.path      "http://orangepi5.local:22300"
joplin config sync.10.username  "<Joplinユーザーのメールアドレス>"
joplin config sync.10.password  "<Joplinユーザーのパスワード>"
joplin sync --log-level info
```

> 設定は実行ユーザーのプロファイルに紐づく。systemd で動かすユーザーと合わせること。

### 取り込みタイマー有効化

```bash
sudo install -m 0644 systemd/scansnap-to-joplin.service /etc/systemd/system/
sudo install -m 0644 systemd/scansnap-to-joplin.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now scansnap-to-joplin.timer
```

### ScanSnap Home の設定（Windows）

1. ScanSnap Home → プロファイル設定 → 対象プロファイルを選択
2. 保存先クラウド: **Google Drive** → フォルダ `ScanSnap/Inbox`
   （フォルダ名は自由に設定してよいが、`rclone-scansnap-sync.service` の `gdrive:` パスと一致させること）
3. Windows タスクスケジューラの転送タスクは**削除**（rclone が代替するため不要）

---

## 取り込みスクリプト

`/usr/local/sbin/scansnap_to_joplin_cli.sh` として配置する。

主な処理フロー：
1. `inbox/` の PDF を `processing/` に移動
2. Joplin CLI でノートを作成（タイトル = ファイル名）
3. PDF を添付
4. 同期
5. `done/` に移動（エラー時は `error/` に移動）

---

## 確認コマンド

```bash
# rclone 同期ログ
tail -f /srv/scansnap/logs/rclone.log

# rclone を手動実行
sudo systemctl start rclone-scansnap-sync.service
journalctl -u rclone-scansnap-sync.service -n 20 --no-pager

# 取り込みスクリプトを手動実行
sudo systemctl start scansnap-to-joplin.service
journalctl -u scansnap-to-joplin.service -n 50 --no-pager

# 処理済みファイル確認
ls -lh /srv/scansnap/done/
ls -lh /srv/scansnap/error/
```

---

## Samba（オプション：PC から直接フォルダを参照したい場合）

inbox を Windows エクスプローラーでブラウズしたい場合のみ設定する。スキャンのフローには不要。

```bash
sudo apt install -y samba

sudo tee -a /etc/samba/smb.conf << 'EOF'

[scansnap]
   path = /srv/scansnap
   browseable = yes
   writable = yes
   valid users = ubuntu
   create mask = 0664
   directory mask = 0775
EOF

sudo smbpasswd -a ubuntu
sudo systemctl restart smbd && sudo systemctl enable smbd
```

Windows 側: エクスプローラー → `\\orangepi5\scansnap` でアクセス可。

---

## 注意事項

- ロックファイルは `/srv/scansnap/scansnap_to_joplin.lock` に置く
  （`/run` 配下は Permission denied になるため）
- `.env` にクレデンシャルを書く場合は `chmod 600` で保護し、git には含めない
- rclone の Google Drive リモート名は `gdrive` で統一する（service ファイルと合わせること）
- GDrive のフォルダパスは環境により異なる。`rclone ls gdrive:` で確認して service ファイルを修正する
