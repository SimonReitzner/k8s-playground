#!/bin/bash

# Exit the script if any command fails
set -e

# Define the path to the config.yaml file
CONFIG_FILE="config.yaml"

# Parse master and worker node information using yq
MASTER_NAME=$(yq '.nodes.master.name' "$CONFIG_FILE")
MASTER_IP=$(yq '.nodes.master.ip' "$CONFIG_FILE")
MASTER_IDENTITY_FILE=$(yq '.nodes.master.identity_file' "$CONFIG_FILE")
WORKER_NAME=$(yq '.nodes.worker.name' "$CONFIG_FILE")

# Define local directories where certificates will be copied
LOCAL_CERT_DIR="$HOME/.kubeadm"
KUBECONFIG_FILE="$HOME/.kube/config"

# Ensure base directory exists
mkdir -p "$LOCAL_CERT_DIR"

# Step 1: Process the master node
echo "Processing $MASTER_NAME..."

LOCAL_VM_DIR="$LOCAL_CERT_DIR/$MASTER_NAME"
mkdir -p "$LOCAL_VM_DIR"

# Copy admin.conf to an accessible folder in the VM and bring it to the local machine
echo "Preparing $MASTER_NAME admin.conf for copying..."
ssh -i "$MASTER_IDENTITY_FILE" vagrant@$MASTER_IP "sudo cp /etc/kubernetes/admin.conf /home/vagrant/admin.conf && sudo chown vagrant:vagrant /home/vagrant/admin.conf"

echo "Copying $MASTER_NAME admin.conf to local machine..."
scp -i "$MASTER_IDENTITY_FILE" vagrant@$MASTER_IP:/home/vagrant/admin.conf "$LOCAL_VM_DIR/admin.conf"

# Extract and decode certificates and keys from the admin.conf file
echo "Extracting certificates from $MASTER_NAME admin.conf..."
CA_CERT=$(awk '/certificate-authority-data/ {print $2}' "$LOCAL_VM_DIR/admin.conf" | base64 --decode)
CLIENT_CERT=$(awk '/client-certificate-data/ {print $2}' "$LOCAL_VM_DIR/admin.conf" | base64 --decode)
CLIENT_KEY=$(awk '/client-key-data/ {print $2}' "$LOCAL_VM_DIR/admin.conf" | base64 --decode)

# Save the decoded certificates and keys to files
echo "$CA_CERT" > "$LOCAL_VM_DIR/$MASTER_NAME-ca.crt"
echo "$CLIENT_CERT" > "$LOCAL_VM_DIR/$MASTER_NAME-client.crt"
echo "$CLIENT_KEY" > "$LOCAL_VM_DIR/$MASTER_NAME-client.key"

# Step 2: Add cluster, user, and context entries to the kubeconfig for the master node
echo "Adding $MASTER_NAME cluster and context to kubeconfig..."
kubectl config set-cluster "$MASTER_NAME" \
  --certificate-authority="$LOCAL_VM_DIR/$MASTER_NAME-ca.crt" \
  --embed-certs=true \
  --server=https://$MASTER_IP:6443 \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config set-credentials "$MASTER_NAME" \
  --client-certificate="$LOCAL_VM_DIR/$MASTER_NAME-client.crt" \
  --client-key="$LOCAL_VM_DIR/$MASTER_NAME-client.key" \
  --embed-certs=true \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config set-context "$MASTER_NAME" \
  --cluster="$MASTER_NAME" \
  --user="$MASTER_NAME" \
  --namespace=default \
  --kubeconfig="$KUBECONFIG_FILE"

# Switch current context to the master node
kubectl config use-context "$MASTER_NAME" --kubeconfig="$KUBECONFIG_FILE"

# Confirm successful processing
echo "$MASTER_NAME has been processed successfully."

# Step 4: Label the worker node with the 'worker' role after it joins
echo "Labeling $WORKER_NAME with worker role..."
kubectl label node "$WORKER_NAME" node-role.kubernetes.io/worker=worker

# Confirm successful labeling
echo "$WORKER_NAME has been labeled as a worker."
