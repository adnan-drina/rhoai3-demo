# Step 02: RHOAI Platform

Deploys Red Hat OpenShift AI operator and DataScienceCluster.

## Deploy

```bash
./deploy.sh [--wait] [--sync]
```

## Verify

```bash
oc get csv -n redhat-ods-operator
oc get datasciencecluster
```
