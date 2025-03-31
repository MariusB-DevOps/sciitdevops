
# DevOps Platform Automation - AWS & Azure

Acest proiect automatizează deploy-ul unei infrastructuri complete în AWS și Azure, folosind Terraform, Ansible, GitHub Actions, ArgoCD și Jenkins.

## 📁 Structură proiect

```
.
├── .github/workflows/          # GitHub Actions pentru deploy/destroy în AWS & Azure
├── aws/                        # Deploy în AWS: Terraform + Ansible
├── Azure/                      # Deploy în Azure: Terraform + Ansible
├── Jenkinsfile                 # Pipeline principal Jenkins
├── pipeline.xml                # Configurație pentru Jenkins
```

## 🔧 Tehnologii folosite

- **Terraform**: Provisioning resurse (EKS/AKS, ALB, Route 53 etc.)
- **Ansible**: Configurare aplicații (ArgoCD, Jenkins, NGINX, Prometheus, Grafana)
- **GitHub Actions**: CI/CD complet automatizat
- **ArgoCD**: Deploy continuu în Kubernetes
- **Jenkins**: CI pentru build-uri și deploy în ArgoCD
- **Prometheus & Grafana**: Monitorizare
- **NGINX**: Webserver de test

## 🚀 Workflows

| Workflow              | Scop                         |
|----------------------|------------------------------|
| `aws-deploy.yaml`    | Deploy complet în AWS        |
| `aws-destroy.yaml`   | Distrugere infrastructură AWS|
| `aks-deploy.yaml`    | Deploy complet în Azure      |
| `aks-destroy.yaml`   | Distrugere infrastructură AKS|

## 🔐 Acces și autentificare

- Credentialele pentru GitHub, AWS și Azure sunt gestionate prin Secrets.
- Parolele și IP-urile sunt salvate automat în:
  - **AWS**: SSM Parameter Store
  - **Azure**: Key Vault

## 📦 Output-uri generate

- Link-uri ArgoCD, Jenkins, Grafana și NGINX
- Parole de admin
- DNS public configurat automat (ex: `jenkins.k8s.it.com`)

---

## ℹ️ Informații suplimentare

Pentru detalii specifice despre deploy-ul în AWS sau Azure, vezi fișierele:

- [`aws/README.md`](aws/README.md)
- [`Azure/README.md`](Azure/README.md)
