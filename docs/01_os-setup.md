# OrangePi5 OS 初期設定

## 1. SD カード → NVMe SSD 切り替え

```bash
# NVMe に SD カードの内容をコピー
sudo wipefs -a /dev/nvme0n1
sudo dd if=/dev/mmcblk1 of=/dev/nvme0n1 bs=4M status=progress
sync

# ファイルシステム修復・UUID変更（重複回避）
sudo e2fsck -f /dev/nvme0n1p2
sudo tune2fs -U random /dev/nvme0n1p2

# UUID 確認
sudo blkid /dev/nvme0n1p2

# ブートローダーに UUID を反映
sudo vi /boot/extlinux/extlinux.conf
# → root=UUID=<NVMe の UUID> に書き換え

# fstab 設定
sudo vi /etc/fstab
# UUID=<NVMe の UUID>  /  ext4  defaults  0 1
```

> 初回は SD から起動して設定後、再起動で NVMe から起動する。
> 起動失敗時は `journalctl -b -1 -p err` でログ確認。

---

## 2. ネットワーク設定（Wi-Fi 固定 IP）

```bash
# インターフェース名確認
ip link

# Netplan 設定
sudo vi /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  wifis:
    wlx90de80709951:
      dhcp4: true
      access-points:
        "TP-Link":
          password: "<パスワード>"
```

```bash
sudo netplan generate
sudo netplan apply
```

> `cloud-init` が干渉する場合は `sudo apt purge cloud-init` で除去済み。
> ルーター側で MAC アドレスによる固定 IP 割り当てを設定すること。

---

## 3. セキュリティ設定

### UFW ファイアウォール

```bash
sudo ufw allow ssh
sudo ufw enable
sudo ufw status
```

### Fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo vi /etc/fail2ban/jail.local  # [sshd] を enabled = true に変更
sudo systemctl restart fail2ban

# 確認
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

---

## 4. SSH 公開鍵認証・強化

### Windows 側（鍵生成）

```powershell
ssh-keygen -t ed25519 -C "your_email@example.com"
# id_ed25519, id_ed25519.pub が生成される

# 公開鍵をサーバーにコピー
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@192.168.0.13 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### サーバー側（sshd 設定変更）

```bash
sudo vi /etc/ssh/sshd_config
# 以下を確認・修正
# PubkeyAuthentication yes
# PasswordAuthentication no
# PermitRootLogin no

sudo systemctl restart sshd
```

### Windows SSH config

`~/.ssh/config`:

```
Host orangepi5
    HostName 192.168.0.13
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519
```

---

## 5. 基本ユーティリティインストール

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y \
  build-essential git curl wget unzip \
  htop vim net-tools lsb-release \
  ca-certificates apt-transport-https \
  software-properties-common \
  python3 python3-pip \
  ufw fail2ban unattended-upgrades \
  dnsutils iproute2 iputils-ping traceroute tcpdump nmap

# タイムゾーン設定
sudo timedatectl set-timezone Asia/Tokyo
```
