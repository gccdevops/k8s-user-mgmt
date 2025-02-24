#!/bin/bash

set -e # break on errors

USERNAME=$1
GROUP=${2:-devops}
NAMESPACE="default"

echo "create CSR for user $USERNAME in group $GROUP"

openssl req -new -newkey rsa:4096 -nodes -keyout $USERNAME-k8s.key -out $USERNAME-k8s.csr -subj "/CN=$USERNAME/O=$GROUP"

echo "upload CSR to Kubernetes"

cat <<EOT | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USERNAME-k8s-access
spec:
  expirationSeconds: 86400 # one day
  signerName: kubernetes.io/kube-apiserver-client  
  groups:
  - system:authenticated
  request: $( cat $USERNAME-k8s.csr | base64 | tr -d '\n' )
  usages:
  - client auth
EOT

echo "sign CSR in Kubernetes"

kubectl certificate approve $USERNAME-k8s-access

echo "retrieve signed certificate from Kubernetes"

kubectl get csr $USERNAME-k8s-access -o jsonpath='{.status.certificate}' | base64 --decode > $USERNAME-k8s-access.crt

echo "retrieve current context"
CURRENT_CONTEXT=$(kubectl config current-context)
CURRENT_CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.cluster}")
CURRENT_CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CURRENT_CLUSTER_NAME\")].cluster.server}")

echo "retrieve Kubernetes CA"

# kubectl config view -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' --raw | base64 --decode - > k8s-ca.crt
kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CURRENT_CLUSTER_NAME\")].cluster.certificate-authority-data}" --raw | base64 -d > k8s-ca.crt

echo "create kubeconfig for user $USERNAME"

# kubectl config set-cluster $(kubectl config view -o jsonpath='{.clusters[0].name}') --server=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}') --certificate-authority=k8s-ca.crt --kubeconfig=$USERNAME-k8s-config --embed-certs
kubectl config set-cluster $CURRENT_CLUSTER_NAME --server=$CURRENT_CLUSTER_SERVER --certificate-authority=k8s-ca.crt --kubeconfig=$USERNAME-k8s-config --embed-certs

kubectl config set-credentials $USERNAME --client-certificate=$USERNAME-k8s-access.crt --client-key=$USERNAME-k8s.key --embed-certs --kubeconfig=$USERNAME-k8s-config

#kubectl config set-context $USERNAME --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') --namespace=$NAMESPACE --user=$USERNAME --kubeconfig=$USERNAME-k8s-config
kubectl config set-context $USERNAME --cluster=$CURRENT_CLUSTER_NAME --namespace=$NAMESPACE --user=$USERNAME --kubeconfig=$USERNAME-k8s-config
kubectl config use-context $USERNAME --kubeconfig=$USERNAME-k8s-config

echo "create rolebinding for user $USERNAME"

# kubectl create rolebinding $USERNAME-admin --namespace=$NAMESPACE --clusterrole=admin --user=$USERNAME
# kubectl create clusterrolebinding devops-view  --clusterrole=view --group=devops

echo "kubeconfig for user $USERNAME has been saved to $USERNAME-k8s-config"
echo
echo "Try it out with"
echo -e "\tkubectl get pods --kubeconfig=$USERNAME-k8s-config"
