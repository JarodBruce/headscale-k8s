# Headscale on Kubernetes with Cloudflare Tunnel

Kubernetes上にHeadscaleをデプロイし、Cloudflare Tunnelを使用して外部からアクセス可能にするセットアップです。

## 🎯 特徴

- ✅ Kubernetes上で動作するHeadscaleコントロールプレーン
- ✅ Cloudflare Tunnelによる安全な外部アクセス
- ✅ ポート開放不要（ローカルネットワーク向け）
- ✅ PersistentVolumeによるデータ永続化
- ✅ ワンコマンドデプロイ

## 📋 前提条件

- Kubernetesクラスタ（v1.24以上）
- `kubectl` がセットアップされている
- Cloudflareアカウント（無料可）
- Cloudflareで管理するドメイン

## 🚀 セットアップ（5分）

### 1. Cloudflare Tunnelの作成

```bash
# cloudflaredをインストール
brew install cloudflare/cloudflare/cloudflared  # macOS
# または Linux の場合
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# トンネルを作成
cloudflared tunnel create headscale-k8s-tunnel

# 認証情報を確認
cat ~/.cloudflared/headscale-k8s-tunnel.json
```

JSON出力例：
```json
{
  "AccountTag": "abc123def456abc123def456abc123de",
  "TunnelID": "12345678-1234-1234-1234-123456789abc",
  "TunnelName": "headscale-k8s-tunnel",
  "TunnelSecret": "abcdefghijklmnopqrstuvwxyzABCDEF1234567890=="
}
```

### 2. Account IDを取得

1. https://dash.cloudflare.com/ にログイン
2. **左下のメニュー**でアカウント名をクリック
3. **Account ID** をコピー（32文字の英数字）

### 3. 環境変数を設定

```bash
cp .env.example .env
nano .env
```

`.env` に以下を記入：
```env
HEADSCALE_DOMAIN=headscale.yourdomain.com
CLOUDFLARE_ACCOUNT_ID=abc123def456abc123def456abc123de
CLOUDFLARE_TUNNEL_ID=12345678-1234-1234-1234-123456789abc
CLOUDFLARE_TUNNEL_SECRET=abcdefghijklmnopqrstuvwxyzABCDEF1234567890==
NAMESPACE=headscale
STORAGE_CLASS=longhorn
STORAGE_SIZE=1Gi
TZ=Asia/Tokyo
```

### 4. デプロイを実行

```bash
./deploy.sh
```

スクリプトが以下を自動実行：
- Namespaceの作成
- Headscaleのデプロイ
- Cloudflared Tunnelのデプロイ

### 5. Cloudflareで DNS設定

1. https://dash.cloudflare.com/ → Websites → あなたのドメイン
2. **DNS** → **Records** → **Add record**
3. 以下を設定：
   - **Type**: `CNAME`
   - **Name**: `headscale`
   - **Target**: `<TUNNEL_ID>.cfargotunnel.com`
   - **Proxy status**: `Proxied` (オレンジ色)
4. **Save**

### 6. ポッドの状態確認

```bash
kubectl get pods -n headscale

# 出力例：
# NAME                        READY   STATUS    RESTARTS   AGE
# headscale-7f95847f86-xxxxx   1/1     Running   0          2m
# cloudflared-6b44966-xxxxx    1/1     Running   0          1m
# cloudflared-5cb74cb-xxxxx    1/1     Running   0          1m
```

すべてのポッドが `1/1 Running` または `Running` 状態になるまで待機。

## 💻 使用方法

### ユーザー作成

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale users create myuser
```

### Pre-auth keyの生成

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale preauthkeys create --user myuser --expiration 24h
```

### クライアント接続

```bash
tailscale up --login-server https://headscale.yourdomain.com --authkey <KEY>
```

### ノード確認

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale nodes list
```

## 🔍 トラブルシューティング

### Headscaleが起動しない

```bash
kubectl logs deploy/headscale -n headscale
```

**よくあるエラー**:
- `server_url cannot be part of base_domain` → このセットアップでは自動修正済み
- `connection refused` → ログで詳細確認

### Cloudflaredが接続できない

```bash
kubectl logs deploy/cloudflared -n headscale

# 以下のエラーが出た場合：
# Unauthorized: Failed to get tunnel → credentials.json が無効
```

原因と対策：
- `CLOUDFLARE_ACCOUNT_ID`: APIトークンではなく、Account IDであることを確認
- `CLOUDFLARE_TUNNEL_ID`: cloudflared tunnel listで確認
- `CLOUDFLARE_TUNNEL_SECRET`: JSONファイルの `TunnelSecret` フィールドを確認

### ドメインにアクセスできない

```bash
# DNS設定確認
nslookup headscale.yourdomain.com

# Tunnel設定確認
cloudflared tunnel info headscale-k8s-tunnel
```

確認項目：
- [ ] DNSレコード（CNAME）が設定されている
- [ ] Cloudflare Tunnelが接続状態（dashboard確認）
- [ ] Headscaleが Running 状態
- [ ] cloudflaredが Running 状態

## 📁 ファイル構成

```
headscale-k8s/
├── .env.example              # 環境変数テンプレート
├── .env                      # 実際の設定（.gitignore対象）
├── deploy.sh                 # デプロイスクリプト
├── SETUP.md                  # 詳細セットアップガイド
├── README.md                 # このファイル
└── k8s/
    ├── namespace.yaml        # Namespace定義
    ├── headscale.yaml        # Headscale設定・Deployment
    └── cloudflared.yaml      # Cloudflared設定・Deployment
```

## 🔑 コマンド集

| コマンド | 説明 |
|--------|------|
| `./deploy.sh` | デプロイを実行 |
| `kubectl get pods -n headscale` | ポッドの状態確認 |
| `kubectl logs deploy/headscale -n headscale` | Headscaleのログ |
| `kubectl logs deploy/cloudflared -n headscale` | Cloudflaredのログ |
| `kubectl delete namespace headscale` | すべてのリソースを削除 |

## 🔒 セキュリティ注意事項

- `.env` ファイルは `.gitignore` に含まれています（バージョン管理に追加しないでください）
- `CLOUDFLARE_TUNNEL_SECRET` は機密情報です
- Headscaleの秘密鍵はPersistentVolumeに安全に保存されます

## 📚 詳細情報

- **詳細セットアップ**: [SETUP.md](SETUP.md)
- **Headscale公式**: https://headscale.net/
- **Cloudflare Tunnel**: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- **Tailscale**: https://tailscale.com/

## 🗑️ アンインストール

```bash
kubectl delete namespace headscale
```

## ライセンス

設定ファイルはMITライセンス。
Headscaleのライセンスについては https://github.com/juanfont/headscale を参照。