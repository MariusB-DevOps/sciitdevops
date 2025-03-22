#!/bin/bash

############################################
# Preluăm lista de instanțe EC2
############################################
instance_ids=$(aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId]" --output text)

############################################
# Dacă nu sunt instanțe, afișăm un mesaj și ieșim
############################################

if [ -z "$instance_ids" ]; then
  echo "Nu s-au găsit instanțe EC2."
  exit 1
fi

############################################
# Modificăm IMDS pentru fiecare instanță
############################################

for instance_id in $instance_ids; do
  echo "Activăm IMDS pentru instanța EC2: $instance_id"
  aws ec2 modify-instance-metadata-options --instance-id $instance_id --http-endpoint enabled --http-put-response-hop-limit 2 --http-tokens optional
done

echo "IMDS a fost activat pe toate instanțele EC2."


# Extragem IP-urile instanțelor EC2 asociate clusterului EKS
INSTANCE_IPS=$(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=main-eks-cluster" --query "Reservations[].Instances[].PrivateIpAddress" --output text)

PARAMS_FILE="../../params.txt"

if [ ! -z "$INSTANCE_IPS" ]; then
  echo "### Jenkins Instances ###" >> "$PARAMS_FILE"
  for IP in $INSTANCE_IPS; do
    echo "INSTANCE_IP=$IP" >> "$PARAMS_FILE"
  done
  echo "########################" >> "$PARAMS_FILE"
else
  echo "⚠️ Nu s-au găsit instanțe asociate clusterului EKS."
fi


############################################
# Preluam config cluster eks
############################################

echo "Actualizare config cluster eks."
aws eks --region eu-west-1 update-kubeconfig --name main-eks-cluster

############################################
# Creez namespace pentru jenkins
############################################

echo "Creez namespace pentru jenkins"
kubectl apply -f namespace.yaml

############################################
# Creez Ingress pentru jenkins
############################################

echo "Creez IngressClass pentru jenkins"
kubectl apply -f ingressclass.yaml

############################################
# Creez IngressClass pentru jenkins
############################################

echo "Creez Ingress pentru jenkins"
kubectl apply -f ingress.yaml

############################################
# Deploy jenkins
############################################

echo "Fac deploy de jenkins"
kubectl apply -f jenkins-app.yaml

############################################
#Extrag IP-urile pod-urilor Jenkins
############################################

MAX_RETRIES=10
RETRY_INTERVAL=30
attempt=0
POD_IPS=""

while [[ -z "$POD_IPS" && $attempt -lt $MAX_RETRIES ]]; do
  echo "Verificare IP-uri pentru pod-ul Jenkins (încercare $((attempt + 1)) din $MAX_RETRIES)..."
  
  POD_IPS=$(kubectl get pod -n jenkins -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[*].status.podIP}')
  
  if [[ -z "$POD_IPS" ]]; then
    attempt=$((attempt + 1))
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      echo "Pod-ul Jenkins nu are IP încă. Așteptăm $RETRY_INTERVAL secunde înainte de o nouă încercare..."
      sleep $RETRY_INTERVAL
    else
      echo "❌ Eroare: Nu am putut obține IP-urile pentru pod-ul Jenkins după $MAX_RETRIES încercări."
      exit 1
    fi
  fi
done

echo "✅ IP-uri pentru pod-ul Jenkins obținute: $POD_IPS"

############################################
#POD_IPS=$(kubectl get pod -n jenkins -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[*].status.podIP}')

############################################
# Extragem ARN-ul target group-ului
############################################

TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --query 'TargetGroups[?TargetGroupName==`jenkins-tg`].TargetGroupArn' --output text 2>/dev/null || true)

############################################
# Crează lista de targets pentru LB
############################################

echo "Creez lista de targets pentru LB"
TARGETS=$(echo $POD_IPS | xargs -n 1 -I {} echo "Id={}")

############################################
# Înregistrează toate IP-urile în target group  
############################################

echo "Aplic targets pe LB"
aws elbv2 register-targets --target-group-arn $TARGET_GROUP_ARN --targets $TARGETS
