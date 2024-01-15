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

kubectl -n kubernetes-dashboard create token cluster-admin-user

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
# kubectl port-forward "$POD_NAME" 8443:9443 --namespace stackgres # TODO replace with deployment

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
    email: mksybr@gmail.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: grafana-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: prometheus-letsencrypt-prod
  namespace: cert-manager
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


cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    kubernetes.io/ingress.class: "nginx"
spec:
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

cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: archivebox
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    kubernetes.io/ingress.class: "nginx"
spec:
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
    secretName: letsencrypt-prod
EOF

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

# POSTGRES_PASSWORD=$(kubectl get secret postgres-cluster --template '{{ printf "%s" (index .data "superuser-password" | base64decode) }}')

kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE DATABASE keycloak;"

kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql "postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster" -c \
"CREATE USER keycloak WITH PASSWORD 'password' CREATEDB;
 GRANT ALL on schema public TO keycloak;"

kubectl get secret -n stackgres stackgres-restapi-admin --template '{{ printf "username = %s\npassword = %s\n" (.data.k8sUsername | base64decode) ( .data.clearPassword | base64decode) }}'

POSTGRES_PASSWORD=$(kubectl get secret postgres-cluster --template '{{ printf "%s" (index .data "superuser-password" | base64decode) }}')

#TODO fix error maybe wait?
cat << EOF | kubectl apply -f -
apiVersion: v1
data:
  keycloak.conf: |
    # Basic settings for running in production. Change accordingly before deploying the server.
    # Database
    db=postgres
    db-username=postgres           # TODO fix permission to run as keycloak
    db-password=$POSTGRES_PASSWORD # TODO fix permission to run as keycloak
    db-url-host=postgres-cluster.default.svc.cluster.local
    # db-url-host=postgres-cluster-primary
    # db-url=jdbc:postgres://postgres:$POSTGRES_PASSWORD@postgres-cluster-primary/postgres
    db-pool-initial-size=10
    

    # Observability
    # If the server should expose healthcheck endpoints.
    #health-enabled=true
    # If the server should expose metrics endpoints.
    #metrics-enabled=true

    # HTTP
    # The file path to a server certificate or certificate chain in PEM format.
    #https-certificate-file=\${kc.home.dir}conf/server.crt.pem
    # The file path to a private key in PEM format.
    #https-certificate-key-file=\${kc.home.dir}conf/server.key.pem
    # The proxy address forwarding mode if the server is behind a reverse proxy.
    proxy=edge
    http-max-queued-requests=10
    # Do not attach route to cookies and rely on the session affinity capabilities from reverse proxy
    #spi-sticky-session-encoder-infinispan-should-attach-route=false

    # Hostname for the Keycloak server.
    # hostname=keycloak.mksybr.com
    # hostname-path=/keycloak
    # http-relative-path=/keycloak
    hostname-url=https://keycloak.mksybr.com:443/
    hostname-admin-url=https://keycloak.mksybr.com:443/
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
          args: ["--verbose", "start-dev", "--db-url-host", "postgres-cluster-primary", "--db-username", "postgres", "--db-password", "$POSTGRES_PASSWORD"] 
          volumeMounts:
          - mountPath: /opt/keycloak/conf/keycloak.conf
            subPath: keycloak.conf
            name: keycloak-config-file
            readOnly: true
          env: []
      volumes:
        - name: keycloak-config-file
          configMap:
            name: keycloak-configmap
EOF


cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  annotations:
    cert-manager.io/cluster-issuer: "keycloak-letsencrypt-prod"
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
                number: 8000
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - keycloak.mksybr.com
    secretName: keycloak-letsencrypt-prod
EOF

echo ""
KEYCLOAK_URL=https://keycloak.mksybr.com &&
echo "" &&
echo "Keycloak:                 $KEYCLOAK_URL" &&
echo "Keycloak Admin Console:   $KEYCLOAK_URL/admin" &&
echo "Keycloak Account Console: $KEYCLOAK_URL/realms/myrealm/account" &&
echo ""

wget -q -O - https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/kubernetes/keycloak-ingress.yaml | \
sed "s/KEYCLOAK_HOST/keycloak.mksybr.com/" | \
kubectl create -f -
## TODO X-Forwarded- and Forwarded headers
#### [io.quarkus.vertx.http.runtime.VertxHttpRecorder] (main) The X-Forwarded-* and Forwarded headers will be considered when determining the proxy address. This configuration can cause a security issue as clients can forge requests and send a forwarded header that is not overwritten by the proxy. Please consider use one of these headers just to forward the proxy address in requests.


# cat << EOF | kubectl patch ingress/keycloak --patch "$(cat -)"
# metadata:
#   name: keycloak
#   annotations:
#     cert-manager.io/cluster-issuer: "letsencrypt-prod"
# spec:
#   ingressClassName: "nginx"
#   tls:
#   - hosts:
#     - keycloak.mksybr.com
#     secretName: letsencrypt-prod
# EOF

cd /tmp/; git clone https://github.com/prometheus-operator/kube-prometheus || true; cd kube-prometheus

kubectl apply --server-side -f manifests/setup
kubectl wait \
	--for condition=Established \
	--all CustomResourceDefinition \
	--namespace=monitoring
kubectl apply -f manifests/

## kubectl delete --ignore-not-found=true -f manifests/ -f manifests/setup
kubectl apply --kustomize github.com/kubernetes/ingress-nginx/deploy/prometheus/

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  annotations:
  labels:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/part-of: ingress-nginx
  name: prometheus-server
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
apiVersion: v1
kind: Service
metadata:
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
  sessionAffinity: None
  type: LoadBalancer
EOF

## TODO why no lets encrypt?
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-prometheus.io/cluster-issuer: letsencrypt-prod
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

kubectl apply --kustomize github.com/kubernetes/ingress-nginx/deploy/grafana/

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: ingress-nginx
  name: grafana
  namespace: ingress-nginx
spec:
  ports:
  - port: 3000
    protocol: TCP
    targetPort: 3000
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

# # TODO bufix error server is invalid
# # The Service "prometheus-server" is invalid: spec.ports[1].name: Required value
# cat << 'EOF' | kubectl patch service -n ingress-nginx prometheus-server --patch "$(cat -)"
# spec:
#   ports:
#     - name: prometheus-server
#       port: 10254
#       targetPort: prometheus
# EOF

# # TODO bufix error server is invalid
# # The Service "prometheus-server" is invalid: spec.ports[1].name: Required value
# cat << EOF | kubectl patch deployment -n ingress-nginx prometheus-server --patch "$(cat -)"
# spec:
#   template:
#     metadata:
#       annotations:
#         prometheus.io/scrape: "true"
#         prometheus.io/port: "10254"
#     spec:
#       containers:
#         - name: controller
#           ports:
#             - name: prometheus
#               containerPort: 10254
# EOF

cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
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

popd