# Headscale on Kubernetes with Cloudflare Tunnel

このガイドでは、Kubernetes上にHeadscaleをデプロイし、Cloudflare Tunnelを使用して外部からアクセスできるようにセットアップします。

## 前提条件

- Kubernetesクラスタ（v1.24以上）
- `kubectl` がセットアップされている
- Cloudflareアカウント（有料/無料問わず）
- Cloudflare Tunnel認証情報

## セットアップ手順

### 1. Cloudflare Tunnelの作成

Cloudflare Tunnelを作成して必要な認証情報を取得します。

#### 方法A: Cloudflareダッシュボードを使用

**重要**: この方法ではトンネルは作成されますが、Secretを直接取得できません。方法Bの方が推奨です。

1. https://dash.cloudflare.com/ にログイン
2. サイドバーから **Networks** → **Tunnels** を選択
3. **Create a tunnel** をクリック
4. 名前を入力: `headscale-k8s-tunnel`
5. Connectorの接続を選択してからTunnel IDをコピー
6. **Public hostname** を設定:
   - Domain: あなたのドメイン
   - Subdomain: `headscale`
   - Type: `HTTP`
   - URL: `http://headscale-service.headscale.svc.cluster.local:8080`

**Secretの取得**: ダッシュボードからはSecretを直接取得できません。以下のいずれかの方法を使用してください。

#### 方法B: cloudflared CLIを使用

```bash
# cloudflaredをインストール
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# トンネルを作成
cloudflared tunnel create headscale-k8s-tunnel

# 認証情報を確認
cat ~/.cloudflared/cert.pem
cat ~/.cloudflared/headscale-k8s-tunnel.json
```

### 2. 必要な情報の確認と取得

セットアップには以下の情報が必要です：

#### CLOUDFLARE_ACCOUNT_ID の取得

1. https://dash.cloudflare.com/ にログイン
2. **左下のメニュー**で、あなたのアカウント名をクリック
3. **Account ID** が表示されます（32文字の英数字）
   - 例: `abc123def456abc123def456abc123de`
4. このIDをコピーして `.env` ファイルに貼り付け

**⚠️ よくある間違い**:
- API Token や API Key ではなく、Account ID を使用してください
- Account ID は通常、ダッシュボードの左下に表示されます

#### CLOUDFLARE_TUNNEL_ID と CLOUDFLARE_TUNNEL_SECRET の取得

方法B（cloudflared CLI）で取得するのが最も確実です：

```bash
# cloudflaredをインストール（まだインストールされていない場合）
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# トンネルを作成
cloudflared tunnel create headscale-k8s-tunnel

# トンネルの認証情報を確認
cat ~/.cloudflared/headscale-k8s-tunnel.json
```

出力例：
```json
{
  "AccountTag": "YOUR_ACCOUNT_ID",
  "TunnelID": "12345678-1234-1234-1234-123456789abc",
  "TunnelName": "headscale-k8s-tunnel",
  "TunnelSecret": "abcdefghijklmnopqrstuvwxyzABCDEF1234567890=="
}
```

以下の値を `.env` ファイルに設定：
- `CLOUDFLARE_TUNNEL_ID`: `TunnelID` フィールドの値
- `CLOUDFLARE_TUNNEL_SECRET`: `TunnelSecret` フィールドの値

#### 必要な情報の一覧

| 情報 | 入手方法 |
|------|--------|
| **CLOUDFLARE_ACCOUNT_ID** | Cloudflareダッシュボードの左下（Account ID） |
| **CLOUDFLARE_TUNNEL_ID** | `cloudflared tunnel create` 後の JSON ファイルの `TunnelID` |
| **CLOUDFLARE_TUNNEL_SECRET** | `cloudflared tunnel create` 後の JSON ファイルの `TunnelSecret` |
| **HEADSCALE_DOMAIN** | あなたのドメイン（例: `headscale.example.com`） |

### 3. 環境変数の設定

```bash
# .envファイルを作成
cp .env.example .env

# .envを編集して以下を設定
nano .env
```

`.env`ファイルの内容例：

```bash
HEADSCALE_DOMAIN=headscale.example.com
CLOUDFLARE_ACCOUNT_ID=abc123def456abc123def456abc123de
CLOUDFLARE_TUNNEL_ID=12345678-1234-1234-1234-123456789abc
CLOUDFLARE_TUNNEL_SECRET=abcdefghijklmnopqrstuvwxyzABCDEF1234567890==
NAMESPACE=headscale
STORAGE_CLASS=longhorn
STORAGE_SIZE=1Gi
TZ=Asia/Tokyo
```

### 4. デプロイ

```bash
# デプロイスクリプトを実行
./deploy.sh
```

スクリプトが以下を自動的に行います：
- Kubernetesネームスペースの作成
- Headscaleの設定ファイル（ConfigMap）の作成
- Headscale Deploymentのデプロイ
- Cloudflared Tunnelのデプロイ

### 5. ポッドの起動を確認

```bash
# ポッドの状態を確認
kubectl get pods -n headscale

# 期待される出力例:
# NAME                         READY   STATUS    RESTARTS   AGE
# headscale-7f95847f86-xxxxx   1/1     Running   0          2m
# cloudflared-6b4496668-xxxxx  1/1     Running   0          1m
# cloudflared-5cb74cb8f7-xxxxx 1/1     Running   0          1m
```

すべてのポッドが `Running` 状態に達するまで待機してください。

### 6. Cloudflare DNSレコードの設定

Cloudflareダッシュボードで DNS レコードを設定します：

1. https://dash.cloudflare.com/ → Websites → あなたのドメイン
2. **DNS** → **Records** を選択
3. **Add record** をクリック
4. 以下を設定：
   - **Type**: `CNAME`
   - **Name**: `headscale`（またはあなたが指定したサブドメイン）
   - **Target**: `<TUNNEL_ID>.cfargotunnel.com`（例: `12345678-1234-1234-1234-123456789abc.cfargotunnel.com`）
   - **Proxy status**: `Proxied`（オレンジ色）
   - **TTL**: `Auto`
5. **Save** をクリック

## Headscaleの使用

### ユーザーの作成

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale users create myuser
```

### Pre-authキーの生成

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale preauthkeys create --user myuser --expiration 24h
```

出力例：
```
Pre-auth key: 0123456789abcdef0123456789abcdef01234567
```

### デバイスの接続

```bash
tailscale up --login-server https://headscale.example.com --authkey 0123456789abcdef0123456789abcdef01234567
```

### ノードの確認

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale nodes list
```

### ユーザーの確認

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale users list
```

## トラブルシューティング

### Headscaleが CrashLoopBackOff 状態の場合

```bash
kubectl logs deploy/headscale -n headscale
```

よくあるエラー：

#### `server_url cannot be part of base_domain`

このエラーは設定ファイルに矛盾がある場合に発生します。最新バージョンではこの問題は修正されています。

#### `connection refused`

headscaleが起動していない可能性があります。ログを確認してください。

### Cloudflaredが接続できない場合

```bash
kubectl logs deploy/cloudflared -n headscale
```

よくあるエラー：

#### `Unauthorized: Failed to get tunnel`

credentials.json が正しく設定されていません。`.env` ファイルの `CLOUDFLARE_TUNNEL_*` 値を確認してください。

#### `Cannot determine default origin certificate path`

cloudflaredの設定ファイルが正しくマウントされていない可能性があります。以下を確認：

```bash
kubectl exec -it deploy/cloudflared -n headscale -- ls -la /etc/cloudflared/
```

### ドメインにアクセスできない場合

1. DNS レコードが正しく設定されているか確認：
```bash
nslookup headscale.example.com
```

2. Cloudflareダッシュボードで Tunnel の状態を確認
3. Cloudflaredポッドが正常に実行されているか確認：
```bash
kubectl logs deploy/cloudflared -n headscale
```

## ログの確認

### Headscaleのログ

```bash
# リアルタイムログ
kubectl logs -f deploy/headscale -n headscale

# 最新100行
kubectl logs deploy/headscale -n headscale --tail=100
```

### Cloudflaredのログ

```bash
# リアルタイムログ
kubectl logs -f deploy/cloudflared -n headscale

# 特定のポッドのログ
kubectl logs cloudflared-<pod-id> -n headscale
```

## クリーンアップ

すべてのリソースを削除する場合：

```bash
kubectl delete namespace headscale
```

## セキュリティに関する注意

- `.env` ファイルは `.gitignore` に含まれています（バージョン管理に追加しないでください）
- `CLOUDFLARE_TUNNEL_SECRET` は機密情報です。バージョン管理には含めないでください
- 定期的にCloudflareのAPIトークンをローテーションしてください
- Headscaleの `private.key` と `noise_private.key` はPersistentVolumeに安全に保存されます

## 参考リンク

- [Headscale公式ドキュメント](https://headscale.net/)
- [Cloudflare Tunnel ドキュメント](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Tailscale 公式ドキュメント](https://tailscale.com/kb/)