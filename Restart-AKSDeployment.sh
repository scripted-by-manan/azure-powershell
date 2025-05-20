# -----------------------------------------------------------------------------
# Script Name: Restart-AKSDeployment.sh
# Description:
#   Restarts a Kubernetes deployment inside an AKS cluster using Azure CLI.
#   This script leverages 'az aks command invoke' to perform the restart 
#   inside the cluster, avoiding the need for kubeconfig or kubectl context
#   on the agent. Fully compatible with Azure DevOps Service Principal context.
#
# Key Benefits:
#   - No kubeconfig or RBAC setup required
#   - Uses Azure-native authentication via Service Principal
#   - Ideal for use in DevOps pipelines or CI/CD jobs
# -----------------------------------------------------------------------------

RESOURCE_GROUP="RG-CMFG-P01-PublicTokenizationService-Application"
CLUSTER_NAME="AKS-PR1-OmniChannel"
NAMESPACE="publictokenizationservice"
DEPLOYMENT_NAME="publictokenizationservice-prod"

echo "🔄 Restarting deployment: $DEPLOYMENT_NAME in namespace: $NAMESPACE using SP context..."

az aks command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --command "kubectl rollout restart deployment $DEPLOYMENT_NAME -n $NAMESPACE"

if [ $? -eq 0 ]; then
  echo "✅ Restart triggered successfully via az aks command invoke."
else
  echo "❌ Restart failed. Check logs for details."
  exit 1
fi
