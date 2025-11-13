# Headscale on Kubernetes with Cloudflare Tunnel

このプロジェクトは、Kubernetes上にHeadscaleをデプロイし、Cloudflare Tunnelを使用して外部からアクセス可能にするための設定とスクリプトを提供します。

## 概要

- **Headscale**: オープンソースのTailscaleコントロールプレーン実装
- **Cloudflare Tunnel**: ローカルネットワークからインターネットへの安全なトンネル
- **Kubernetes**: コンテナオーケストレーションプラットフォーム

## アーキテクチャ

```
Internet → Cloudflare Edge → Cloudflare Tunnel → Kubernetes Cluster → Headscale
                                    ↓
                            (cloudflared pod)
                                    ↓
                            (headscale service)
                                    ↓
                            (headscale pod)
```

## 前提条件

- Kubernetesクラスタ（ローカルまたはクラウド）
- `kubectl`がインストールされ、クラスタに接続可能
- Cloudflareアカウント
- 独自ドメイン（Cloudflareで管理）
- Cloudflare Zero Trustダッシュボードへのアクセス

## セットアップ手順

### 1. Cloudflare Tunnelの作成

1. [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)にログイン
2. `Access` → `Tunnels`に移動
3. `Create a tunnel`をクリック
4. トンネル名を入力（例: `headscale-tunnel`）
5. トンネルトークンとIDを保存

### 2. プロジェクトのクローン

```bash
git clone <repository-url>
cd headscale
```

### 3. 環境変数の設定

```bash
cp .env.example .env
```

`.env`ファイルを編集して、以下の値を設定：

```env
# Headscale Domain Configuration
HEADSCALE_DOMAIN=headscale.your-domain.com

# Cloudflare Tunnel Configuration
CLOUDFLARE_TUNNEL_ID=<your-tunnel-id>
CLOUDFLARE_TUNNEL_TOKEN=<your-tunnel-token>

# その他の設定（必要に応じて調整）
```

### 4. デプロイ

```bash
chmod +x deploy.sh
./deploy.sh
```

スクリプトは以下を実行します：
- Namespace `headscale`の作成
- Headscale ConfigMap、PVC、Service、Deploymentの作成
- Cloudflare Tunnel Secret、ConfigMap、Deploymentの作成
- デプロイメントの状態確認

### 5. Cloudflareでのルーティング設定

Cloudflare Zero Trustダッシュボードで：
1. 作成したトンネルを選択
2. `Public Hostname`タブで`Add a public hostname`をクリック
3. 以下を設定：
   - Subdomain: `headscale`
   - Domain: `your-domain.com`
   - Path: （空白）
   - Service: `http://headscale-service.headscale.svc.cluster.local:8080`
4. 保存

## 使用方法

### ユーザーの作成

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale users create myuser
```

### Pre-authentication keyの生成

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale preauthkeys create --user myuser
```

### クライアントの接続

生成されたpre-auth keyを使用してTailscaleクライアントを接続：

```bash
tailscale up --login-server=https://headscale.your-domain.com --authkey=<pre-auth-key>
```

### ノードの確認

```bash
kubectl exec -it deploy/headscale -n headscale -- headscale nodes list
```

## 管理コマンド

### ログの確認

```bash
# Headscaleのログ
kubectl logs -f deploy/headscale -n headscale

# Cloudflare Tunnelのログ
kubectl logs -f deploy/cloudflared -n headscale
```

### Podの状態確認

```bash
kubectl get pods -n headscale
```

### 設定の更新

1. ConfigMapを編集：
```bash
kubectl edit configmap headscale-config -n headscale
```

2. Deploymentを再起動：
```bash
kubectl rollout restart deployment/headscale -n headscale
```

## アンインストール

```bash
chmod +x undeploy.sh
./undeploy.sh
```

このスクリプトは以下のオプションを提供します：
- リソースの削除
- PersistentVolumeClaimの保持/削除
- Namespaceの保持/削除

## トラブルシューティング

### Headscaleが起動しない

```bash
# Podのイベントを確認
kubectl describe pod -l app=headscale -n headscale

# ログを確認
kubectl logs -l app=headscale -n headscale --previous
```

### Cloudflare Tunnelが接続できない

1. トークンが正しいか確認
2. Cloudflareダッシュボードでトンネルのステータスを確認
3. cloudflaredのログを確認：
```bash
kubectl logs -l app=cloudflared -n headscale
```

### 外部からアクセスできない

1. DNSレコードが正しく設定されているか確認
2. Cloudflare Tunnelのpublic hostnameが正しく設定されているか確認
3. Headscaleサービスが正常に動作しているか確認：
```bash
kubectl get svc -n headscale
kubectl exec -it deploy/headscale -n headscale -- curl -s http://localhost:8080/health
```

## ファイル構成

```
headscale/
├── .env.example                          # 環境変数のテンプレート
├── .github/
│   └── copilot-instructions.md          # プロジェクトの要件
├── deploy.sh                             # デプロイスクリプト
├── undeploy.sh                           # アンインストールスクリプト
├── README.md                             # このファイル
└── k8s/
    ├── 00-namespace.yaml                 # Namespace定義
    ├── headscale/
    │   ├── 01-configmap.yaml            # Headscale設定
    │   ├── 02-pvc.yaml                  # PersistentVolumeClaim
    │   ├── 03-service.yaml              # ClusterIP Service
    │   └── 04-deployment.yaml           # Headscale Deployment
    └── cloudflared/
        ├── 01-secret.yaml.template      # Tunnelトークン（テンプレート）
        ├── 02-configmap.yaml.template   # Cloudflared設定（テンプレート）
        └── 03-deployment.yaml           # Cloudflared Deployment
```

## セキュリティに関する注意事項

- `.env`ファイルには機密情報が含まれます。Gitにコミットしないでください。
- Cloudflare Tunnelトークンは安全に管理してください。
- 本番環境では、より強固なRBACとNetworkPolicyの設定を検討してください。
- 定期的にHeadscaleとcloudflaredのイメージを更新してください。

## リソース要件

デフォルト設定：
- **Headscale**: 128Mi〜512Mi RAM, 100m〜500m CPU
- **Cloudflared**: 128Mi〜256Mi RAM, 100m〜500m CPU  
- **Storage**: 1Gi（調整可能）

## 関連リンク

- [Headscale公式ドキュメント](https://headscale.net/)
- [Cloudflare Tunnel ドキュメント](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Tailscale クライアント](https://tailscale.com/download)

## ライセンス

このプロジェクトの設定ファイルはMITライセンスで提供されます。
Headscale自体のライセンスについては[Headscaleリポジトリ](https://github.com/juanfont/headscale)を参照してください。

## サポート

問題が発生した場合は、以下を確認してください：
1. このREADMEのトラブルシューティングセクション
2. Headscale公式ドキュメント
3. プロジェクトのIssuesセクション