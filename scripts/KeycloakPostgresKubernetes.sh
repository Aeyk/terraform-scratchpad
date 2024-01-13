#!/usr/bin/env bash

set -o xtrace

pushd .

## TODO(Malik): Check if not UBUNTU

## Generate and add ssh key to authorized users
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
test -e $HOME/.ssh/id_rsa || ssh-keygen -f $HOME/.ssh/id_rsa -P ""
cat $HOME/.ssh/id_rsa.pub >> $HOME/.ssh/authorized_keys

## Install ansible
sudo apt update
# sudo apt install software-properties-common --yes
# sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install python-is-python3 python3-pip -y
pip3 install ansible==7.6.0 ruamel_yaml netaddr jmespath==0.9.5

echo 'export PATH=${PATH:+${PATH}:}$HOME/.local/bin/' >> $HOME/.bashrc && source $HOME/.bashrc

## Install kubespray
cd /tmp
git clone https://github.com/kubernetes-sigs/kubespray
cd kubespray
git checkout release-2.23

# Copy ``inventory/sample`` as ``inventory/mycluster``
cp -rfp inventory/sample inventory/main

# Update Ansible inventory file with inventory builder
declare -a IPS=(10.0.0.4)
CONFIG_FILE=inventory/main/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

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

mkdir $HOME/.kube
sudo cp -fv /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass | grep "local path (default)"

kubectl create -f https://stackgres.io/downloads/stackgres-k8s/stackgres/1.7.0/stackgres-operator-demo.yml
kubectl wait -n stackgres deployment -l group=stackgres.io --for=condition=Available && kubectl get pods -n stackgres -l group=stackgres.io

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
      size: '5Gi'
EOF

kubectl get secret postgres-cluster --template '{{ printf "%s" (index .data "superuser-password" | base64decode) }}'

kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql postgres://postgres:$(kubectl get secrets postgres-cluster -o jsonpath='{.data.superuser-password}' | base64 -d)@postgres-cluster-primary -c \
"CREATE USER keycloak WITH PASSWORD 'password' CREATEDB;
 CREATE DATABASE keycloak;
 GRANT ALL on schema public TO keycloak;"

kubectl run psql --rm -it --image ongres/postgres-util --restart=Never -- psql postgres://keycloak:password@postgres-cluster-primary/keycloak

kubectl get secret -n stackgres stackgres-restapi-admin --template '{{ printf "username = %s\npassword = %s\n" (.data.k8sUsername | base64decode) ( .data.clearPassword | base64decode) }}'

POD_NAME=$(kubectl get pods --namespace stackgres -l "stackgres.io/restapi=true" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward "$POD_NAME" 8443:9443 --namespace stackgres

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

kubectl patch ingress keycloak --patch "$(cat <<EOF
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - keycloak.mksybr.com
    secretName: keycloak-tls
EOF
)"

cat << EOF | kubectl apply -f -
apiVersion: stackgres.io/v1
kind: SGInstanceProfile
metadata:
  namespace: default
  name: size-small
spec:
  cpu: "1"
  memory: "4Gi"
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
  instances: 3
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

cat << 'EOF' | kubectl apply -f -
apiVersion: v1
data:
  keycloak.conf: |
    # Basic settings for running in production. Change accordingly before deploying the server.
    # Database
    db=postgres
    db-username=postgres           # TODO fix permission to run as keycloak
    db-password=***REMOVED*** # TODO fix permission to run as keycloak
    db-url=jdbc:postgresql://postgres-cluster-primary/keycloak

    # Observability
    # If the server should expose healthcheck endpoints.
    #health-enabled=true
    # If the server should expose metrics endpoints.
    #metrics-enabled=true

    # HTTP
    # The file path to a server certificate or certificate chain in PEM format.
    #https-certificate-file=${kc.home.dir}conf/server.crt.pem
    # The file path to a private key in PEM format.
    #https-certificate-key-file=${kc.home.dir}conf/server.key.pem
    # The proxy address forwarding mode if the server is behind a reverse proxy.
    #proxy=reencrypt

    # Do not attach route to cookies and rely on the session affinity capabilities from reverse proxy
    #spi-sticky-session-encoder-infinispan-should-attach-route=false

    # Hostname for the Keycloak server.
    hostname=keycloak.mksybr.com

kind: ConfigMap
metadata:
  name: keycloak-configmap
EOF

# kubectl create -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/kubernetes/keycloak.yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  labels:
    app: keycloak
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
  selector:
    app: keycloak
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  labels:
    app: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:23.0.4
          args: ["start-dev"]
          env:
            - name: KEYCLOAK_ADMIN
              value: "admin"
            - name: KEYCLOAK_ADMIN_PASSWORD
              value: "admin"
            - name: KC_PROXY
              value: "edge"
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /realms/master
              port: 8080
          volumeMounts:
          - mountPath: /opt/keycloak/conf/keycloak.conf
            subPath: keycloak.conf
            name: keycloak-config-file
            readOnly: true
      volumes:
        - name: keycloak-config-file
          configMap:
            name: keycloak-configmap
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

popd