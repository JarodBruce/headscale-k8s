# GitHub Copilot Instructions for headscale-k8s

## 1. このリポジトリについて (About This Repository)

このリポジトリは、Kubernetes (k8s) クラスター上で **Headscale**（セルフホストVPN）と **Cloudflare Tunnel (`cloudflared`)** を管理・運用します。

主な目的は、**ポート解放を一切行わず**、これらのトンネリング技術を活用して、外部ユーザーや管理者が内部サービスへ**安全かつ限定的なアクセス**を行えるようにすることです。

## 2. 技術スタック (Technical Stack)

* **オーケストレーション:** Kubernetes (k8s)
* **VPNコントロールプレーン:** Headscale
* **VPNデータプレーン:** Tailscale (クライアント)
* **セキュアトンネル:** Cloudflare Tunnel (`cloudflared`)
* **IaC / マニフェスト:** Kubernetes YAML (後述のファイル構成)
* **設定管理:** `.env` ファイルによる環境変数管理

## 3. 重要な概念とルール (Key Concepts & Rules)

### 1. マニフェストと設定の管理
* **ファイル構成:** Kubernetes マニフェストは `k8s/` ディレクトリ配下に配置します。
    * `k8s/cloudflare.yaml`: `cloudflared` に関連する全てのマニフェスト（Deployment, Secret, ConfigMapなど）をこのファイルにまとめます。
    * `k8s/headscale.yaml`: Headscale に関連する全てのマニフェストをこのファイルにまとめます。
* **`.env` の使用:** 設定値や機密情報は、リポジトリルートの **`.env` ファイルに集約**します。Copilotは、これらの変数が `.env` から読み込まれ、k8sマニフェスト（特にSecretやConfigMap）に注入されることを前提としてください。
    * **管理対象の変数 (例):**
        * `NAMESPACE`: (最重要) リソースをデプロイする名前空間。
        * `HEADSCALE_SERVER_URL`: Headscaleのドメイン。
        * `CLOUDFLARE_TOKEN`: Cloudflare Tunnel のトークン。
        * (その他、各種APIキーやドメイン名)
* **Namespaceの適用:** **`k8s/cloudflare.yaml`** と **`k8s/headscale.yaml`** 内の全てのリソース（`Secret` や `Deployment`、`Namespace` 自体の定義を除く `ServiceAccount` や `RoleBinding` など）は、`.env` で指定された `NAMESPACE` 変数を `metadata.namespace` フィールドで参照する必要があります。
* **接続テスト用pod:** `k8s/test-pod.yaml` は、Headscale ネットワークへの接続テスト用に提供されるシンプルな Pod マニフェストです。このPodがHeadscaleネットワークに参加し、Headscaleサーバーにpingできることを目指してください。

### 2. セキュリティとアクセス
* **ポート公開の禁止:** ファイアウォールでインバウンドポートを開放する必要があるソリューション（例: NodePort, LoadBalancer）を提案**しないでください**。すべてのアクセスはHeadscaleまたはCloudflare Tunnelを経由する必要があります。
* **Headscale ACL:** Headscaleのアクセス制御に関する変更を提案する際は、**常に厳格なHeadscale ACL** (`acl.json` / HCL形式) を優先してください。アクセスは、そのユーザーやグループに必要な最小限の宛先ポートに限定する必要があります。
* **Headscale認証:** 外部ユーザー（友人など）には **Headscale 事前認証キー (Pre-Auth Keys)** を使用します。ゲストアクセスにOIDC等の複雑なユーザーアカウント連携を要求するソリューションを提案しないでください。

## 4. 回答の指針 (How to Answer)

* **コンテキストの意識:** 常に「ポート解放なし」「Headscale/Cloudflared優先」「.env管理」「指定Namespace」という前提を考慮してください。
* **具体例:** 解決策を提案する際は、`.env` ファイルの変数定義例や、`k8s/cloudflare.yaml` または `k8s/headscale.yaml` に記述するマニフェストの具体例（YAML形式）を提供してください。
* **主要ファイルへの言及:** デプロイに関する文脈では、`k8s/cloudflare.yaml`, `k8s/headscale.yaml`, `.env` ファイルへの言及を優先してください。アクセス制御については `acl.json` (HCL) に言及してください。

## 5. 避けるべきこと (What to Avoid)

* 明確に求められない限り、代替のVPNソリューション (OpenVPN, 素のWireGuard, SoftEtherなど) を推奨しないでください。Headscaleの採用は意図的なものです。
* 設定値をYAMLファイル内にハードコーディングする提案は避けてください。（`.env` の使用を促してください）
* `default` ネームスペースにリソースを作成するようなマニフェストを提案しないでください。