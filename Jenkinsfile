pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'ai-bankapp'
        DOCKER_TAG = "ci-${BUILD_NUMBER}"

        KIND_CLUSTER = 'aws-devops-local'
        K8S_NAMESPACE = 'bankapp'
        K8S_DEPLOYMENT = 'bankapp'
        K8S_CONTAINER = 'bankapp'
        K8S_SERVICE = 'bankapp'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out source code...'
                checkout scm
            }
        }

        stage('Build and Test') {
            steps {
                echo 'Building and testing Spring Boot application...'

                sh '''
                    chmod +x mvnw
                    ./mvnw clean verify -B
                '''
            }
        }

        stage('Docker Build') {
            steps {
                echo 'Building Docker image...'

                sh '''
                    docker build \
                        -t ${DOCKER_IMAGE}:${DOCKER_TAG} \
                        -t ${DOCKER_IMAGE}:latest .
                '''
            }
        }

        stage('Docker Image Validation') {
            steps {
                echo 'Validating Docker image...'

                sh '''
                    docker image inspect ${DOCKER_IMAGE}:${DOCKER_TAG}
                    docker images ${DOCKER_IMAGE}
                '''
            }
        }

        stage('Load Image into kind') {
            steps {
                echo 'Loading Docker image into Kubernetes cluster...'

                sh '''
                    kind load docker-image \
                        ${DOCKER_IMAGE}:${DOCKER_TAG} \
                        --name ${KIND_CLUSTER}
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo 'Deploying BankApp to Kubernetes...'

                sh '''
                    kubectl set image \
                        deployment/${K8S_DEPLOYMENT} \
                        ${K8S_CONTAINER}=${DOCKER_IMAGE}:${DOCKER_TAG} \
                        -n ${K8S_NAMESPACE}
                '''
            }
        }

        stage('Kubernetes Rollout Verification') {
            steps {
                echo 'Waiting for Kubernetes rollout...'

                sh '''
                    kubectl rollout status \
                        deployment/${K8S_DEPLOYMENT} \
                        -n ${K8S_NAMESPACE} \
                        --timeout=240s

                    kubectl get pods -n ${K8S_NAMESPACE}
                '''
            }
        }

        stage('Application Health Check') {
            steps {
                echo 'Checking BankApp application health...'

                sh '''
                    set -eu

                    PORT=18082
                    LOG_FILE=$(mktemp)

                    kubectl port-forward \
                        -n ${K8S_NAMESPACE} \
                        service/${K8S_SERVICE} \
                        ${PORT}:8080 > "$LOG_FILE" 2>&1 &

                    PF_PID=$!

                    cleanup() {
                        kill "$PF_PID" 2>/dev/null || true
                        rm -f "$LOG_FILE"
                    }

                    trap cleanup EXIT

                    HEALTHY=false

                    for i in $(seq 1 30); do
                        if curl -fsS \
                            http://127.0.0.1:${PORT}/actuator/health \
                            -o /tmp/bankapp-health.json; then

                            if grep -q '"status":"UP"' \
                                /tmp/bankapp-health.json; then

                                HEALTHY=true
                                break
                            fi
                        fi

                        sleep 2
                    done

                    if [ "$HEALTHY" != "true" ]; then
                        echo "Application health check failed."
                        cat "$LOG_FILE"
                        cat /tmp/bankapp-health.json 2>/dev/null || true
                        exit 1
                    fi

                    echo "Application health check successful!"
                    cat /tmp/bankapp-health.json

                    rm -f /tmp/bankapp-health.json
                '''
            }
        }
    }

    post {
        success {
            echo '''
            ==========================================
                 CI/CD PIPELINE COMPLETED
            ==========================================
            Docker image: ${DOCKER_IMAGE}:${DOCKER_TAG}
            Kubernetes namespace: ${K8S_NAMESPACE}
            Deployment: ${K8S_DEPLOYMENT}
            ==========================================
            '''
        }

        failure {
            echo 'CI/CD pipeline failed. Check the stage logs.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
