#!/bin/bash
set -e

##############
# VARIABLES #
#############
MON_SECRET_NAME=rook-ceph-mon
RGW_ADMIN_OPS_USER_SECRET_NAME=rgw-admin-ops-user
MON_SECRET_CLUSTER_NAME_KEYNAME=cluster-name
MON_SECRET_FSID_KEYNAME=fsid
MON_SECRET_ADMIN_KEYRING_KEYNAME=admin-secret
MON_SECRET_MON_KEYRING_KEYNAME=mon-secret
MON_SECRET_CEPH_USERNAME_KEYNAME=ceph-username
MON_SECRET_CEPH_SECRET_KEYNAME=ceph-secret
MON_ENDPOINT_CONFIGMAP_NAME=rook-ceph-mon-endpoints
ROOK_EXTERNAL_CLUSTER_NAME=$NAMESPACE
ROOK_EXTERNAL_MAX_MON_ID=2
ROOK_EXTERNAL_MAPPING={}
RBD_STORAGE_CLASS_NAME=ceph-rbd
CEPHFS_STORAGE_CLASS_NAME=cephfs
ROOK_EXTERNAL_MONITOR_SECRET=mon-secret
OPERATOR_NAMESPACE=rook-ceph # default set to rook-ceph
RBD_PROVISIONER=$OPERATOR_NAMESPACE".rbd.csi.ceph.com" # driver:namespace:operator
CEPHFS_PROVISIONER=$OPERATOR_NAMESPACE".cephfs.csi.ceph.com" # driver:namespace:operator
CLUSTER_ID_RBD=$NAMESPACE
CLUSTER_ID_CEPHFS=$NAMESPACE
: "${ROOK_EXTERNAL_ADMIN_SECRET:=admin-secret}"

#############
# FUNCTIONS #
#############

function checkEnvVars() {
  if [ -z "$NAMESPACE" ]; then
    echo "Please populate the environment variable NAMESPACE"
    exit 1
  fi
   if [ -z "$RBD_POOL_NAME" ]; then
    echo "Please populate the environment variable RBD_POOL_NAME"
    exit 1
  fi
  if [ -z "$CSI_RBD_NODE_SECRET_NAME" ]; then
    echo "Please populate the environment variable CSI_RBD_NODE_SECRET_NAME"
    exit 1
  fi
  if [ -z "$CSI_RBD_PROVISIONER_SECRET_NAME" ]; then
    echo "Please populate the environment variable CSI_RBD_PROVISIONER_SECRET_NAME"
    exit 1
  fi
  if [ -z "$CSI_CEPHFS_NODE_SECRET_NAME" ]; then
    echo "Please populate the environment variable CSI_CEPHFS_NODE_SECRET_NAME"
    exit 1
  fi
  if [ -z "$CSI_CEPHFS_PROVISIONER_SECRET_NAME" ]; then
    echo "Please populate the environment variable CSI_CEPHFS_PROVISIONER_SECRET_NAME"
    exit 1
  fi
  if [ -z "$ROOK_EXTERNAL_FSID" ]; then
    echo "Please populate the environment variable ROOK_EXTERNAL_FSID"
    exit 1
  fi
  if [ -z "$ROOK_EXTERNAL_CEPH_MON_DATA" ]; then
    echo "Please populate the environment variable ROOK_EXTERNAL_CEPH_MON_DATA"
    exit 1
  fi
  if [[ "$ROOK_EXTERNAL_ADMIN_SECRET" == "admin-secret" ]]; then
    if [ -z "$ROOK_EXTERNAL_USER_SECRET" ]; then
      echo "Please populate the environment variable ROOK_EXTERNAL_USER_SECRET"
      exit 1
    fi
    if [ -z "$ROOK_EXTERNAL_USERNAME" ]; then
      echo "Please populate the environment variable ROOK_EXTERNAL_USERNAME"
      exit 1
    fi
    if [ -z "$CSI_RBD_NODE_SECRET" ]; then
      echo "Please populate the environment variable CSI_RBD_NODE_SECRET"
      exit 1
    fi
    if [ -z "$CSI_RBD_PROVISIONER_SECRET" ]; then
      echo "Please populate the environment variable CSI_RBD_PROVISIONER_SECRET"
      exit 1
    fi
    if [ -z "$CSI_CEPHFS_NODE_SECRET" ]; then
      echo "Please populate the environment variable CSI_CEPHFS_NODE_SECRET"
      exit 1
    fi
    if [ -z "$CSI_CEPHFS_PROVISIONER_SECRET" ]; then
      echo "Please populate the environment variable CSI_CEPHFS_PROVISIONER_SECRET"
      exit 1
    fi
  fi
  if [[ "$ROOK_EXTERNAL_ADMIN_SECRET" != "admin-secret" ]] && [ -n "$ROOK_EXTERNAL_USER_SECRET" ] ; then
    echo "Providing both ROOK_EXTERNAL_ADMIN_SECRET and ROOK_EXTERNAL_USER_SECRET is not supported, choose one only."
    exit 1
  fi
}

function importClusterID() {
  if [ -n "$RADOS_NAMESPACE_CLUSTER_ID" ]; then
    CLUSTER_ID_RBD=$(kubectl -n "$NAMESPACE" get cephblockpoolradosnamespace.ceph.rook.io/"$RADOS_NAMESPACE_CLUSTER_ID" -o jsonpath='{.status.info.clusterID}')
  fi
  if [ -n "$SUBVOLUME_GROUP_CLUSTER_ID" ]; then
    CLUSTER_ID_CEPHFS=$(kubectl -n "$NAMESPACE" get cephfilesystemsubvolumegroup.ceph.rook.io/"$SUBVOLUME_GROUP_CLUSTER_ID" -o jsonpath='{.status.info.clusterID}')
  fi
}

function importSecret() {
  kubectl -n "$NAMESPACE" \
  create \
  secret \
  generic \
  --type="kubernetes.io/rook" \
  "$MON_SECRET_NAME" \
  --from-literal="$MON_SECRET_CLUSTER_NAME_KEYNAME"="$ROOK_EXTERNAL_CLUSTER_NAME" \
  --from-literal="$MON_SECRET_FSID_KEYNAME"="$ROOK_EXTERNAL_FSID" \
  --from-literal="$MON_SECRET_ADMIN_KEYRING_KEYNAME"="$ROOK_EXTERNAL_ADMIN_SECRET" \
  --from-literal="$MON_SECRET_MON_KEYRING_KEYNAME"="$ROOK_EXTERNAL_MONITOR_SECRET" \
  --from-literal="$MON_SECRET_CEPH_USERNAME_KEYNAME"="$ROOK_EXTERNAL_USERNAME" \
  --from-literal="$MON_SECRET_CEPH_SECRET_KEYNAME"="$ROOK_EXTERNAL_USER_SECRET"
}

function importConfigMap() {
  kubectl -n "$NAMESPACE" \
  create \
  configmap \
  "$MON_ENDPOINT_CONFIGMAP_NAME" \
  --from-literal=data="$ROOK_EXTERNAL_CEPH_MON_DATA" \
  --from-literal=mapping="$ROOK_EXTERNAL_MAPPING" \
  --from-literal=maxMonId="$ROOK_EXTERNAL_MAX_MON_ID"
}

function importCsiRBDNodeSecret() {
  kubectl -n "$NAMESPACE" \
  create \
  secret \
  generic \
  --type="kubernetes.io/rook" \
  "rook-""$CSI_RBD_NODE_SECRET_NAME" \
  --from-literal=userID="$CSI_RBD_NODE_SECRET_NAME" \
  --from-literal=userKey="$CSI_RBD_NODE_SECRET"
}

function importCsiRBDProvisionerSecret() {
  kubectl -n "$NAMESPACE" \
  create \
  secret \
  generic \
  --type="kubernetes.io/rook" \
  "rook-""$CSI_RBD_PROVISIONER_SECRET_NAME" \
  --from-literal=userID="$CSI_RBD_PROVISIONER_SECRET_NAME" \
  --from-literal=userKey="$CSI_RBD_PROVISIONER_SECRET"
}

function importCsiCephFSNodeSecret() {
  kubectl -n "$NAMESPACE" \
  create \
  secret \
  generic \
  --type="kubernetes.io/rook" \
  "rook-""$CSI_CEPHFS_NODE_SECRET_NAME" \
  --from-literal=adminID="$CSI_CEPHFS_NODE_SECRET_NAME" \
  --from-literal=adminKey="$CSI_CEPHFS_NODE_SECRET"
}

function importCsiCephFSProvisionerSecret() {
  kubectl -n "$NAMESPACE" \
  create \
  secret \
  generic \
  --type="kubernetes.io/rook" \
  "rook-""$CSI_CEPHFS_PROVISIONER_SECRET_NAME" \
  --from-literal=adminID="$CSI_CEPHFS_PROVISIONER_SECRET_NAME" \
  --from-literal=adminKey="$CSI_CEPHFS_PROVISIONER_SECRET"
}

function importRGWAdminOpsUser() {
  kubectl -n "$NAMESPACE" \
  create \
  secret \
  generic \
  --type="kubernetes.io/rook" \
  "$RGW_ADMIN_OPS_USER_SECRET_NAME" \
  --from-literal=accessKey="$RGW_ADMIN_OPS_USER_ACCESS_KEY" \
  --from-literal=secretKey="$RGW_ADMIN_OPS_USER_SECRET_KEY"
}

function createECRBDStorageClass() {
cat <<eof | kubectl create -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $RBD_STORAGE_CLASS_NAME
provisioner: $RBD_PROVISIONER
parameters:
  clusterID: $CLUSTER_ID_RBD
  pool: $RBD_POOL_NAME
  dataPool: $RBD_METADATA_EC_POOL_NAME
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: "rook-$CSI_RBD_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/controller-expand-secret-name:  "rook-$CSI_RBD_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/controller-expand-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/node-stage-secret-name: "rook-$CSI_RBD_NODE_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
eof
}

function createRBDStorageClass() {
cat <<eof | kubectl create -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $RBD_STORAGE_CLASS_NAME
provisioner: $RBD_PROVISIONER
parameters:
  clusterID: $CLUSTER_ID_RBD
  pool: $RBD_POOL_NAME
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: "rook-$CSI_RBD_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/controller-expand-secret-name:  "rook-$CSI_RBD_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/controller-expand-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/node-stage-secret-name: "rook-$CSI_RBD_NODE_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
eof
}

function createCephFSStorageClass() {
cat <<eof | kubectl create -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $CEPHFS_STORAGE_CLASS_NAME
provisioner: $CEPHFS_PROVISIONER
parameters:
  clusterID: $CLUSTER_ID_CEPHFS
  fsName: $CEPHFS_FS_NAME
  pool: $CEPHFS_POOL_NAME
  csi.storage.k8s.io/provisioner-secret-name: "rook-$CSI_CEPHFS_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/controller-expand-secret-name: "rook-$CSI_CEPHFS_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/controller-expand-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/node-stage-secret-name: "rook-$CSI_CEPHFS_NODE_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: $NAMESPACE
allowVolumeExpansion: true
reclaimPolicy: Delete
eof
}

########
# MAIN #
########
checkEnvVars
importClusterID
importSecret
importConfigMap
importCsiRBDNodeSecret
importCsiRBDProvisionerSecret
importCsiCephFSNodeSecret
importCsiCephFSProvisionerSecret
importRGWAdminOpsUser
if [ -n "$RBD_METADATA_EC_POOL_NAME" ]; then
  createECRBDStorageClass
else
  createRBDStorageClass
fi
if [ -n "$CEPHFS_FS_NAME" ] && [ -n "$CEPHFS_POOL_NAME" ]; then
  createCephFSStorageClass
fi
