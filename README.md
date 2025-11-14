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

### 1. Cloudflare APIトークンを準備

1. https://dash.cloudflare.com/profile/api-tokens へアクセス
2. **Create Token** → **Edit Cloudflare Tunnels** テンプレートを選択
3. 追加で `Zone > DNS > Edit` パーミッションを付与（自動DNS登録に必要）
4. 対象リソースを必要なアカウント/ゾーンに限定
5. トークンを発行してメモしておく（再表示不可）

> 📝 トークンはセットアップJobが Cloudflare Tunnel 作成・構成・DNS登録をすべて自動で行うためだけに使用します。

### 2. `.env` を作成

```bash
cp .env.example .env
nano .env
```

例：
```env
HEADSCALE_DOMAIN=headscale.yourdomain.com
NAMESPACE=headscale
STORAGE_CLASS=longhorn
STORAGE_SIZE=1Gi
TZ=Asia/Tokyo

CLOUDFLARE_API_TOKEN=v1.0_xxxxxxxxx
# 任意（複数アカウント利用時など）。空欄のままなら自動検出されます。
CLOUDFLARE_ACCOUNT_ID=
# 任意：自動解決がうまくいかない場合に指定。空欄のままで自動検出。
CLOUDFLARE_ZONE_ID=
# 任意：トンネル名を変えたい場合
CLOUDFLARE_TUNNEL_NAME=headscale-k8s-tunnel
```

### 3. デプロイを実行

```bash
./deploy.sh
```

スクリプトが以下を自動実行：
- Namespaceの作成
- HeadscaleのConfigMap/PVC/Deployment/Service展開
- Cloudflared Deployment と Setup Job の展開
- Setup Job が Cloudflare API を呼び出し、トンネル作成/取得・ConfigMap/Secret更新・DNS CNAME登録をすべて自動化

### 4. ジョブとポッドの状態確認

```bash
kubectl get pods -n headscale

# 出力例：
# NAME                        READY   STATUS    RESTARTS   AGE
# headscale-7f95847f86-xxxxx   1/1     Running   0          2m
# cloudflared-6b44966-xxxxx    1/1     Running   0          1m
# cloudflared-5cb74cb-xxxxx    1/1     Running   0          1m
# cloudflared-setup-xxxxx      0/1     Completed 0          2m
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
# Unauthorized: Failed to get tunnel
```

原因と対策：
- `CLOUDFLARE_API_TOKEN` の権限不足 → `Cloudflare Tunnel` Edit / `Account Settings` Read / `DNS` Edit が付与されているか確認
- `cloudflared-setup` Job が失敗 → `kubectl logs job/cloudflared-setup -n headscale` で詳細を確認
- 既存トンネルの状態がおかしい → Cloudflareダッシュボードで同名トンネルを削除して再実行（Jobが再作成可能）

### ドメインにアクセスできない

```bash
# DNS設定確認
nslookup headscale.yourdomain.com

# Tunnel設定確認（任意）
cloudflared tunnel info headscale-k8s-tunnel
```

確認項目：
- [ ] `cloudflared-setup` Job が CNAME レコードを作成できている（Cloudflareダッシュボードまたは Job ログで確認）
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
- Cloudflare APIトークンは機密情報です
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