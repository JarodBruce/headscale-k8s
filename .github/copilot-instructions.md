# 目的
Kubernetes (k8s) クラスタ上にHeadscaleをデプロイしたい。

# 前提条件
* デプロイ先のk8sクラスタはローカルネットワーク（自宅など）にあり、ルーターのポート開放はできない（または、したくない）。
* Headscaleへの外部からのアクセス（コントロールプレーンの通信）は、Cloudflare Tunnel (cloudflared) を利用して行う。
* Headscaleの管理には、 `https://headscale.example.com` のような独自ドメインを使用する。
* .envを作成しcloudflaredとドメインについてはそこに記述し、デプロイ時(./deploy.sh)に書き込むものとする。
* ネームスペースは新規作成し、`headscale` とする。

# 必須要件
1.  **Headscale設定:**
    * `server_url` を `https://headscale.example.com` （独自ドメイン）に設定する。
    * 内蔵DERPサーバーは無効化（`derp.server.enabled: false`）し、Tailscale公式のDERPサーバーを利用する設定にする。
    * データ（`db.sqlite`）と設定（`config.yaml`）は、PersistentVolume (PV/PVC) を使用して永続化する。
2.  **k8sアーキテクチャ:**
    * Headscale本体はk8sのDeploymentとして実行する。
    * Headscaleへのアクセス用にClusterIPタイプのServiceを作成する。
    * `config.yaml` はConfigMapとしてマウントする。
3.  **Cloudflare Tunnel設定:**
    * `cloudflared` をk8s内で別のDeploymentとして実行する。
    * この`cloudflared`が、`headscale.example.com` へのトラフィックを、上記で作成したHeadscaleのClusterIP Service（例: `http://headscale-service.default.svc.cluster.local:8080`）に転送するように設定する。

# 成果物
上記構成を実現するための、以下の具体的なYAMLマニフェスト例、またはHelmチャート（`headscale/headscale`）を使用する場合の `values.yaml` の設定例を教えてください。

1.  Headscale用の `config.yaml` の内容（ConfigMap用）。
2.  Headscaleの `Deployment`, `Service`, `PersistentVolumeClaim` のマニフェスト例。
3.  Cloudflare Tunnel (cloudflared) をk8s内で実行するための `Deployment` と `ConfigMap`（または `cloudflared` のHelmチャートの `values.yaml`）の設定例。
3.  Cloudflare の設定に関してはAccount APIを用いてpodが自ら構成を変更して欲しい