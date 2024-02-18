#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o errtrace
set -o pipefail

pushd .

## TODO(Malik): Check if not UBUNTU
## TODO(Malik): seperate applications to different namespaces 

## Generate and add ssh key to authorized users
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
test -e "$HOME"/.ssh/id_rsa || ssh-keygen -f "$HOME"/.ssh/id_rsa -P ""
cat "$HOME"/.ssh/id_rsa.pub >> "$HOME"/.ssh/authorized_keys

## Install ansible
sudo apt update
# sudo apt install software-properties-common --yes
# sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install python-is-python3 python3-pip -y
pip3 install ansible==7.6.0 ruamel_yaml netaddr jmespath==0.9.5

sudo mkdir /data/{elasticsearch,kibana,archivebox,gitea}

echo 'export PATH=${PATH:+${PATH}:}$HOME/.local/bin/' >> "$HOME"/.bashrc && source "$HOME"/.bashrc

## Install kubespray
cd /tmp || exit
git clone https://github.com/kubernetes-sigs/kubespray || true
cd kubespray || exit
git checkout release-2.23

# Copy ``inventory/sample`` as ``inventory/mycluster``
cp -rfp inventory/sample inventory/main

# Update Ansible inventory file with inventory builder
declare -a IPS=(10.0.0.4)
CONFIG_FILE=inventory/main/hosts.yaml python3 contrib/inventory_builder/inventory.py "${IPS[@]}"

# Review and change parameters under ``inventory/main/group_vars``
# cat inventory/main/group_vars/all/all.yml
# cat inventory/main/group_vars/k8s_cluster/k8s-cluster.yml

sed -i 's/metrics_server_enabled: false/metrics_server_enabled: true/g' inventory/main/group_vars/k8s_cluster/addons.yml
sed -i 's/ingress_nginx_enabled: false/ingress_nginx_enabled: true/g' inventory/main/group_vars/k8s_cluster/addons.yml
sed -i 's/cert_manager_enabled: false/cert_manager_enabled: true/g' inventory/main/group_vars/k8s_cluster/addons.yml
sed -i 's/^# kubectl_localhost: false/kubectl_localhost: true/g' inventory/main/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's/helm_enabled: false/helm_enabled: true/g' inventory/main/group_vars/k8s_cluster/addons.yml

# TODO CA certificate

# Clean up old Kubernetes cluster with Ansible Playbook - run the playbook as root
# The option `--become` is required, as for example cleaning up SSL keys in /etc/,
# uninstalling old packages and interacting with various systemd daemons.
# Without --become the playbook will fail to run!
# And be mind it will remove the current kubernetes cluster (if it's running)!
ansible-playbook -i inventory/main/hosts.yaml  --become --become-user=root reset.yml -e reset_confirmation=true

# Deploy Kubespray with Ansible Playbook - run the playbook as root
# The option `--become` is required, as for example writing SSL keys in /etc/,
# installing packages and interacting with various systemd daemons.
# Without --become the playbook will fail to run!
ansible-playbook -i inventory/main/hosts.yaml  --become --become-user=root cluster.yml

mkdir -p "$HOME"/.kube
sudo cp -fv /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u):$(id -g)" "$HOME"/.kube/config

# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass | grep "local-path (default)"

# cat << EOF | kubectl apply -f -
# apiVersion: storage.k8s.io/v1
# kind: StorageClass
# metadata:
#   name: local-storage
# provisioner: kubernetes.io/no-provisioner
# volumeBindingMode: Immediate
# EOF

## Kubernetes Dashboard BEGIN
# TODO lets encrypt certificate error
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-admin-user
  namespace: kubernetes-dashboard
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cluster-admin-user
  namespace: kubernetes-dashboard
EOF
# TODO service and deployment to access cluster dashboard
kubectl -n kubernetes-dashboard create token cluster-admin-user
## Kubernetes Dashboard END


## StackGres BEGIN
kubectl create -f https://stackgres.io/downloads/stackgres-k8s/stackgres/1.7.0/stackgres-operator-demo.yml
kubectl wait -n stackgres deployment -l group=stackgres.io --for=condition=Available
kubectl get pods -n stackgres -l group=stackgres.io
cat << 'EOF' | kubectl create -f -
apiVersion: stackgres.io/v1
kind: SGCluster
metadata:
  name: postgres-cluster
spec:
  instances: 1
  postgres:
    version: 'latest'
  pods:
    persistentVolume: 
      size: '10Gi'
EOF
POD_NAME=$(kubectl get pods --namespace stackgres -l "stackgres.io/restapi=true" -o jsonpath="{.items[0].metadata.name}")
cat << EOF | kubectl apply -f -
apiVersion: stackgres.io/v1
kind: SGInstanceProfile
metadata:
  namespace: default
  name: size-small
spec:
  cpu: "1"
  memory: "10Gi"
EOF
cat << EOF | kubectl apply -f -
apiVersion: stackgres.io/v1
kind: SGPostgresConfig
metadata:
  namespace: default
  name: pgconfig1
spec:
  postgresVersion: "16"
  postgresql.conf:
    shared_buffers: '512MB'
    random_page_cost: '1.5'
    password_encryption: 'scram-sha-256'
    log_checkpoints: 'on'
EOF
cat << EOF | kubectl apply -f -
apiVersion: stackgres.io/v1
kind: SGPoolingConfig
metadata:
  namespace: default
  name: poolconfig1
spec:
  pgBouncer:
    pgbouncer.ini:
      pgbouncer:
        pool_mode: transaction
        max_client_conn: '1000'
        default_pool_size: '80'
EOF
cat << EOF | kubectl apply -f -
apiVersion: stackgres.io/v1
kind: SGCluster
metadata:
  namespace: default
  name: postgres-cluster
spec:
  postgres:
    version: '16.1'
  instances: 1
  sgInstanceProfile: 'size-small'
  pods:
    persistentVolume:
      size: '10Gi'
  configurations:
    # sgPostgresConfig: 'pgconfig1'
    sgPoolingConfig: 'poolconfig1'
    # backups:
    # - sgObjectStorage: 'backupconfig1'
    #   cronSchedule: '*/5 * * * *'
    #   retention: 6
  managedSql:
    scripts:
    - sgScript: cluster-scripts
EOF
cat << EOF | kubectl patch statefulsets/postgres-cluster --patch "$(cat -)"
spec:
  replicas: 1
EOF
while ! kubectl get secret postgres-cluster; do echo "Waiting for my secret. CTRL-C to exit."; sleep 1; done
kubectl get secret -n stackgres stackgres-restapi-admin --template '{{ printf "username = %s\npassword = %s\n" (.data.k8sUsername | base64decode) ( .data.clearPassword | base64decode) }}'
## StackGres END


## Let's Encrypt BEGIN
cat << EOF | kubectl patch configmap -n ingress-nginx ingress-nginx --patch "$(cat -)"
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
data:
  hsts: "false"
EOF
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
 name: letsencrypt-staging
 namespace: cert-manager
spec:
 acme:
   # The ACME server URL
   server: https://acme-staging-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: mksybr@gmail.com
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
     name: letsencrypt-staging
   # Enable the HTTP-01 challenge provider
   solvers:
   - http01:
       ingress:
         class:  nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
## Let's Encrypt END


## Keycloak BEGIN
### TODO(Malik): make single realm w/ multiple OIDC clients
head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | kubectl create secret generic keycloak-admin-user     --from-file=password=/dev/stdin -o json
head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | kubectl create secret generic postgres-keycloak-user     --from-file=password=/dev/stdin -o json
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE DATABASE keycloak;"
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE USER keycloak WITH ENCRYPTED PASSWORD '$(kubectl get secrets postgres-keycloak-user -o jsonpath='{.data.password}' | base64 -d)' CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;"
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster/keycloak" -c \
"GRANT ALL on schema public TO keycloak;"
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://keycloak:$(kubectl get secrets postgres-keycloak-user -o jsonpath='{.data.password}' | base64 -d)@postgres-cluster/keycloak" -c \
"GRANT ALL on schema public TO keycloak;"
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: keycloak-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: keycloak-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
## TODO X-Forwarded- and Forwarded headers
#### [io.quarkus.vertx.http.runtime.VertxHttpRecorder] (main) The X-Forwarded-* and Forwarded headers will be considered when determining the proxy address. This configuration can cause a security issue as clients can forge requests and send a forwarded header that is not overwritten by the proxy. Please consider use one of these headers just to forward the proxy address in requests.
cat << EOF | kubectl apply -f -
apiVersion: v1
data:
  keycloak.conf: |
    # Basic settings for running in production. Change accordingly before deploying the server.
    # Database
    db=postgres
    db-username=keycloak
    db-password=$(kubectl get secrets postgres-keycloak-user -o jsonpath='{.data.password}' | base64 -d)
    db-url-host=postgres-cluster.default.svc.cluster.local
    db-pool-initial-size=10
    

    # Observability TODO(Malik): monitoring
    health-enabled=true
    metrics-enabled=true

    # HTTP
    hostname-debug=true
    http-max-queued-requests=10
    proxy=edge
    hostname-strict-ssl=true
    http-enabled=true
    hostname-url=https://keycloak.mksybr.com/
    hostname-admin-url=https://keycloak.mksybr.com/

    # Quarkus
    quarkus.transaction-manager.enable-recovery=true

kind: ConfigMap
metadata:
  name: keycloak-configmap
EOF
kubectl create -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/kubernetes/keycloak.yaml
kubectl scale deployment keycloak --replicas=0
kubectl scale deployment keycloak --replicas=1
cat <<EOF | kubectl patch deployment keycloak --patch "$(cat -)" 
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: keycloak
          # why does thiese args work but the keycloak config map doesnt?
          args: ["--verbose", "start"]
          volumeMounts:
          - mountPath: /opt/keycloak/conf/keycloak.conf
            subPath: keycloak.conf
            name: keycloak-config-file
            readOnly: true
          env: # TODO(Malik): alternative / more secure secret injection?
            - name: KEYCLOAK_ADMIN
              value: admin
            - name: KEYCLOAK_ADMIN_PASSWORD
              value: "$(kubectl get secrets keycloak-admin-user -o jsonpath='{.data.password}' | base64 -d)"
      volumes:
        - name: keycloak-config-file
          configMap:
            name: keycloak-configmap
        - name: keycloak-realm-file
          secret:
            secretName: keycloak-realm
EOF
# cat << EOF | kubectl patch deployment/keycloak --patch "$(cat -)"
# spec:
#   template:
#     spec:
#       initContainers:
#         - name: import-realm
#           image: quay.io/keycloak/keycloak:23.0.4
#           command: ["/opt/keycloak/bin/kc.sh"]
#           args: ["import", "--file", "/opt/keycloak/realm/dev.json"]
#           volumeMounts:
#             - mountPath: /opt/keycloak/realm/dev.json
#               subPath: dev.json
#               name: keycloak-realm-file
#               readOnly: true          
#       volumes:
#         - name: keycloak-config-file
#           configMap:
#             name: keycloak-configmap
#         - name: keycloak-realm-file
#           secret:
#             secretName: keycloak-realm
# EOF
# TODO(Malik): automatic realm backups
echo ""
KEYCLOAK_URL=https://keycloak.mksybr.com &&
echo "" &&
echo "Keycloak:                 $KEYCLOAK_URL" &&
echo "Keycloak Admin Console:   $KEYCLOAK_URL/admin" &&
echo "Keycloak Account Console: $KEYCLOAK_URL/realms/dev/account" &&
echo ""
# NOTE: do I even need this commented block now?
# wget -q -O - https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/kubernetes/keycloak-ingress.yaml | \
#     sed "s/KEYCLOAK_HOST/keycloak.mksybr.com/" | \
#     kubectl create -f -
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: keycloak.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: keycloak
              port:
                number: 8080
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - keycloak.mksybr.com
    secretName: keycloak-letsencrypt-prod
EOF
## Keycloak END


## Prometheus & Grafana Initialization BEGIN
cd /tmp/; git clone https://github.com/prometheus-operator/kube-prometheus || true; cd kube-prometheus
kubectl apply --server-side -f manifests/setup
kubectl wait \
	--for condition=Established \
	--all CustomResourceDefinition \
	--namespace=monitoring
kubectl apply -f manifests/
## Prometheus & Grafana Initialization END


## Prometheus BEGIN
## UNDO:
#### cd /tmp/kube-prometheus; kubectl delete --ignore-not-found=true -f manifests/ -f manifests/setup
cat << EOF | kubectl apply  -f -
apiVersion: v1
data:
  prometheus-config: |
    global:
      scrape_interval: 10s
      evaluation_interval: 15s
    scrape_configs:
    - job_name: 'ingress-nginx-endpoints'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - ingress-nginx
          - default
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
      - source_labels: [__meta_kubernetes_service_name]
        regex: prometheus-server
        action: drop
    scrape_configs:
      - job_name: keycloak
        static_configs:
          - targets: ['https://keycloak.mksybr.com']
          - targets: ['https://prometheus.mksybr.com']

kind: ConfigMap
metadata:
  name: prometheus-configmap
  namespace: ingress-nginx
EOF
# TODO(Malik): fix prometheus configmap injection
# cat << EOF | kubectl patch deployments -n ingress-nginx prometheus-server --patch="$(cat -)"
# spec:
#   template:
#     spec:
#       containers:
#         - name: prometheus-server
#           image: prom/prometheus
#           volumeMounts:
#             - name: prometheus-config-file 
#               mountPath: /etc/prometheus/prometheus.yaml
#               subPath: prometheus.yaml
#       volumes:
#         - name: prometheus-config-file
#           configMap:
#             name: prometheus-configmap
# EOF
kubectl apply --kustomize github.com/kubernetes/ingress-nginx/deploy/prometheus/
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: prometheus-letsencrypt-prod
  namespace: ingress-nginx
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: prometheus-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  annotations:
  labels:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/part-of: ingress-nginx
  name: prometheus
  namespace: ingress-nginx
spec:
  ports:
  - port: 9090
    protocol: TCP
    targetPort: 9090
  selector:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/part-of: ingress-nginx
  type: LoadBalancer
EOF
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  name: prometheus
  namespace: ingress-nginx
spec:
  ingressClassName: "nginx"
  rules:
  - host: prometheus.mksybr.com
    http:
      paths:
      - backend:
          service:
            name: prometheus
            port:
              number: 9090
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - prometheus.mksybr.com
    secretName: prometheus-letsencrypt-prod
EOF
## Prometheus END


## Grafana BEGIN
## UNDO:
#### cd /tmp/kube-prometheus; kubectl delete --ignore-not-found=true -f manifests/ -f manifests/setup
kubectl apply --kustomize github.com/kubernetes/ingress-nginx/deploy/grafana/ # TODO(Malik): volume & volumeMount for Grafana Deployment

cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: grafana-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.comf
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: grafana-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
# [server]
# domain = grafana.mksybr.com
# http_port = 443
# [date_formats]
# default_timezone = UTC

cat << EOF | kubectl create secret generic -n ingress-nginx grafana-config --from-file=grafana.ini=/dev/stdin
[server]
root_url = https://grafana.mksybr.com
[auth.generic_oauth]
enabled = true
name = Keycloak
allow_sign_up = true
client_id = grafana
client_secret = $(kubectl get secrets -n ingress-nginx keycloak-grafana-client-secret -o jsonpath='{.data.client-secret}' | base64 -d)
scopes = openid email profile offline_access roles
email_attribute_path = email
login_attribute_path = username
name_attribute_path = full_name
auth_url = https://keycloak.mksybr.com/realms/dev/protocol/openid-connect/auth
token_url = https://keycloak.mksybr.com/realms/dev/protocol/openid-connect/token
api_url = https://keycloak.mksybr.com/realms/dev/protocol/openid-connect/userinfo
role_attribute_path = contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'editor') && 'Editor' || 'Viewer'
EOF
cat << EOF | kubectl patch deployments -n ingress-nginx grafana --patch="$(cat -)"
spec:
  template:
    spec:
      containers:
        - name: grafana
          volumeMounts:
            - name: grafana-config-file 
              mountPath: /etc/grafana/grafana.ini 
              subPath: grafana.ini
      volumes:
        - name: grafana-config-file
          secret:
            secretName: grafana-config
            items:
              - key: grafana.ini
                path: grafana.ini
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: grafana
  name: grafana
  namespace: ingress-nginx
spec:
  ports:
  - port: 3000
    protocol: TCP
    targetPort: 3002
  selector:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: ingress-nginx
  type: LoadBalancer
EOF
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  name: grafana
  namespace: ingress-nginx
spec:
  ingressClassName: "nginx"
  rules:
  - host: grafana.mksybr.com
    http:
      paths:
      - backend:
          service:
            name: grafana
            port:
              number: 3000
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - grafana.mksybr.com
    secretName: grafana-letsencrypt-prod
EOF
## Grafana END


## ArchiveBox BEGIN
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: archivebox-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: archivebox-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archivebox
spec:
  storageClassName: "local-path"
  volumeName: archivebox
  resources:
    requests:
      storage: 1Gi
  accessModes:
    - ReadWriteMany
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: archivebox
  labels:
    type:
      local
spec:
  local:
    path:
      /data/archivebox
  capacity: 
    storage:
      10Gi
  storageClassName: "local-path"
  accessModes:
    - ReadWriteMany
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node1
EOF
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: archivebox
spec:
  selector:
    matchLabels:
      app: archivebox
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: archivebox
    spec:
      initContainers:
        - name: init-archivebox
          image: archivebox/archivebox
          args: ['init']
          volumeMounts:
            - mountPath: /data
              name: archivebox
      containers:
        - name: archivebox
          args: ["server"]
          image: archivebox/archivebox
          ports:
            - containerPort: 8000
              protocol: TCP
              name: http
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
          volumeMounts:
            - mountPath: /data
              name: archivebox
      restartPolicy: Always
      volumes:
        - name: archivebox
          persistentVolumeClaim:
            claimName: archivebox
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app: archivebox
  name: archivebox
spec:
  selector:
    app: archivebox
  ports:
    - name: http
      port: 8000
  type: LoadBalancer
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: archivebox
  annotations:
    cert-manager.io/cluster-issuer: "archivebox-letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: archivebox.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: archivebox
              port:
                number: 8000
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - archivebox.mksybr.com
    secretName: archivebox-letsencrypt-prod
EOF
## ArchiveBox END

## ElasticSearch BEGIN
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: elasticsearch-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: elasticsearch-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: elasticsearch
spec:
  storageClassName: "local-path"
  volumeName: elasticsearch
  resources:
    requests:
      storage: 10Gi
  accessModes:
    - ReadWriteMany
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: elasticsearch
  labels:
    type:
      local
spec:
  local:
    path:
      /data/elasticsearch
  capacity: 
    storage:
      10Gi
  storageClassName: "local-path"
  accessModes:
    - ReadWriteMany
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node1
EOF
kubectl create -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.10.0/operator.yaml
cat <<EOF | kubectl apply -f -
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
spec:
  version: 8.11.4
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: elasticsearch
  annotations:
    cert-manager.io/cluster-issuer: "elasticsearch-letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: elasticsearch.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: elasticsearch
              port:
                number: 9200
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - elasticsearch.mksybr.com
    secretName: elasticsearch-letsencrypt-prod
EOF
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
spec:
  selector:
    matchLabels:
      app: elasticsearch
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
        - name: elasticsearch
          image: elasticsearch:8.11.3
          ports:
            - containerPort: 9200
              protocol: TCP
              name: http
          volumeMounts:
            - mountPath: /usr/share/elasticsearch/data
              name: elasticsearch
      restartPolicy: Always
      volumes:
        - name: elasticsearch
          persistentVolumeClaim:
            claimName: elasticsearch
EOF
## ElasticSearch END

## Kibana BEGIN
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    common.k8s.elastic.co/type: kibana
  name: kibana
  namespace: default
spec:
  ports:
  - name: https
    port: 5601
    protocol: TCP
    targetPort: 5601
  selector:
    common.k8s.elastic.co/type: kibana
  sessionAffinity: None
  type: LoadBalancer
EOF
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: kibana-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: kibana-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kibana
spec:
  storageClassName: "local-path"
  volumeName: kibana
  resources:
    requests:
      storage: 10Gi
  accessModes:
    - ReadWriteMany
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kibana
  labels:
    type:
      local
spec:
  local:
    path:
      /data/kibana
  capacity: 
    storage:
      10Gi
  storageClassName: "local-path"
  accessModes:
    - ReadWriteMany
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node1
EOF
cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
spec:
  version: 8.11.4
  count: 1
  elasticsearchRef:
    name: kibana
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana
  annotations:
    cert-manager.io/cluster-issuer: "kibana-letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: kibana.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: kibana
              port:
                number: 5601
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - kibana.mksybr.com
    secretName: kibana-letsencrypt-prod
EOF
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
spec:
  selector:
    matchLabels:
      app: kibana
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
        - name: kibana
          image: kibana:8.11.3
          ports:
            - containerPort: 5601
              protocol: TCP
              name: http
          volumeMounts:
            - mountPath: /usr/share/kibana/data
              name: kibana
      restartPolicy: Always
      volumes:
        - name: kibana
          persistentVolumeClaim:
            claimName: kibana
EOF
## Kibana END


## Gitea BEGIN
head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | kubectl create secret generic gitea-admin-user     --from-file=password=/dev/stdin -o json
head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | kubectl create secret generic postgres-gitea-user     --from-file=password=/dev/stdin -o json
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE USER IF NOT EXISTS gitea WITH PASSWORD 'password' CREATEDB;"
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE DATABASE giteadb WITH OWNER gitea TEMPLATE template0 ENCODING UTF8 LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';"
kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
 "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO gitea;"

cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: gitea-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: gitea-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea
spec:
  storageClassName: "local-path"
  volumeName: gitea
  resources:
    requests:
      storage: 10Gi
  accessModes:
    - ReadWriteMany
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: gitea
  labels:
    type:
      local
spec:
  local:
    path:
      /data/gitea
  capacity: 
    storage:
      10Gi
  storageClassName: "local-path"
  accessModes:
    - ReadWriteMany
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node1
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
data:
  app.ini: |
    APP_NAME = Gitea
    RUN_USER = git
    RUN_MODE = prod
    WORK_PATH = /data/gitea/

    [security]
    INTERNAL_TOKEN     = $(kubectl get secrets gitea-internal-token -o jsonpath='{.data.password}' | base64 -d)
    INSTALL_LOCK       = true
    SECRET_KEY         = $(kubectl get secrets gitea-secret-key -o jsonpath='{.data.password}' | base64 -d)
    PASSWORD_HASH_ALGO = pbkdf2
    
    [database]
    DB_TYPE  = postgres
    HOST     = postgres-cluster:5432
    NAME     = giteadb
    USER     = gitea
    PASSWD   = $(kubectl get secrets postgres-gitea-user -o jsonpath='{.data.password}' | base64 -d)
    SCHEMA   = 
    SSL_MODE = disable
    CHARSET  = utf8
    PATH     = /app/gitea/data/gitea.db
    LOG_SQL  = false

    [repository]
    ROOT = /data/gitea/gitea-repositories

    [server]
    SSH_DOMAIN       = gitea.mksybr.com
    DOMAIN           = gitea.mksybr.com
    HTTP_PORT        = 3000
    ROOT_URL         = https://gitea.mksybr.com/
    SSH_DOMAIN       = gitea.mksybr.com
    DISABLE_SSH      = false
    START_SSH_SERVER = true
    SSH_PORT         = 22
    LFS_START_SERVER = true
    LFS_CONTENT_PATH = /data/gitea/lfs
    LFS_JWT_SECRET   = $(kubectl get secrets gitea-lfs-secret -o jsonpath='{.data.password}' | base64 -d)
    OFFLINE_MODE     = false

    [mailer]
    ENABLED = false

    [service]
    REGISTER_EMAIL_CONFIRM            = false
    ENABLE_NOTIFY_MAIL                = false
    DISABLE_REGISTRATION              = false
    ALLOW_ONLY_EXTERNAL_REGISTRATION  = false
    ENABLE_CAPTCHA                    = false
    REQUIRE_SIGNIN_VIEW               = true
    DEFAULT_KEEP_EMAIL_PRIVATE        = true
    DEFAULT_ALLOW_CREATE_ORGANIZATION = true
    DEFAULT_ENABLE_TIMETRACKING       = true
    NO_REPLY_ADDRESS                  = noreply.localhost

    [picture]
    DISABLE_GRAVATAR        = false
    ENABLE_FEDERATED_AVATAR = true

    [openid]
    ENABLE_OPENID_SIGNIN = true
    ENABLE_OPENID_SIGNUP = true

    [oauth2_client]
    ENABLE_AUTO_REGISTRATION = true
    USERNAME = email

    [session]
    PROVIDER = db # TODO(Malik): redis/redis-cluster

    [log]
    MODE      = console
    LEVEL     = info
    ROOT_PATH = /data/gitea/log
    ROUTER    = console

    [cors]
    ENABLED   = false

    [api]
    ENABLE_SWAGGER = false

    [metrics]
    # ENABLED    = true
    # TOKEN      = create and get prometheus secret

    [cron]
    ENABLED      = true

    [cache]
    # ADAPTER    = redis # TODO(Malik): redis

kind: ConfigMap
metadata:
  name: gitea-configmap
EOF
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
spec:
  selector:
    matchLabels:
      app: gitea
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: gitea
    spec:
      containers:
        - name: gitea
          image: gitea/gitea:1.15
          ports:
            - containerPort: 3000
              hostPort: 3001
              protocol: TCP
              name: http
          ports:
            - containerPort: 22
              hostPort: 2222
              protocol: TCP
              name: ssh
          volumeMounts:
          - mountPath: /data
            name: gitea
      restartPolicy: Always
      volumes:
        - name: gitea
          persistentVolumeClaim:
            claimName: gitea
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gitea
  namespace: default
spec:
  ports:
  - name: https
    port: 3001
    protocol: TCP
    targetPort: 3000
  selector:
    app: gitea
  sessionAffinity: None
  type: LoadBalancer
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gitea-ssh
  namespace: default
spec:
  ports:
  - name: ssh
    port: 2222
    protocol: TCP
    targetPort: 22
  selector:
    app: gitea
  sessionAffinity: None
  type: LoadBalancer
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitea
  annotations:
    cert-manager.io/cluster-issuer: "gitea-letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: gitea.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: gitea
              port:
                number: 3000
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - gitea.mksybr.com
    secretName: gitea-letsencrypt-prod
EOF
## Gitea END

##  Drone CI BEGIN
sudo sysctl -w fs.inotify.max_user_watches=2099999999
sudo sysctl -w fs.inotify.max_user_instances=2099999999
sudo sysctl -w fs.inotify.max_queued_events=2099999999

cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: drone-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: drone-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
helm repo add drone https://charts.drone.io
cat << EOF |  helm install --namespace drone drone drone/drone -f -
env:
  ## REQUIRED: Set the user-visible Drone hostname, sans protocol.
  ## Ref: https://docs.drone.io/installation/reference/drone-server-host/
  ##
  DRONE_SERVER_HOST: drone.mksybr.com
  ## The protocol to pair with the value in DRONE_SERVER_HOST (http or https).
  ## Ref: https://docs.drone.io/installation/reference/drone-server-proto/
  ##
  DRONE_SERVER_PROTO: https
  ## REQUIRED: Set the secret secret token that the Drone server and its Runners will use
  ## to authenticate. This is commented out in order to leave you the ability to set the
  ## key via a separately provisioned secret (see existingSecretName above).
  ## Ref: https://docs.drone.io/installation/reference/drone-rpc-secret/
  ##

  # TODO(automatically register and store in secret)
  DRONE_RPC_SECRET: 
  DRONE_GITEA_CLIENT_ID: 
  DRONE_GITEA_CLIENT_SECRET: 
  DRONE_GITEA_SERVER: https://gitea.mksybr.com
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: drone
  namespace: drone
  annotations:
    cert-manager.io/cluster-issuer: "drone-letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: drone.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: drone
              port:
                number: 8080
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - drone.mksybr.com
    secretName: drone-letsencrypt-prod
EOF
##  Drone CI END


## OpenEBS BEGIN
helm repo add openebs https://openebs.github.io/charts
helm repo update
helm install openebs --namespace openebs openebs/openebs --create-namespace
## OpenEBS BEGIN


## Datasette BEGIN
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: datasette-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: datasette-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: datasette
spec:
  replicas: 1
  selector:
    matchLabels:
      app: datasette
  template:
    metadata:
      labels:
        app: datasette
    spec:
      containers:
      - name: datasette
        image: datasetteproject/datasette
        command:
        - sh
        - -c
        args:
        - |-
          # Install some plugins
          pip install \
            datasette-debug-asgi \
            datasette-cluster-map \
            datasette-psutil
          # Download a DB (using Python because curl/wget are not available)
          python -c 'import urllib.request; urllib.request.urlretrieve("https://global-power-plants.datasettes.com/global-power-plants.db", "/home/global-power-plants.db")'
          # Start Datasette, on 0.0.0.0 to allow external traffic
          datasette -h 0.0.0.0 /home/global-power-plants.db
        ports:
        - containerPort: 8001
          protocol: TCP
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: datasette
  namespace: default
spec:
  ports:
  - name: https
    port: 8001
    protocol: TCP
    targetPort: 8001
  selector:
    app: datasette
  sessionAffinity: None
  type: LoadBalancer
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: datasette
  annotations:
    cert-manager.io/cluster-issuer: "datasette-letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: datasette.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: datasette
              port:
                number: 8001
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - datasette.mksybr.com
    secretName: datasette-letsencrypt-prod
EOF
## Datasette END


## Paperless-NGX BEGIN
curl -L https://github.com/kubernetes/kompose/releases/download/v1.26.0/kompose-linux-amd64 -o kompose
sudo mv kompose /usr/local/bin
git clone https://github.com/paperless-ngx/paperless-ngx/
cd paperless-ngx/docker/compose
mkdir ../kubernetes
kompose convert -f docker-compose.postgres.yml

head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | kubectl create secret generic postgres-paperless-user --from-file=password=/dev/stdin -o json

kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE DATABASE paperless;
CREATE USER paperless WITH ENCRYPTED PASSWORD '$(kubectl get secrets postgres-paperless-user -o jsonpath='{.data.password}' | base64 -d)' CREATEDB;
GRANT ALL ON DATABASE paperless TO paperless;
GRANT USAGE, CREATE ON SCHEMA PUBLIC TO paperless;
ALTER DATABASE paperless OWNER TO paperless;"

kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://paperless:$(kubectl get secrets postgres-paperless-user -o jsonpath='{.data.password}' | base64 -d)@postgres-cluster/paperless" -c \
"GRANT ALL on schema public TO paperless;"
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: paperless-consume
  name: paperless-consume
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: paperless-data
  name: paperless-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: paperless-export
  name: paperless-export
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: paperless-media
  name: paperless-media
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: paperless-redis-data
  name: paperless-redis-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: paperless-redis
  name: paperless-redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: paperless-redis
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: paperless-redis
    spec:
      containers:
        - image: docker.io/library/redis:7
          name: paperless-redis
          volumeMounts:
            - mountPath: /data
              name: paperless-redis-data
      restartPolicy: Always
      volumes:
        - name: paperless-redis-data
          persistentVolumeClaim:
            claimName: paperless-redis-data
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: paperless-redis
  name: paperless-redis
spec:
  ports:
    - name: paperless-redis
      port: 6379
      targetPort: 6379
  selector:
    app: paperless-redis
status:
  loadBalancer: {}
---
apiVersion: v1
kind: Service
metadata:
  labels:
  name: paperless-redis-name
spec:
  externalName: paperless-redis.default.svc.cluster.local
  sessionAffinity: None
  type: ExternalName
status:
  loadBalancer: {}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: paperless-webserver
  name: paperless-webserver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: paperless-webserver
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: paperless-webserver
    spec:
      containers:
        - env:
            - name: PAPERLESS_REDIS
              value: redis://paperless-redis.default.svc.cluster.local:6379
            - name: PAPERLESS_DBHOST
              value: postgres-cluster.default.svc.cluster.local
            - name: PAPERLESS_DBPORT
              value: "5432"
            - name: PAPERLESS_DBNAME
              value: paperless
              # TODO(Malik): resolve db permissions issues
            - name: PAPERLESS_DBUSER
              value: postgres # paperless
            - name: PAPERLESS_DBPASS
              value: $(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d) 
              # $(kubectl get secrets  postgres-paperless-user  -o jsonpath='{.data.password}' | base64 -d)
            - name: PAPERLESS_URL
              value: https://paperless.mksybr.com
          image: ghcr.io/paperless-ngx/paperless-ngx:latest
          name: paperless-webserver
          ports:
            - containerPort: 8000
          resources: {}
          volumeMounts:
            - mountPath: /usr/src/paperless/data
              name: paperless-data
            - mountPath: /usr/src/paperless/media
              name: paperless-media
            - mountPath: /usr/src/paperless/export
              name: paperless-export
            - mountPath: /usr/src/paperless/consume
              name: paperless-consume
      restartPolicy: Always
      volumes:
        - name: paperless-data
          persistentVolumeClaim:
            claimName: paperless-data
        - name: paperless-media
          persistentVolumeClaim:
            claimName: paperless-media
        - name: paperless-export
          persistentVolumeClaim:
            claimName: paperless-export
        - name: paperless-consume
          persistentVolumeClaim:
            claimName: paperless-consume
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: paperless-webserver
  name: paperless-webserver
spec:
  ports:
    - name: http
      port: 8003
      targetPort: 8000
  selector:
    app: paperless-webserver
  type: LoadBalancer
status:
  loadBalancer: {}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: paperless-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: paperless-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: paperless
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: paperless.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: paperless-webserver
              port:
                number: 8003
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - paperless.mksybr.com
    secretName: paperless-letsencrypt-prod
EOF
## Paperless-NGX END


## Statping-NG BEGIN
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: statping
  labels:
    app: statping
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
EOF
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: statping
  labels:
    app: statping
spec:
  replicas: 1
  selector:
    matchLabels:
      app: statping
  template:
    metadata:
      labels:
        app: statping
    spec:
      containers:
      - name: statping
        image:  hunterlong/statping:v0.80.51
        ports:
        - containerPort: 8080
        volumeMounts:
          - mountPath: /app
            name: statping-config
      volumes:
        - name: statping-config
          persistentVolumeClaim:
            claimName: statping
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app: statping
  name: statping
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app: statping
status:
  loadBalancer: {}
EOF
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: statping
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: "nginx"
  rules:
  - host: statping.mksybr.com
    http:
      paths:
      - backend:
          service:
              name: staping
              port:
                number: 80
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - statping.mksybr.com
    secretName: statping-letsencrypt-prod
EOF
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: statping-letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: statping-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
## Statping-NG END


popd


## TODO:
# Change elasticsearch/kibana name quickstart -> ELK
# Fix ElasticSearch Deployment/Service/Ingress
# Limit Elasticsearch memory usage
# Wire up Keycloak for authentication for ELK, ArchiveBox
## Drone <-> Gitea automatic secret creation and sync
# ArgoCD?
#### initContainer, Postgres, Keycloak
# Explicit versions for each image
# Paperless-NGX
# SyncThing + Tailscale/WireGuard
# Velero
# OpenEBS vs Ceph vs Minio vs NFS
# Redis
# HAProxy vs Nginx?
# BugZilla?
# Zulip
# Screego
# Jitsi Meet
# Statping (better kubernetes alternative?), Gotify
# Datasette connect to PostgresQL
# Pi-Hole
# Asciinema
# Dokku vs OpenFaaS vs LocalStack Lambda vs Kubero
# rsyslog
# Searxng
