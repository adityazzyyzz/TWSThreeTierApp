#!/bin/bash

set -e

REGION="us-west-2"
CLUSTER_NAME="three-tier-cluster"
PROJECT_DIR="$HOME/TWSThreeTierApp"
K8S_DIR="$PROJECT_DIR/Kubernetes-Manifests-file"

echo "========================================"
echo " Three-Tier Project - Start"
echo "========================================"

echo ""
echo "AWS identity:"
aws sts get-caller-identity

echo ""
echo "Project directory:"
cd "$PROJECT_DIR"

echo ""
echo "Checking required tools..."

command -v aws >/dev/null || { echo "ERROR: AWS CLI not found"; exit 1; }
command -v kubectl >/dev/null || { echo "ERROR: kubectl not found"; exit 1; }
command -v eksctl >/dev/null || { echo "ERROR: eksctl not found"; exit 1; }
command -v helm >/dev/null || { echo "ERROR: Helm not found"; exit 1; }

echo "All required tools are available."

echo ""
echo "========================================"
echo "Start script initialized successfully"
echo "========================================"
echo ""
echo "Checking EKS cluster..."

if aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" >/dev/null 2>&1
then
    echo "EKS cluster already exists."
    echo "Using existing cluster."
else
    echo "EKS cluster does not exist."
    echo "Creating EKS cluster..."

    eksctl create cluster -f "$PROJECT_DIR/eks-cluster.yaml"

    echo "EKS cluster created."
fi
echo ""
echo "Updating kubeconfig..."

aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME"

echo "Kubeconfig updated successfully."
echo ""
echo "Waiting for EKS cluster to become ACTIVE..."

aws eks wait cluster-active \
  --name "$CLUSTER_NAME" \
  --region "$REGION"

echo "EKS cluster is ACTIVE."
echo ""
echo "Checking EKS nodes..."

kubectl get nodes

echo ""
echo "Node check completed."
echo ""
echo "Checking AWS Load Balancer Controller..."

if kubectl get deployment aws-load-balancer-controller -n kube-system >/dev/null 2>&1
then
    echo "AWS Load Balancer Controller already exists."
else
    echo "Installing AWS Load Balancer Controller..."

    helm repo add eks https://aws.github.io/eks-charts
    helm repo update

    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      --set clusterName="$CLUSTER_NAME" \
      --set serviceAccount.create=false \
      --set serviceAccount.name=aws-load-balancer-controller

    echo "AWS Load Balancer Controller installed."
fi
echo ""
echo "Checking EBS CSI driver..."

echo ""
echo "Checking EBS CSI driver..."

if aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --region "$REGION" >/dev/null 2>&1
then
    echo "EBS CSI driver already exists."
else
    echo "Installing EBS CSI driver..."

    aws eks create-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name aws-ebs-csi-driver \
      --region "$REGION"

    echo "EBS CSI driver installation started."
fi

echo ""
echo "Waiting for EBS CSI driver to become ACTIVE..."

aws eks wait addon-active \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --region "$REGION"

echo "EBS CSI driver is ACTIVE."

echo ""
echo "Creating application namespace..."

kubectl create namespace three-tier \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Namespace ready."

echo ""
echo "Deploying MongoDB..."

kubectl apply -f "$K8S_DIR/Database/secrets.yaml"
kubectl apply -f "$K8S_DIR/Database/pvc.yaml"

echo "Waiting for MongoDB PVC..."

for i in {1..30}
do
    PVC_STATUS=$(kubectl get pvc mongo-volume-claim \
      -n three-tier \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)

    if [ "$PVC_STATUS" = "Bound" ]
    then
        echo "MongoDB PVC is Bound."
        break
    fi

    echo "PVC status: ${PVC_STATUS:-Pending}. Waiting..."
    sleep 10
done

if [ "$PVC_STATUS" != "Bound" ]
then
    echo "ERROR: MongoDB PVC did not become Bound."
    kubectl get pvc -n three-tier
    exit 1
fi

kubectl apply -f "$K8S_DIR/Database/deployment.yaml"
kubectl apply -f "$K8S_DIR/Database/service.yaml"

echo "MongoDB deployment applied."

echo ""
echo "Deploying backend..."

kubectl apply -f "$K8S_DIR/Backend/deployment.yaml"
kubectl apply -f "$K8S_DIR/Backend/service.yaml"

echo "Backend deployment applied."

echo ""
echo "Deploying frontend..."

kubectl apply -f "$K8S_DIR/Frontend/deployment.yaml"
kubectl apply -f "$K8S_DIR/Frontend/service.yaml"

echo "Frontend deployment applied."

echo ""
echo "Deploying Ingress..."

kubectl apply -f "$K8S_DIR/ingress.yaml"

echo "Ingress applied."

echo ""
echo "Waiting for application deployments..."

kubectl rollout status deployment/mongodb \
  -n three-tier \
  --timeout=180s

kubectl rollout status deployment/api \
  -n three-tier \
  --timeout=180s

kubectl rollout status deployment/frontend \
  -n three-tier \
  --timeout=180s

echo ""
echo "========================================"
echo " Application status"
echo "========================================"

kubectl get pods -n three-tier

echo ""
echo "Services:"
kubectl get svc -n three-tier

echo ""
echo "Persistent Volume Claim:"
kubectl get pvc -n three-tier

echo ""
echo "Ingress:"
kubectl get ingress -n three-tier

echo ""
echo "Checking ALB hostname..."

ALB_HOSTNAME=$(kubectl get ingress mainlb \
  -n three-tier \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

if [ -n "$ALB_HOSTNAME" ]
then
    echo ""
    echo "ALB HOSTNAME:"
    echo "$ALB_HOSTNAME"
else
    echo ""
    echo "ALB hostname is not available yet."
    echo "Run this later:"
    echo "kubectl get ingress mainlb -n three-tier"
fi

echo ""
echo "========================================"
echo " Three-Tier Project Started"
echo "========================================"
