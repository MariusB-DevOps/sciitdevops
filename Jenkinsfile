pipeline {
    agent none

    environment {
        GITHUB_REPO = "https://github.com/MariusB-DevOps/sciitdevops.git"
        ARGOCD_FOLDER = "html/nginx"
        ALB_NAME = "jenkins-alb"
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Setup Kubernetes Agent') {
            agent {
                kubernetes {
                    label 'custom-jenkins-agent'
                    yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins/agent: 'true'
spec:
  containers:
    - name: jnlp
      image: 'iroi/k8s:latest'
      resources:
        requests:
          memory: "512Mi"
          cpu: "500m"
        limits:
          memory: "1024Mi"
          cpu: "1000m"
"""
                }
            }
            steps {
                script {
                    node('custom-jenkins-agent') { // 🔥 Menținem pod-ul activ pentru toate stage-urile
                        sh 'echo "✅ Agent configurat corect!"'

                        stage('Clone GitHub Repo') {
                            withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
                                sh '''
                                    git clone https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/MariusB-DevOps/sciitdevops.git repo
                                '''
                            }
                        }

                        stage('Generate ArgoCD Manifests') {
                            sh '''
                                mkdir -p repo/${ARGOCD_FOLDER}

                                cat <<EOF > repo/${ARGOCD_FOLDER}/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      initContainers:
        - name: copy-html
          image: alpine:latest
          command: ["/bin/sh", "-c", "cp -r /src/. /html/"]
          volumeMounts:
            - name: html-volume
              mountPath: /html
            - name: source-volume
              mountPath: /src
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html-volume
              mountPath: /usr/share/nginx/html
            - name: config-volume
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
            - name: tmp-volume
              mountPath: /tmp
          command: ["nginx", "-g", "daemon off;"]

        - name: nginx-exporter
          image: nginx/nginx-prometheus-exporter:0.10.0
          args:
            - "-nginx.scrape-uri=http://127.0.0.1:80/metrics"
          ports:
            - containerPort: 9113

      volumes:
        - name: html-volume
          persistentVolumeClaim:
            claimName: nginx-pvc
        - name: config-volume
          configMap:
            name: nginx-config
        - name: tmp-volume
          emptyDir: {}
        - name: source-volume
          configMap:
            name: nginx-html-configmap
EOF

                                # ✅ PVC pentru persistenta datelor
                                cat <<EOF > repo/${ARGOCD_FOLDER}/nginx-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: gp2
EOF

                                # ✅ Service pentru NGINX
                                cat <<EOF > repo/${ARGOCD_FOLDER}/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: default
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: nginx
EOF

                                # ✅ ArgoCD Application
                                cat <<EOF > repo/${ARGOCD_FOLDER}/argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: '${GITHUB_REPO}'
    targetRevision: HEAD
    path: ${ARGOCD_FOLDER}
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

                                # ✅ ConfigMap pentru nginx.conf
                                cat <<EOF > repo/${ARGOCD_FOLDER}/nginx-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: default
data:
  nginx.conf: |
    worker_processes auto;
    events {
        worker_connections 1024;
    }
    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        sendfile on;
        keepalive_timeout 65;
        gzip on;
        gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

        server {
            listen 80;
            location / {
                root /usr/share/nginx/html;
                index index.html;
                try_files \\$uri \\$uri/ /index.html;
            }

            # ✅ Adăugăm locație pentru exporter
            location /metrics {
                stub_status;
                allow 127.0.0.1;
                deny all;
            }
        }
    }

EOF
                            '''
                        }

                        stage('Create Nginx HTML ConfigMap') {
                          sh '''
                            kubectl delete configmap nginx-html-configmap -n default || true
                            kubectl create configmap nginx-html-configmap --from-file=repo/html/www -n default
                          '''
                        }

                        stage('Commit ArgoCD Files to GitHub') {
                            withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
                                sh '''
                                    cd repo
                                    git config --global user.email "mariusb-jenkins@users.noreply.github.com"
                                    git config --global user.name "Jenkins Automation"
                                    git pull origin main || true
                                    git add ${ARGOCD_FOLDER}/*
                                    git commit -m "Add ArgoCD manifests and proxy params for NGINX" || true
                                    git push origin main
                                '''
                            }
                        }

                        stage('Trigger ArgoCD Sync') {
                            sh '''
                                kubectl apply -f repo/${ARGOCD_FOLDER}/argocd-app.yaml -n argocd
                            '''
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline complete - NGINX deployed with ArgoCD!"
        }
        failure {
            echo "❌ Pipeline failed!"
        }
    }
}