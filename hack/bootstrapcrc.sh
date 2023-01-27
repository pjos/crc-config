#!/bin/bash

oc login -u kubeadmin -p $(cat $HOME/.crc/machines/crc/kubeadmin-password)  https://api.crc.testing:6443 || {
  echo "Unable to login ... Aborting ..."
}

# https://github.com/bitnami-labs/sealed-secrets#secret-rotation
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets -n kube-system
helm install sealed-secrets -n kube-system --set-string fullnameOverride=sealed-secrets-controller sealed-secrets/sealed-secrets
oc delete  consolenotifications.console.openshift.io security-notice

#kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.1/cert-manager.yaml

# https://medium.com/@jeesmon/steps-to-install-an-operator-from-command-line-in-openshift-9473039bc92e
oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

while ! oc get crd applications.argoproj.io > /dev/null 2>&1; do
  printf '.'
  sleep 1
done
printf "\r"

oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: devspaces
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: devspaces
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# checlusters.org.eclipse.che

while ! oc get crd checlusters.org.eclipse.che > /dev/null 2>&1; do
  printf '.'
  sleep 1
done
printf "\r"


# https://che.eclipseprojects.io/2022/10/10/@mloriedo-building-container-images.html
oc create -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: eclipse-che
---
apiVersion: org.eclipse.che/v2
kind: CheCluster
metadata:
  finalizers:
  - checluster.che.eclipse.org
  - cheGateway.clusterpermissions.finalizers.che.eclipse.org
  - cheWorkspaces.clusterpermissions.finalizers.che.eclipse.org
  - namespaces-editor.permissions.finalizers.che.eclipse.org
  - devWorkspace.permissions.finalizers.che.eclipse.org
  - oauthclients.finalizers.che.eclipse.org
  - dashboard.clusterpermissions.finalizers.che.eclipse.org
  - consolelink.finalizers.che.eclipse.org
  name: devspaces
  namespace: eclipse-che
spec:
  components:
    cheServer:
      debug: false
      logLevel: INFO
    dashboard: {}
    database:
      credentialsSecretName: postgres-credentials
      externalDb: false
      postgresDb: dbche
      postgresHostName: postgres
      postgresPort: "5432"
      pvc:
        claimSize: 1Gi
    devWorkspace: {}
    devfileRegistry: {}
    imagePuller:
      enable: false
      spec: {}
    metrics:
      enable: true
    pluginRegistry: {}
  containerRegistry: {}
  devEnvironments:
    defaultNamespace:
      template: <username>-devspaces
    secondsOfInactivityBeforeIdling: 18000
    secondsOfRunBeforeIdling: -1
    storage:
      pvcStrategy: per-user
  networking:
    auth:
      gateway:
        configLabels:
          app: che
          component: che-gateway-config
EOF

oc create -f - <<EOF
---
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: container-build
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities:
  - SETUID
  - SETGID
defaultAddCapabilities: null
fsGroup:
  type: MustRunAs
# Temporary workaround for https://github.com/devfile/devworkspace-operator/issues/884
priority: 20
readOnlyRootFilesystem: false
requiredDropCapabilities:
  - KILL
  - MKNOD
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
users: []
groups: []
volumes:
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim
  - projected
  - secret
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: get-n-update-container-build-scc
rules:
- apiGroups:
  - "security.openshift.io"
  resources:
  - "securitycontextconstraints"
  resourceNames:
  - "container-build"
  verbs:
  - "get"
  - "update"
EOF

#while ! oc get sa devworkspace-controller-serviceaccount -n openshift-operators > /dev/null 2>&1; do
#  printf '.'
#  sleep 1
#done
#printf "\r"

#oc adm policy add-cluster-role-to-user \
#       get-n-update-container-build-scc \
#       system:serviceaccount:openshift-operators:devworkspace-controller-serviceaccount
#oc adm policy add-scc-to-user container-build developer

oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cert-manager
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Manual
  name: cert-manager
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

# https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw
# Pilla till cerifikat  
oc create configmap custom-ca --from-file=ca-bundle.crt=$(git rev-parse --show-toplevel)/hack/self-signed/ca.crt  -n openshift-config 
oc patch proxy/cluster --type=merge --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}' 
oc create secret tls domain-cert --cert=$(git rev-parse --show-toplevel)/hack/self-signed/domain.crt --key=$(git rev-parse --show-toplevel)/hack/self-signed/domain.key -n openshift-ingress 
oc patch ingresscontroller.operator default --type=merge -p '{"spec":{"defaultCertificate": {"name": "domain-cert"}}}' -n openshift-ingress-operator 

echo
echo "... this will take a while for CRC to roll out certificate changes ..."
while curl -kf https://console-openshift-console.apps-crc.testing > /dev/null 2>&1 ; do 
  printf '.'
  sleep 1
done  
while ! curl -kf https://console-openshift-console.apps-crc.testing > /dev/null 2>&1 ; do 
  printf '.'
  sleep 1
done  
printf "\r"
crc start 