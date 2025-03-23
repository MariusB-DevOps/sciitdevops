#!/bin/bash

set -e

MAX_RETRIES=5
SLEEP_TIME=5

############################################
# Extragem IP-urile instanțelor EC2 (cu retry)
############################################
attempt=0
INSTANCE_IPS=""
while [[ -z "$INSTANCE_IPS" && $attempt -lt $MAX_RETRIES ]]; do
  echo "🔎 Încercare $((attempt + 1))/$MAX_RETRIES: Preiau IP-urile instanțelor EC2..."
  INSTANCE_IPS=$(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=main-eks-cluster" --query "Reservations[].Instances[].PrivateIpAddress" --output text | tr -d '\n' | tr -s ' ')
  
  if [[ -z "$INSTANCE_IPS" ]]; then
    echo "⚠️ Nu s-au găsit IP-uri pentru instanțele EC2. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ -z "$INSTANCE_IPS" ]]; then
  echo "❌ Eroare: Nu s-au găsit IP-uri după $MAX_RETRIES încercări."
  exit 1
fi

############################################
# Scriem în fișier IP-urile instanțelor
############################################
PARAMS_FILE="../../params.txt"
echo "### Jenkins Instances ###" >> "$PARAMS_FILE"
for IP in $INSTANCE_IPS; do
  echo "INSTANCE_IP=$IP" >> "$PARAMS_FILE"
done
echo "########################" >> "$PARAMS_FILE"

############################################
# Actualizare config cluster EKS (cu retry)
############################################
attempt=0
while [[ $attempt -lt $MAX_RETRIES ]]; do
  echo "🔧 Actualizez config cluster EKS (încercare $((attempt + 1)))"
  if aws eks --region eu-west-1 update-kubeconfig --name main-eks-cluster; then
    echo "✅ Config cluster actualizată"
    break
  else
    echo "⚠️ Eroare actualizare cluster. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -eq $MAX_RETRIES ]]; then
  echo "❌ Eroare: Config cluster EKS nu a putut fi actualizată."
  exit 1
fi

############################################
# Creez namespace (cu retry)
############################################
attempt=0
while [[ $attempt -lt $MAX_RETRIES ]]; do
  echo "🔧 Creez namespace (încercare $((attempt + 1)))"
  if kubectl apply -f namespace.yaml; then
    echo "✅ Namespace creat"
    break
  else
    echo "⚠️ Eroare creare namespace. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -eq $MAX_RETRIES ]]; then
  echo "❌ Eroare: Namespace nu a putut fi creat după $MAX_RETRIES încercări."
  exit 1
fi

############################################
# Creez IngressClass (cu retry)
############################################
attempt=0
while [[ $attempt -lt $MAX_RETRIES ]]; do
  echo "🔧 Creez IngressClass (încercare $((attempt + 1)))"
  if kubectl apply -f ingressclass.yaml; then
    echo "✅ IngressClass creat"
    break
  else
    echo "⚠️ Eroare creare IngressClass. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -eq $MAX_RETRIES ]]; then
  echo "❌ Eroare: IngressClass nu a putut fi creat după $MAX_RETRIES încercări."
  exit 1
fi

############################################
# Creez Ingress (cu retry)
############################################
attempt=0
while [[ $attempt -lt $MAX_RETRIES ]]; do
  echo "🔧 Creez Ingress (încercare $((attempt + 1)))"
  if kubectl apply -f ingress.yaml; then
    echo "✅ Ingress creat"
    break
  else
    echo "⚠️ Eroare creare Ingress. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -eq $MAX_RETRIES ]]; then
  echo "❌ Eroare: Ingress nu a putut fi creat după $MAX_RETRIES încercări."
  exit 1
fi

############################################
# Deploy Jenkins (cu retry)
############################################
attempt=0
while [[ $attempt -lt $MAX_RETRIES ]]; do
  echo "🚀 Fac deploy de Jenkins (încercare $((attempt + 1)))"
  if kubectl apply -f jenkins-app.yaml; then
    echo "✅ Jenkins a fost deployat"
    break
  else
    echo "⚠️ Eroare deploy Jenkins. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -eq $MAX_RETRIES ]]; then
  echo "❌ Eroare: Jenkins nu a putut fi deployat după $MAX_RETRIES încercări."
  exit 1
fi

############################################
# Înregistrare target-uri în LB (cu retry)
############################################
attempt=0
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --query 'TargetGroups[?TargetGroupName==`jenkins-tg`].TargetGroupArn' --output text)

while [[ $attempt -lt $MAX_RETRIES ]]; do
  echo "🔧 Înregistrez target-uri în LB (încercare $((attempt + 1)))"
  TARGETS=$(echo $POD_IPS | xargs -n 1 -I {} echo "Id={}")
  
  if aws elbv2 register-targets --target-group-arn $TARGET_GROUP_ARN --targets $TARGETS; then
    echo "✅ Target-uri înregistrate în LB"
    break
  else
    echo "⚠️ Eroare înregistrare target-uri. Retry în $SLEEP_TIME secunde..."
    sleep $SLEEP_TIME
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -eq $MAX_RETRIES ]]; then
  echo "❌ Eroare: Înregistrarea target-urilor în LB a eșuat după $MAX_RETRIES încercări."
  exit 1
fi
