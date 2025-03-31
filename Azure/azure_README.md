
# Deploy complet în Azure - AKS + ArgoCD + Jenkins + NGINX + Monitorizare

Acest director conține toate componentele necesare pentru a realiza un deploy complet al unei platforme DevOps în Azure, folosind Terraform, Ansible și GitHub Actions.

## 📦 Componente principale

- **Terraform**
  - Provisionare AKS + resurse asociate
  - Salvare output-uri în Azure Key Vault
- **Ansible**
  - Configurare ArgoCD, Jenkins, Prometheus, Grafana, NGINX
  - Integrare DNS automată în AWS Route53
- **GitHub Actions**
  - Pipeline-uri automatizate pentru deploy și destroy

## 🧱 Structură

```
Azure/
├── ansible-playbook/
│   ├── deploy.yaml                   # Playbook principal Ansible
│   ├── Jenkinsfile / pipeline.xml   # Pipeline-uri Jenkins
│   └── roles/
│       ├── argocd/                   # Deploy ArgoCD
│       ├── jenkins/                 # Deploy Jenkins și ConfigMap
│       ├── monitoring_setup/        # Prometheus + Grafana + ServiceMonitor
│       ├── azure_dns_route53/       # Adăugare DNS în Route 53
│       └── send_summary_email/      # Trimitere email la final
├── terraform/
│   └── aks/                          # Terraform pentru cluster AKS
```

## 🌍 DNS Public

După deploy, sunt create automat DNS-uri în Route 53 (AWS) pentru servicii din Azure:

- `argo-azure.k8s.it.com`
- `jenkins-azure.k8s.it.com`
- `grafana-azure.k8s.it.com`
- `app-azure.k8s.it.com`

## 🔐 Output-uri și parole

- Salvate automat în **Azure Key Vault**
- Email automat cu parolele și link-urile generate

## ✉️ Email Summary

Conține:
- URL ArgoCD, Jenkins, Grafana, NGINX
- User + parolă admin pentru fiecare serviciu

## 🛠 Recomandări

- Rulează `deploy.yaml` pentru provisioning complet
- Asigură-te că Terraform folosește backend Azure configurat în `aks/main.tf`
