
# Deploy complet în AWS - EKS + ArgoCD + Jenkins + NGINX + Monitorizare

Acest director conține tot ce este necesar pentru a realiza un deploy complet al unei platforme DevOps în AWS folosind Terraform și Ansible.

## 📦 Componente principale

- **Terraform**
  - Provisionare EKS, ALB, Route 53
  - Certificate SSL cu ACM
- **Ansible**
  - Configurare ArgoCD, Jenkins, NGINX, Prometheus, Grafana
  - Automatizare completă prin role
- **GitHub Actions**
  - Declanșare deploy din workflow-uri YAML
- **SSM Parameter Store**
  - Salvare parole, hostname-uri, outputs

## 🧱 Structură

```
aws/
├── ansible.cfg
├── deploy.yaml / destroy.yaml         # Playbook-uri principale
├── inventory.ini
├── roles/
│   ├── terraform/                     # Inițializare infrastructură AWS
│   ├── argocd/                        # Deploy ArgoCD
│   ├── jenkins/                       # Deploy Jenkins (Helm)
│   ├── jenkins_setup/                # Configurare Jenkins (CLI + pluginuri)
│   ├── monitoring_setup/             # Prometheus + Grafana + ServiceMonitor
│   ├── nginx_route53/                # DNS pentru NGINX
│   ├── send_summary_email/           # Trimitere email la final
│   ├── git/                          # Integrare GitHub
│   └── app/                          # Aplicația HTML cu ConfigMap și Ingress
```

## ☁️ Output-uri salvate

Toate output-urile relevante (ALB DNS, parole, URL-uri) sunt stocate în:
- **AWS Systems Manager Parameter Store**

## 🌐 DNS automatizat

Înregistrările DNS sunt create automat în Route 53:
- `argocd.k8s.it.com`
- `jenkins.k8s.it.com`
- `app.k8s.it.com`
- `grafana.k8s.it.com`

## ✉️ Email Summary

La finalul deploy-ului, un email este trimis cu:
- Link-uri ArgoCD, Jenkins, Grafana, NGINX
- Parolele de acces

## 🛠 Recomandări

- Rulează `deploy.yaml` pentru provisioning complet
- Folosește `destroy.yaml` doar pentru ștergere completă și testare
