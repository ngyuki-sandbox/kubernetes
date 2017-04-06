# Kubernetes をオンプレで使ってみた

**2017/04/06 頃に書いたもの、元は社内の Lodge にあります**

- https://kubernetes.io/
    - 公式サイト
- https://kubernetes.io/docs/getting-started-guides/centos/centos_manual_config/
    - CentOS へのセットアップ方法
- https://kubernetes.io/docs/resources-reference/v1.6/
    - Pod や Service の YANL のリファレンス
- http://knowledge.sakura.ad.jp/tech/3681/
    - ググって一番上に来たサイト、手順はちょっと古い
- http://qiita.com/ocadaruma/items/5a00f87f56e295d3553c
    - コンポーネントやリソースに説明がわかりやすい

## 概要

クラスタを制御する Master サーバと、Master と通信してコンテナを制御する Node サーバで構成される。

それぞれ下記のコンポートンで構成される。

- Master
    - etcd
    - kube-apiserver
    - kube-controller-manager
    - kube-scheduler
- Node
    - docker
    - flanneld
    - kube-proxy
    - kubelet

CentOS 7 には、概ね下記の通りで構築できる。

- https://kubernetes.io/docs/getting-started-guides/centos/centos_manual_config/

## yum リポジトリ

[virt7-docker-common-release](http://cbs.centos.org/repos/virt7-docker-common-release/x86_64/os/) というリポジトリを使っているだけれども、素のままでも yum でインストールできるし、素のままの方が新しい版だった。

[virt7-docker-common-candidate](https://cbs.centos.org/repos/virt7-docker-common-candidate/x86_64/os/) ならもっと新しい版になるようだけれども？

リポジトリごとのバージョンは下記の通り。

```sh
# extras
docker        2:1.12.6-11.el7.centos
etcd          3.1.0-2.el7
flannel       0.7.0-1.el7
kubernetes    1.5.2-0.2.gitc55cf2b.el7

# virt7-docker-common-release
docker        1.6.2-4.gitc3ca5bb.el7
etcd          2.0.9-1.el7
flannel       0.2.0-7.el7
kubernetes    1.1.0-0.4.git2bfa9a1.el7

# virt7-docker-common-candidate
docker        1.12.6-14.gitf499e8b.el7
docker-latest 1.13-27.git6cd0bbe.el7
kubernetes    1.5.2-2.el7
```

extras で十分だと思うので素のままで extras を使う。

## Master サーバ

kubernetes-master と etcd をインストールする。

元の手順だと kubernetes と flannel を入れているけど、flannel はノードを超えたコンテナ間の通信のためのものなので Master には要らないと思う（もし Master からもサービスのポートにアクセスする必要があるなら必要だろうけど、必要？）

また、kubernetes をインストールすると kubernetes からの依存で kubernetes-node もインストールされ、そこからさらに docker もインストールされる。Master には docker 不要でしょう。

```sh
yum install kubernetes-master etcd
```

次のように設定ファイルを修正する。

**/etc/etcd/etcd.conf**

```sh
# etcd がクライアントからの接続をリッスンするアドレス
# Node サーバの flanneld からも接続するので localhost だとダメ
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"

# たぶん etcd をクラスタ化しなければ不要？
# 0.0.0.0 だとダメな気がするけど？
# etcd のドキュメント見てもこれが何に使われているのかよくわからない
ETCD_ADVERTISE_CLIENT_URLS="http://0.0.0.0:2379"
```

**/etc/kubernetes/config**

```sh
# Master の apiserver の URL を指定する
# このファイルは kubernetes の複数のコンポーネントで参照される
KUBE_MASTER="--master=http://master:8080"
```

**/etc/kubernetes/apiserver**

```sh
# kube-apiserver のリッスンアドレス
# たぶん --insecure-bind-address が正しい
# たぶん --address は古い記法で後方互換のために残っているのではなかろうか
KUBE_API_ADDRESS="--address=0.0.0.0"

# これも --insecure-port が正しい気がする
KUBE_API_PORT="--port=8080"

# Node で実行する kubelet のポート（デフォルトのまま）
KUBELET_PORT="--kubelet-port=10250"

# etcd の URL
KUBE_ETCD_SERVERS="--etcd-servers=http://master:2379"

# kubernetes で作成したサービスが利用するアドレスレンジ（デフォルトのまま）
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"

# コメントアウトしておけば鍵とかを作る必要がない？
#KUBE_ADMISSION_CONTROL="--admission-control=..."
```

etcd を開始して flannel で作るオーバーレイネットワークの情報を保存する。

```sh
systemctl start etcd

etcdctl mkdir /kube-centos/network
etcdctl mk /kube-centos/network/config '{
  "Network": "172.30.0.0/16",
  "SubnetLen": 24,
  "Backend": {
    "Type": "vxlan"
  }
}'
```

サービスを開始する。

```sh
for SERVICES in etcd kube-apiserver kube-controller-manager kube-scheduler; do
    systemctl restart $SERVICES
    systemctl enable $SERVICES
    systemctl status $SERVICES
done
```

## Node サーバ

kubernetes-node flannel をインストールする。

元の手順だと kubernetes をインストールしているけど、たぶん kubernetes-node だけで十分。
Node サーバで kubectl を使いたければ kubernetes-client をインストールしても良いかも。

```sh
yum -y install kubernetes-node flannel
```

次のように設定ファイルを修正する。

**/etc/sysconfig/flanneld**

```sh
# etcd の URL
FLANNEL_ETCD_ENDPOINTS="http://master:2379"

# etcd の flannel 設定のプレフィックス
FLANNEL_ETCD_PREFIX="/kube-centos/network"

# 手順にはないけど Vagrant だとインタフェースを指定する必要がありそう
FLANNEL_OPTIONS="-iface=enp0s8"
```

**/etc/kubernetes/config**

```sh
# Master で設定した内容と同じ。
KUBE_MASTER="--master=http://master:8080"
```

**/etc/kubernetes/kubelet**

```sh
# kubelet のリッスンアドレス（デフォルト）
KUBELET_ADDRESS="--address=0.0.0.0"

# kubelet のポート番号（デフォルト）
KUBELET_PORT="--port=10250"

# kubelet が Master に伝えるホスト名
# 空ならサーバのホスト名そのまま
KUBELET_HOSTNAME="--hostname-override="

# apiserver の URL
# /etc/kubernetes/config と意味が重複している気がするんだけど
KUBELET_API_SERVER="--api-servers=http://master:8080"
```

サービスを開始する。

```sh
for SERVICES in kube-proxy kubelet flanneld docker; do
    systemctl restart $SERVICES
    systemctl enable $SERVICES
    systemctl status $SERVICES
done
```

flannel でそれっぽいインタフェースが作られている。

```sh
ip addr show dev flannel.1
# 5: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN 
#     link/ether 6e:c0:dc:87:00:0e brd ff:ff:ff:ff:ff:ff
#     inet 172.30.50.0/32 scope global flannel.1
#        valid_lft forever preferred_lft forever
#     inet6 fe80::6cc0:dcff:fe87:e/64 scope link 
#        valid_lft forever preferred_lft forever

ip -d link show dev flannel.1
# 5: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN mode DEFAULT 
#     link/ether 6e:c0:dc:87:00:0e brd ff:ff:ff:ff:ff:ff promiscuity 0 
#     vxlan id 1 local 192.168.121.65 dev enp0s8 srcport 0 0 dstport 8472 nolearning ageing 300 addrgenmode eui64 
```

docker のインタフェースは etcd に保存した flannel のサブネット帯になるが、これはどういう原理？
docker が flannel を認識して自動的にそうなるの？

```sh
ip addr show dev docker0
# 4: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN 
#     link/ether 02:42:06:c6:b0:98 brd ff:ff:ff:ff:ff:ff
#     inet 172.30.50.1/24 scope global docker0
#        valid_lft forever preferred_lft forever
```

クラスタが正しく組めていれば Master の kubectl コマンドでノードの一覧が表示できる。

```sh
kubectl get nodes
# NAME      STATUS    AGE
# sv01      Ready     11m
# sv02      Ready     4m
# sv03      Ready     1m
```

## Pod

Pod リソースとは複数のコンテナをまとめたもので、Pod の単位で必ず同じ Node に配置される。

以下の用に定義ファイルを作成し、kubectl コマンドで Pod の作成と確認を行なう。

**pod.yaml**

```sh
apiVersion: v1
kind: Pod                 # Podに関する設定ファイルであることを指定
metadata:                 # メタデータに関する情報を指定
  name: httpd             # Podの名前を指定
  labels:                 # Podに付与するラベルを指定
    app: httpd
spec:
  containers:
  - name: httpd           # コンテナ名を指定
    image: httpd          # コンテナを作成する際に使用するイメージを指定
    ports:
    - containerPort: 80   # コンテナに外部からアクセスできるポートを指定
```

Pod を作成する。

```sh
kubectl create -f pod.yaml
# pod "httpd" created

kubectl get pods
# NAME      READY     STATUS              RESTARTS   AGE
# httpd     0/1       ContainerCreating   0          3s

kubectl get pods
# NAME      READY     STATUS    RESTARTS   AGE
# httpd     1/1       Running   0          17s

kubectl get pod httpd -o yaml | grep -E 'podIP|nodeName'
#  nodeName: sv02
#  podIP: 172.30.65.2
```

sv02 で実行されているが、flanne のオーバーレイネットワークにより、どの Node からでもアクセスできる。

```sh
curl http://172.30.65.2/
```

Pod に中には下記のように exec で入ることができる。

```sh
kubectl exec -it httpd bash
```

Pod は複数のコンテナを含むことができるため、その場合はコンテナの名前も指定する必要がある(-c オプション)。

```sh
kubectl exec -it httpd -c httpd bash
```

Pod の削除は次のように行なう。

```sh
kubectl delete pod httpd
# pod "httpd" deleted

kubectl get pods
# No resources found.
```

## Service

Pod のポートは Pod を開始/停止するたびに変わるため、アドレスを固定するために Service リソースを使う。

**service.yaml**

```yaml
apiVersion: v1
kind: Service     # Serviceの定義であることを指定
metadata:
  name: httpd     # Service名を指定
spec:
  ports:
    - port: 80    # Serviceが使用するポート番号を指定
  selector:       # 対象とするPodをラベルで指定
    app: httpd
```

```sh
kubectl create -f pod.yaml
# pod "httpd" created

kubectl create -f service.yaml
# service "httpd" created

kubectl get pods
# NAME      READY     STATUS    RESTARTS   AGE
# httpd     1/1       Running   0          6s

kubectl get pod httpd -o yaml | grep -E 'podIP|nodeName'
#  nodeName: sv01
#  podIP: 172.30.63.2

kubectl get services
# NAME         CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
# httpd        10.254.84.59   <nodes>       80:32742/TCP   1h
# kubernetes   10.254.0.1     <none>        443/TCP        1d
```

Pod のポートと Service のポートのどちらでもアクセスできる。

```sh
curl 172.30.63.2
curl 10.254.84.59
```

と思ったけど、Pod が動いているサーバ（sv01）以外からは Service のポートではアクセスできなかった。
Service にも幾つかの種類があり、デフォルトは ClusterIP で、コンテナ間の通信だけに使用できるもの？

```sh
kubectl run centos --image=centos --rm --attach --restart=Never --command -- curl -s -m 1 10.254.84.59
# Waiting for pod default/centos to be running, status is Pending, pod ready: false
# <html><body><h1>It works!</h1></body></html>
# pod "centos" deleted
```

なお、サービスのポートは環境変数でも取得できる。

```sh
kubectl exec httpd env | grep HTTPD_SERVICE_
# HTTPD_SERVICE_HOST=10.254.84.59
# HTTPD_SERVICE_PORT=80
```

## Service NodePort

Service で NodePort というタイプを使えば Node サーバのポートを Pod のポートに転送できる。

**service.yaml**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: httpd
spec:
  type: NodePort      # サービスのタイプを指定
  ports:
    - port: 80
  selector:
    app: httpd
```

サービスを作り直します。

```sh
kubectl delete -f service.yaml
# service "httpd" deleted

kubectl create -f service.yaml
# service "httpd" create

kubectl get services
# NAME         CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# httpd        10.254.0.63   <nodes>       80:32742/TCP   32s
# kubernetes   10.254.0.1    <none>        443/TCP        1d
```

任意の Node サーバの 32742 ポートでアクセスできる（下記のアドレスは Node サーバのアドレス）。

```sh
curl http://192.168.121.65:32742/
curl http://192.168.121.66:32742/
curl http://192.168.121.67:32742/
```

## Deployment

Deployment を使えば Pod を複数展開できる。

**deployment.yaml**

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: httpd
spec:
  replicas: 3             # Pod のレプリカ数
  template:               # Pod のテンプレート
    metadata:
      labels:             # Pod に付与するラベル（Deployment のラベルにもなる）
        app: httpd
    spec:
      containers:
        - name: httpd
          image: httpd
```

```sh
kubectl create -f deployment.yaml 
# deployment "httpd" created

kubectl get deployments
# NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
# httpd     3         3         3            3           30s

kubectl get replicasets
# NAME               DESIRED   CURRENT   READY     AGE
# httpd-3128727596   3         3         3         1m

kubectl get pods
# NAME                     READY     STATUS    RESTARTS   AGE
# httpd-3128727596-5nndz   1/1       Running   0          1m
# httpd-3128727596-vs95b   1/1       Running   0          1m
# httpd-3128727596-zkf9q   1/1       Running   0          1m
```

Deployment から ReplicaSet というリソースが作られ、さらに Pod が作られる。

Deployment を作らずに ReplicaSet を直接作ることも出来るけど、Deployment ならローリングアップデートとかもできる。

## メモ

- minikube という仮想環境でシングル構成で kubernetes をお試し実行できるものがある
    - こっちで試せばよかったかも・・
- オンプレで自前で構築するのは辛そうなのでもし使うなら GKE とか OpenShift とかだろうか
- Service の LoadBalancer タイプ
    - NodePort と同じようなものだけどさらにクラウドプロバイダのロードバランサも設定される
    - GKE とかでなければ使えない
- Service の ExternalName タイプ
    - 外部のサービスの DNS 名が Pod から CNAME で参照できる
    - RDS のエンドポイントを抽象的な名前でアクセスしたり出来る
    - [kube-dns](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns) が別途必要
    - さっと作れそうじゃなかったのでパス
- ↑でためしたリソース以外にもいろいろなリソースがあるっぽい
- もうちょっと本気で使ってみないとなんともわからない
    - でもたぶん本番系で使うことはないと思う
