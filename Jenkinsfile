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

        TRIVY_SEVERITY = 'HIGH,CRITICAL'
        TRIVY_REPORT_DIR = 'reports'
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
                    set -eu

                    chmod +x mvnw
                    ./mvnw clean verify -B
                '''
            }
        }

        stage('Trivy Filesystem Security Scan') {
            steps {
                echo 'Scanning project dependencies for HIGH and CRITICAL vulnerabilities...'

                sh '''
                    set -eu

                    mkdir -p "${TRIVY_REPORT_DIR}"

                    # Generate JSON report without stopping the pipeline.
                    trivy fs \
                        --config trivy.yaml \
                        --scanners vuln \
                        --severity "${TRIVY_SEVERITY}" \
                        --format json \
                        --output "${TRIVY_REPORT_DIR}/trivy-filesystem.json" \
                        --exit-code 0 \
                        .

                    # Enforce the security gate.
                    trivy fs \
                        --config trivy.yaml \
                        --scanners vuln \
                        --severity "${TRIVY_SEVERITY}" \
                        --exit-code 1 \
                        .
                '''
            }
        }

        stage('Docker Build') {
            steps {
                echo 'Building Docker image...'

                sh '''
                    set -eu

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
                    set -eu

                    docker image inspect ${DOCKER_IMAGE}:${DOCKER_TAG}
                    docker images ${DOCKER_IMAGE}
                '''
            }
        }

        stage('Trivy Docker Image Security Scan') {
            steps {
                echo 'Scanning Docker image for vulnerabilities and secrets...'

                sh '''
                    set -eu

                    mkdir -p "${TRIVY_REPORT_DIR}"

                    # Generate JSON report.
                    trivy image \
                        --config trivy.yaml \
                        --scanners vuln,secret \
                        --severity "${TRIVY_SEVERITY}" \
                        --format json \
                        --output "${TRIVY_REPORT_DIR}/trivy-image.json" \
                        --exit-code 0 \
                        ${DOCKER_IMAGE}:${DOCKER_TAG}

                    # Enforce the vulnerability security gate.
                    trivy image \
                        --config trivy.yaml \
                        --scanners vuln,secret \
                        --severity "${TRIVY_SEVERITY}" \
                        --exit-code 1 \
                        ${DOCKER_IMAGE}:${DOCKER_TAG}
                '''
            }
        }

        stage('Load Image into kind') {
            steps {
                echo 'Loading Docker image into Kubernetes cluster...'

                sh '''
                    set -eu

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
                    set -eu

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
                    set -eu

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
            echo """
            ==========================================
                 CI/CD PIPELINE COMPLETED
            ==========================================
            Docker image: ${DOCKER_IMAGE}:${DOCKER_TAG}
            Kubernetes namespace: ${K8S_NAMESPACE}
            Deployment: ${K8S_DEPLOYMENT}
            Security scans: PASSED
            ==========================================
            """
        }

        failure {
            echo 'CI/CD pipeline failed. Check the stage logs and security reports.'
        }

        always {
            archiveArtifacts(
                artifacts: 'reports/trivy-*.json',
                allowEmptyArchive: true,
                fingerprint: true
            )

            echo 'Pipeline execution finished.'
        }
    }
}
