# ScanSnap → Joplin 自動取り込み

ScanSnap でスキャンした PDF を `/srv/scansnap/inbox` に置くと、
Joplin CLI が自動でノートを作成・PDF を添付・タイトルを OCR から設定する。

systemd timer で定期的に処理する。

---

## ディレクトリ構成

```
/srv/scansnap/
├── inbox/       # ScanSnap からの受け取り場所
├── done/        # 処理済み PDF
├── error/       # 処理失敗 PDF
├── processing/  # 処理中（一時）
└── logs/        # ログ
```

---

## セットアップ

```bash
# ディレクトリ作成
sudo mkdir -p /srv/scansnap/{inbox,done,error,processing,logs}
sudo chown -R ubuntu:ubuntu /srv/scansnap
sudo chmod -R 775 /srv/scansnap

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
> root で設定すると systemd 実行時に別プロファイルが使われる。

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

## systemd ユニット

`/etc/systemd/system/scansnap-to-joplin.service` / `.timer` を配置して定期実行。

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now scansnap-to-joplin.timer
```

---

## 確認コマンド

```bash
# 手動テスト
sudo systemctl start scansnap-to-joplin.service
journalctl -u scansnap-to-joplin.service -n 50 --no-pager

# 処理済みファイル確認
ls -lh /srv/scansnap/done/
ls -lh /srv/scansnap/error/  # エラーがあれば
```

---

## 注意事項

- ロックファイルは `/srv/scansnap/scansnap_to_joplin.lock` に置く
  （`/run` 配下は Permission denied になるため）
- `.env` にクレデンシャルを書く場合は `chmod 600` で保護し、git には含めない
