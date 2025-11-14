# Headscale on Kubernetes with Cloudflare Tunnel

このガイドでは、Kubernetes上にHeadscaleをデプロイし、Cloudflare Tunnelを使用して外部からアクセスできるようにセットアップします。

## 前提条件

- Kubernetesクラスタ（v1.24以上）
- `kubectl` がセットアップされている
- Cloudflareアカウント（有料/無料問わず）
- Cloudflare Tunnel認証情報

## セットアップ手順

### 1. Cloudflare APIトークンの準備

このリポジトリでは、Kubernetes上の `cloudflared-setup` Job が Cloudflare API を直接呼び出し、トンネル作成・構成・DNS登録をすべて自動で行います。必要なのは十分な権限を持った API トークンだけです。

1. https://dash.cloudflare.com/profile/api-tokens を開く
2. **Create Token** → **Edit Cloudflare Tunnels** テンプレートを選択
3. 追加で `Zone > DNS > Edit` 権限を付与（自動でCNAMEを作成するため）
4. 対象アカウント/ゾーンを指定
5. トークンを発行し `.env` に保存（再表示不可）

> 🔐 セットアップJobは、このトークンで Cloudflare Account API を叩き、トンネルの作成/再利用・トークン取得・ConfigMap/Secret更新・DNS作成を行います。

### 2. 追加で用意しておくと便利な情報

| 項目 | 用途 | 入手方法 |
|------|------|----------|
| `CLOUDFLARE_ACCOUNT_ID` | 複数アカウントを使う場合の明示指定 | Cloudflareダッシュボード左下または `GET /accounts` API |
| `CLOUDFLARE_ZONE_ID` | 特殊TLDなどで自動解決が難しい場合のフォールバック | ダッシュボード > Website > Overview |
| `CLOUDFLARE_TUNNEL_NAME` | デフォルト以外の名前を使いたい場合 | 任意 | 

これらは `.env` のオプション項目です。指定しなければ Job が自動検出／デフォルト値を用います。

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
NAMESPACE=headscale
STORAGE_CLASS=longhorn
STORAGE_SIZE=1Gi
TZ=Asia/Tokyo

CLOUDFLARE_API_TOKEN=v1.0_xxxxxxxxx
CLOUDFLARE_ACCOUNT_ID=abc123def456abc123def456abc123de   # 任意
CLOUDFLARE_ZONE_ID=def456abc123def456abc123def456ab       # 任意
CLOUDFLARE_TUNNEL_NAME=headscale-k8s-tunnel               # 任意
```

### 4. デプロイ

```bash
# デプロイスクリプトを実行
./deploy.sh
```

スクリプトが以下を自動的に行います：
- Kubernetesネームスペースの作成
- HeadscaleのConfigMap/PVC/Deployment/Serviceデプロイ
- Cloudflared Deploymentのデプロイ
- Cloudflare APIを利用したTunnel作成/取得、Token生成、ConfigMap+Secret更新、DNS CNAME登録

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

### 6. Cloudflare DNSレコードの確認

Setup Job が `HEADSCALE_DOMAIN` 向けの CNAME を自動で作成します。念のため Cloudflareダッシュボードの DNS レコード一覧で `headscale`（または指定サブドメイン）が `<tunnel-id>.cfargotunnel.com` を指していることを確認してください。

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

APIトークンの権限不足、もしくは `cloudflared-setup` Job がトンネル設定に失敗しています。

- `kubectl logs job/cloudflared-setup -n headscale` で詳細を確認
- トークンに `Cloudflare Tunnel (Edit/Read)`・`Account Settings (Read)`・`DNS (Edit)` が含まれているかチェック
- 同名トンネルが壊れている場合は Cloudflare ダッシュボードで削除後に `kubectl delete job/cloudflared-setup -n headscale` で再実行

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

4. `cloudflared-setup` Job が CNAME レコードを作成したか、ログに `DNS record created/updated` が出力されているか確認

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
- Cloudflare APIトークンは機密情報です。バージョン管理には含めないでください
- 定期的にCloudflareのAPIトークンをローテーションしてください
- Headscaleの `private.key` と `noise_private.key` はPersistentVolumeに安全に保存されます

## 参考リンク

- [Headscale公式ドキュメント](https://headscale.net/)
- [Cloudflare Tunnel ドキュメント](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Tailscale 公式ドキュメント](https://tailscale.com/kb/)