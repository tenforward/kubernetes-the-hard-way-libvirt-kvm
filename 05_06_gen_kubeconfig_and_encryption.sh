#!/bin/bash -e
. ./config

echo "Generating the kubeconfig for worker nodes"
for instance in ${WORKERS[@]}
do
    kubectl config set-cluster kubernetes-the-hard-way \
	    --certificate-authority=certs/${CA_CERTS} \
	    --embed-certs=true \
	    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
	    --kubeconfig=${instance}.kubeconfig

    kubectl config set-credentials system:node:${instance}.${DOMAIN} \
	    --client-certificate=certs/${instance}.pem \
	    --client-key=certs/${instance}-key.pem \
	    --embed-certs=true \
	    --kubeconfig=${instance}.kubeconfig

    kubectl config set-context default \
	    --cluster=kubernetes-the-hard-way \
	    --user=system:node:${instance}.${DOMAIN} \
	    --kubeconfig=${instance}.kubeconfig

    kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done

echo "Generating the kubeconfig for kube-proxy"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=certs/${CA_CERTS} \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=certs/kube-proxy.pem \
    --client-key=certs/kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}

echo "Generating the kubeconfig for kube-controller-manager"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=certs/${CA_CERTS} \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=certs/kube-controller-manager.pem \
    --client-key=certs/kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}


echo "Generating the kubeconfig for kube-scheduler"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=certs/${CA_CERTS} \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=certs/kube-scheduler.pem \
    --client-key=certs/kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}

echo "Generating the kubeconfig for admin"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=certs/${CA_CERTS} \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=certs/admin.pem \
    --client-key=certs/admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

for node in ${WORKERS[@]}
do
    virsh start ${node}
    sleep 10
    addr=$(virsh net-dhcp-leases k8s-net | grep ${node} | awk '{ print $5 }' | sed 's|/24||')
    scp ${node}.kubeconfig ${addr}:~
    scp kube-proxy.kubeconfig ${addr}:~
done

for node in ${MASTERS[@]}
do
    virsh start ${node}
    sleep 10
    addr=$(virsh net-dhcp-leases k8s-net | grep ${node} | awk '{ print $5 }' | sed 's|/24||')
    for kubeconfig in admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig; do
	scp ${kubeconfig} ${addr}:~
    done
done

# Data Encryption Config and Key (06)
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

for node in master00 master01 master02; do 
    scp encryption-config.yaml $node:~
done
