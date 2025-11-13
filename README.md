# Headscale on Kubernetes with Cloudflare Tunnel

このプロジェクトは、Kubernetes上にHeadscaleをデプロイし、Cloudflare Tunnelを使用して外部からアクセス可能にするための設定とスクリプトを提供します。

---

## 🚀 今すぐ始める

**初めての方は [QUICKSTART.md](QUICKSTART.md) をご覧ください！**

5分でデプロイできる簡単なステップバイステップガイドです。

---

## 📖 ドキュメント構成

| ドキュメント | 用途 | 対象 |
|------------|------|------|
| **[QUICKSTART.md](QUICKSTART.md)** | 最速でデプロイ | 初心者・すぐに始めたい方 |
| **README.md（このファイル）** | 詳細な説明と全体像 | 全体を理解したい方 |
| **[WEBSOCKET_FIX.md](WEBSOCKET_FIX.md)** | WebSocket問題の解決 | 警告が出た方 |
| **[k8s/cloudflared/alternative-config/README.md](k8s/cloudflared/alternative-config/README.md)** | 設定ファイルベースの詳細 | 上級者・カスタマイズしたい方 |

---

## 🚨 重要: WebSocket サポートについて

Headscale は Tailscale プロトコル (TS2021/Noise) を使用しており、**WebSocket サポートが必須**です。

適切に設定されていない場合、以下の警告が表示されます：
```
WRN No Upgrade header in TS2021 request. If headscale is behind a reverse proxy, 
    make sure it is configured to pass WebSockets through.
```

この問題を解決するため、**2つのデプロイ方法**を提供しています：

1. **トークンベース** (`deploy.sh`) - シンプルだが、Cloudflareダッシュボードで手動設定が必要
2. **設定ファイルベース** (`deploy-alternative.sh`) - **推奨** - WebSocket対応が組み込み済み

詳細は [WebSocket サポートの設定](#websocket-サポートの設定) セクションを参照してください。

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

### 方法を選択

以下の2つの方法から選択してください：

| 方法 | 難易度 | WebSocket | 推奨度 |
|------|--------|-----------|--------|
| **方法A: トークンベース** | ⭐ 簡単 | ⚠️ 手動設定必要 | 初心者向け |
| **方法B: 設定ファイルベース** | ⭐⭐ 中級 | ✅ 自動対応 | **推奨** |

---

## 方法A: トークンベースデプロイ

### 1. Cloudflare Tunnelの作成

1. [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)にログイン
2. `Access` → `Tunnels`に移動
3. `Create a tunnel`をクリック
4. トンネル名を入力（例: `headscale-tunnel`）
5. インストール方法で「Cloudflared」を選択
6. 表示されるトークンをコピー（`cloudflared tunnel run --token eyJ...` の形式）
</text>

### 2. プロジェクトの準備

```bash
git clone <repository-url>
cd headscale
```

### 3. 環境変数の設定（トークンベース）

```bash
cp .env.example .env
```

`.env`ファイルを編集して、以下の値を設定：

```env
# Headscale Domain Configuration
HEADSCALE_DOMAIN=headscale.your-domain.com

# Cloudflare Tunnel Configuration (トークンベース)
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoiODQ2ZWFm...（トークン全体をペースト）

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
   - Subdomain: `headscale`（または任意）
   - Domain: `your-domain.com`
   - Path: （空白）
   - Type: `HTTP`
   - URL: `headscale-service.headscale.svc.cluster.local:8080`
4. 保存

**注意**: トンネルを作成してトークンを取得した後、上記の Public Hostname 設定を行ってください。

### 6. WebSocket を有効化（重要！）

Cloudflare Zero Trustダッシュボードで：
1. 作成した Public Hostname を編集
2. **Additional application settings** を展開
3. **WebSocket** トグルを **ON** に設定 ✅
4. 保存

これを行わないと、Tailscale クライアントが接続できません。

詳細は [`WEBSOCKET_FIX.md`](WEBSOCKET_FIX.md) を参照してください。

---

## 方法B: 設定ファイルベースデプロイ（推奨）

この方法では、WebSocket サポートが設定ファイルに組み込まれているため、ダッシュボードでの手動設定が不要です。

### 1. Cloudflare Tunnelの作成（方法Aと同じ）

上記の [方法A - 1. Cloudflare Tunnelの作成](#1-cloudflare-tunnelの作成) と同じ手順でトンネルを作成します。

### 2. トンネル認証情報の取得

以下のいずれかの方法で認証情報を取得：

#### オプション1: cloudflared CLI を使用

```bash
# トンネルIDを確認
cloudflared tunnel list

# 認証情報ファイルを確認
cat ~/.cloudflared/<tunnel-id>.json
```

JSONファイルに以下が含まれています：
- `AccountTag` → `CLOUDFLARE_ACCOUNT_ID`
- `TunnelSecret` → `CLOUDFLARE_TUNNEL_SECRET`
- `TunnelID` → `CLOUDFLARE_TUNNEL_ID`

#### オプション2: Cloudflareダッシュボードから

1. Tunnel ID は、ダッシュボードのトンネル詳細画面のURLから取得できます
2. `TunnelSecret` と `AccountTag` は、トンネル作成時に表示されるJSONから取得

### 3. 環境変数の設定（設定ファイルベース）

```bash
cp .env.example .env
```

`.env` ファイルを編集して、**以下の値を設定**：

```env
# Headscale Domain
HEADSCALE_DOMAIN=headscale.your-domain.com

# 設定ファイルベース用の認証情報
CLOUDFLARE_TUNNEL_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
CLOUDFLARE_TUNNEL_SECRET=your-tunnel-secret-here
CLOUDFLARE_ACCOUNT_ID=your-account-id-here
CLOUDFLARE_DOMAIN=headscale.your-domain.com
```

### 4. デプロイ（設定ファイルベース）

```bash
chmod +x deploy-alternative.sh
./deploy-alternative.sh
```

このスクリプトは、WebSocket サポートが組み込まれた設定ファイルを使用してデプロイします。

### 5. Cloudflareでのルーティング設定

方法Aと同じ手順で Public Hostname を設定しますが、**WebSocket の手動設定は不要**です（設定ファイルに含まれています）。

---

## WebSocket サポートの設定

### 確認方法

デプロイ後、以下のコマンドでWebSocket警告がないか確認：

```bash
kubectl logs -f deploy/headscale -n headscale
```

**警告が表示される場合**:
- 方法A（トークンベース）：[`WEBSOCKET_FIX.md`](WEBSOCKET_FIX.md) を参照
- 方法B（設定ファイルベース）：[`k8s/cloudflared/alternative-config/README.md`](k8s/cloudflared/alternative-config/README.md) を参照

### テストスクリプト

```bash
chmod +x test-websocket.sh
./test-websocket.sh
```

---

## 共通の使用方法

どちらの方法でデプロイしても、以下の使用方法は共通です。

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

### WebSocket 警告が表示される

```
WRN No Upgrade header in TS2021 request...
```

**解決方法**:
- **方法A（トークンベース）を使用している場合**: [`WEBSOCKET_FIX.md`](WEBSOCKET_FIX.md) を参照してCloudflareダッシュボードでWebSocketを有効化
- **方法B（設定ファイルベース）を使用している場合**: 設定が正しく適用されているか確認：
  ```bash
  kubectl describe configmap cloudflared-config -n headscale
  ```

### 外部からアクセスできない

1. DNSレコードが正しく設定されているか確認
2. Cloudflare Tunnelのpublic hostnameが正しく設定されているか確認
3. **WebSocketサポートが有効**になっているか確認
4. Headscaleサービスが正常に動作しているか確認：
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
├── deploy.sh                             # 方法A: トークンベースデプロイ
├── deploy-alternative.sh                 # 方法B: 設定ファイルベースデプロイ（推奨）
├── test-websocket.sh                     # WebSocket設定テストスクリプト
├── README.md                             # このファイル（詳細ドキュメント）
├── QUICKSTART.md                         # クイックスタートガイド（初心者向け）
├── WEBSOCKET_FIX.md                      # WebSocket問題のクイックフィックスガイド
└── k8s/
    ├── 00-namespace.yaml                 # Namespace定義
    ├── headscale/
    │   ├── 01-configmap.yaml            # Headscale設定
    │   ├── 02-pvc.yaml                  # PersistentVolumeClaim
    │   ├── 03-service.yaml              # ClusterIP Service
    │   └── 04-deployment.yaml           # Headscale Deployment
    └── cloudflared/
        ├── 01-secret.yaml.template      # 方法A: Tunnelトークン
        ├── 03-deployment.yaml           # 方法A: Cloudflared Deployment
        └── alternative-config/          # 方法B: WebSocket対応設定
            ├── README.md                # 詳細な設定ガイド
            ├── 01-secret.yaml.template  # トンネル認証情報
            ├── 02-configmap.yaml.template # WebSocket設定を含む設定ファイル
            └── 03-deployment.yaml       # 設定ファイルベースのDeployment
```

## セキュリティに関する注意事項

- `.env`ファイルには機密情報が含まれます。Gitにコミットしないでください。
- Cloudflare Tunnelトークンは安全に管理してください。
- 本番環境では、より強固なRBACとNetworkPolicyの設定を検討してください。
- 定期的にHeadscaleとcloudflaredのイメージを更新してください。

## リソース要件

デフォルト設定：
- **Headscale**: 128Mi〜512Mi RAM, 100m〜500m CPU
- **Cloudflared**: 64Mi〜128Mi RAM, 50m〜200m CPU  
- **Storage**: 1Gi（調整可能）

## クイックスタートチートシート

### 方法A（トークンベース）
```bash
# 1. トンネルを作成してトークンを取得
# 2. .env を編集（CLOUDFLARE_TUNNEL_TOKEN のみ）
cp .env.example .env
# 3. デプロイ
./deploy.sh
# 4. Cloudflareダッシュボードで WebSocket を有効化（重要！）
# 詳細: WEBSOCKET_FIX.md
```

### 方法B（設定ファイルベース - 推奨）
```bash
# 1. トンネルを作成して認証情報を取得
cloudflared tunnel list
cat ~/.cloudflared/<tunnel-id>.json
# 2. .env を編集（TUNNEL_ID, TUNNEL_SECRET, ACCOUNT_ID）
cp .env.example .env
# 3. デプロイ（WebSocket自動対応）
chmod +x deploy-alternative.sh
./deploy-alternative.sh
# 4. テスト
./test-websocket.sh
```

## 関連リンク

- [Headscale公式ドキュメント](https://headscale.net/)
- [Cloudflare Tunnel ドキュメント](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Tailscale クライアント](https://tailscale.com/download)
- [WebSocket問題のクイックフィックス](WEBSOCKET_FIX.md)
- [設定ファイルベース詳細ガイド](k8s/cloudflared/alternative-config/README.md)

## ライセンス

このプロジェクトの設定ファイルはMITライセンスで提供されます。
Headscale自体のライセンスについては[Headscaleリポジトリ](https://github.com/juanfont/headscale)を参照してください。

## サポート

問題が発生した場合は、以下を確認してください：

1. **まず試す**: [`QUICKSTART.md`](QUICKSTART.md) のトラブルシューティングセクション
2. **WebSocket警告が出る**: [`WEBSOCKET_FIX.md`](WEBSOCKET_FIX.md)
3. このREADMEのトラブルシューティングセクション
4. [設定ファイルベース詳細ガイド](k8s/cloudflared/alternative-config/README.md)
5. テストスクリプト実行: `./test-websocket.sh`
6. Headscale公式ドキュメント
7. プロジェクトのIssuesセクション

## まとめ

- **初めての方**: まず [`QUICKSTART.md`](QUICKSTART.md) を参照
- **WebSocket警告**: [`WEBSOCKET_FIX.md`](WEBSOCKET_FIX.md) を参照
- **詳細なカスタマイズ**: このREADMEと [alternative-config/README.md](k8s/cloudflared/alternative-config/README.md)

Happy Headscaling! 🎉
