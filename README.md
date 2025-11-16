# headscale-k8s

Kubernetes クラスタ上に Headscale と Cloudflare Tunnel (cloudflared) をデプロイし、**ポート開放なし**で外部アクセスを確立するためのマニフェスト集です。設定値はすべて `.env` に集約し、`envsubst` でマニフェストへ注入します。

## 概要

- Headscale: セルフホストの Tailscale コントロールプレーン。`k8s/headscale.yaml` に Namespace/ConfigMap/PVC/Deployment/Service をまとめています。
- Cloudflared: Cloudflare Tunnel コンテナ。`k8s/cloudflare.yaml` に ConfigMap/Secret/ServiceAccount/Deployment をまとめています。
- `.env`/`.env.example`: すべての変数をここで管理し、Git には平文を残しません。

## 必要条件

- Kubernetes 1.24+（`ReadWriteOnce` に対応した StorageClass 必須）
- `kubectl` と `envsubst` (`gettext` パッケージ)
- Cloudflare アカウントと DNS ゾーン（Tunnel を発行できる権限）
- `cloudflared` CLI（トンネル作成と資格情報取得に使用）

## `.env` の準備手順

1. 雛形をコピーして編集します。

   ```bash
   cp .env.example .env
   ${EDITOR:-nano} .env
   ```

2. Headscale 用変数を設定します。
   - `HEADSCALE_SERVER_URL`: Cloudflare 側で公開するホスト名 (例: `https://headscale.example.com`)
   - `HEADSCALE_DNS_NAMESERVER_1/2`: Tailscale クライアントへ配布したい DNS
   - `HEADSCALE_ACL_*`: `acl.json` に反映される ACL ルール

3. Cloudflare Tunnel 用変数を取得します（以下ではトンネル名 `headscale` を例にします）。

   **(1) Cloudflare へログインしトンネルを作成**

   ```bash
   cloudflared login
   cloudflared tunnel create headscale
   cloudflared tunnel list
   ```

   - `cloudflared tunnel list` の出力から `CLOUDFLARE_TUNNEL_ID` と `CLOUDFLARE_ACCOUNT_ID` を控えます。
   - `~/.cloudflared/<トンネルID>.json` が生成されるので、このファイルを `CLOUDFLARE_TUNNEL_CREDENTIALS_JSON` にコピーします（1 行、もしくはエスケープした JSON として貼り付けてください）。

   **(2) トンネルシークレットとトークンを取得/生成**

   ```bash
   # credentials.json 内の "TunnelSecret" をそのまま再利用する場合
   jq -r '.TunnelSecret' ~/.cloudflared/${CLOUDFLARE_TUNNEL_ID}.json

   # 独自に生成する場合
   head -c32 /dev/urandom | base64
   ```

   - 上記で得た値を `CLOUDFLARE_TUNNEL_SECRET` に設定します。
   - API トークンは `cloudflared tunnel token headscale` で取得し、`CLOUDFLARE_TUNNEL_TOKEN` に貼り付けます。

    **(3) DNS とホスト名**

    - `HEADSCALE_SERVER_URL` と `CLOUDFLARE_INGRESS_HOST` は同じホスト名を指定し、Headscale のリダイレクト URL と一致させます。
    - ダッシュボードが使えない場合でも、CLI だけで CNAME を作成できます。

       ```bash
       # 例: headscale トンネルを headscale.example.com に関連付ける
       cloudflared tunnel route dns headscale headscale.example.com

       # 登録済みルートの確認
       cloudflared tunnel route list headscale
       ```

       上記コマンドは Cloudflare API を直接呼び出し、ゾーン内に CNAME（`<hostname> ➜ <tunnel>.cfargotunnel.com`）を自動作成します。必要に応じて `--overwrite-dns` を付与すると既存レコードを置き換えられます。

4. `.env` を保存したら、機微情報が正しく埋まっているか再確認してください。`deploy.sh` は `CLOUDFLARE_TUNNEL_SECRET` と `CLOUDFLARE_TUNNEL_CREDENTIALS_JSON` が空だと中断します。

## デプロイ手順

1. 一度だけ実行権限を付与します。

   ```bash
   chmod +x deploy.sh
   ```

2. スクリプトを実行して Namespace/Headscale/Cloudflared をまとめて適用します。

   ```bash
   ./deploy.sh
   ```

   - スクリプトは `.env` を `source` し、`envsubst` 経由で `k8s/headscale.yaml` と `k8s/cloudflare.yaml` を適用します。
   - 実行後に `kubectl get pods -n ${NAMESPACE}` の結果を表示して完了を確認できます。

## 動作確認と運用

- Pod の状態確認: `kubectl get pods -n ${NAMESPACE}`
- Cloudflared ログ: `kubectl logs -l app=cloudflared -n ${NAMESPACE} --tail=200`
- Headscale API 健康チェック: `kubectl port-forward -n ${NAMESPACE} svc/headscale 8080:8080` で `http://localhost:8080/healthz`
- ACL を変更したい場合は `k8s/headscale.yaml` 内の `headscale-acl` ConfigMap を更新し、`kubectl apply` で再適用してください。
- `headscale-data` PVC に Headscale DB が保存されます。スナップショットや `kubectl cp` で定期バックアップを取得してください。

## 参考ファイル

- `k8s/headscale.yaml` — Namespace、ConfigMap、PVC、Deployment、Service を定義。
- `k8s/cloudflare.yaml` — Cloudflared 用 ConfigMap/Secret/ServiceAccount/Deployment を定義。
- `.env.example` — 必須変数の雛形。`.env` にコピーしてから編集してください。
