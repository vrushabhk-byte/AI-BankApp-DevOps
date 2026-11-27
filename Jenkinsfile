pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        DOCKER_IMAGE = 'ai-bankapp'
        DOCKER_TAG = "ci-${BUILD_NUMBER}"

        K8S_CLUSTER = 'aws-devops-local'
        K8S_NAMESPACE = 'bankapp'
        K8S_DEPLOYMENT = 'bankapp'
        K8S_CONTAINER = 'bankapp'
        K8S_SERVICE = 'bankapp'

        SONAR_PROJECT_KEY = 'ai-bankapp-devops'
        SONAR_SERVER = 'SonarQube-Local'

        TRIVY_SEVERITY = 'HIGH,CRITICAL'
        TRIVY_REPORT_DIR = 'reports'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out source code...'

                checkout scm

                sh '''
                    set -eu

                    rm -f .rollback-previous-image
                    rm -f .deployment-attempted

                    echo "Git revision:"
                    git rev-parse --short=7 HEAD
                '''
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

        stage('SonarQube Analysis') {
            steps {
                echo 'Running SonarQube code quality analysis...'

                withSonarQubeEnv("${SONAR_SERVER}") {
                    sh '''
                        set -eu

                        ./mvnw \
                            org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
                            -Dsonar.projectKey="${SONAR_PROJECT_KEY}" \
                            -Dsonar.projectName="AI-BankApp-DevOps"
                    '''
                }
            }
        }

        stage('SonarQube Quality Gate') {
            steps {
                echo 'Waiting for SonarQube Quality Gate result...'

                timeout(time: 10, unit: 'MINUTES') {
                    script {
                        def qualityGate = waitForQualityGate()

                        echo "SonarQube Quality Gate: ${qualityGate.status}"

                        if (qualityGate.status != 'OK') {
                            error "SonarQube Quality Gate failed: ${qualityGate.status}"
                        }
                    }
                }
            }
        }

        stage('Trivy Filesystem Security Scan') {
            steps {
                echo 'Scanning project dependencies...'

                sh '''
                    set -eu

                    mkdir -p "${TRIVY_REPORT_DIR}"

                    trivy fs \
                        --config trivy.yaml \
                        --scanners vuln \
                        --severity "${TRIVY_SEVERITY}" \
                        --format json \
                        --output "${TRIVY_REPORT_DIR}/filesystem-report.json" \
                        --exit-code 0 \
                        .

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
                        -t "${DOCKER_IMAGE}:${DOCKER_TAG}" \
                        -t "${DOCKER_IMAGE}:latest" \
                        .

                    docker image inspect "${DOCKER_IMAGE}:${DOCKER_TAG}"

                    docker images "${DOCKER_IMAGE}"
                '''
            }
        }

        stage('Docker Image Validation') {
            steps {
                echo 'Validating Docker image...'

                sh '''
                    set -eu

                    docker image inspect \
                        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
                        --format='Image ID: {{.Id}}'

                    docker image inspect \
                        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
                        --format='Image size: {{.Size}} bytes'

                    docker image inspect "${DOCKER_IMAGE}:${DOCKER_TAG}" >/dev/null

                    echo "Docker image validation successful."
                '''
            }
        }

        stage('Trivy Docker Image Security Scan') {
            steps {
                echo 'Scanning Docker image for vulnerabilities and secrets...'

                sh '''
                    set -eu

                    mkdir -p "${TRIVY_REPORT_DIR}"

                    trivy image \
                        --config trivy.yaml \
                        --scanners vuln,secret \
                        --severity "${TRIVY_SEVERITY}" \
                        --format json \
                        --output "${TRIVY_REPORT_DIR}/image-report.json" \
                        --exit-code 0 \
                        "${DOCKER_IMAGE}:${DOCKER_TAG}"

                    trivy image \
                        --config trivy.yaml \
                        --scanners vuln,secret \
                        --severity "${TRIVY_SEVERITY}" \
                        --exit-code 1 \
                        "${DOCKER_IMAGE}:${DOCKER_TAG}"
                '''
            }
        }

        stage('Load Image into kind') {
            steps {
                echo 'Loading Docker image into Kubernetes cluster...'

                sh '''
                    set -eu

                    kind load docker-image \
                        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
                        --name "${K8S_CLUSTER}"
                '''
            }
        }

        stage('Capture Previous Deployment') {
            steps {
                echo 'Capturing currently deployed image for rollback...'

                script {
                    def previousImage = sh(
                        script: """
                            kubectl get deployment ${K8S_DEPLOYMENT} \
                                -n ${K8S_NAMESPACE} \
                                -o go-template='{{(index .spec.template.spec.containers 0).image}}'
                        """,
                        returnStdout: true
                    ).trim()

                    echo "Captured previous image: [${previousImage}]"

                    if (!previousImage || previousImage == 'null') {
                        error 'Unable to identify the currently deployed image. Aborting deployment.'
                    }

                    writeFile(
                        file: '.rollback-previous-image',
                        text: previousImage
                    )

                    echo "Previous deployment image saved: ${previousImage}"
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo 'Deploying new BankApp image...'

                script {
                    // Create marker before attempting deployment.
                    // The post-failure handler uses this to decide
                    // whether rollback is necessary.

                    writeFile(
                        file: '.deployment-attempted',
                        text: 'true'
                    )

                    sh '''
                        set -eu

                        kubectl set image \
                            deployment/"${K8S_DEPLOYMENT}" \
                            "${K8S_CONTAINER}"="${DOCKER_IMAGE}:${DOCKER_TAG}" \
                            -n "${K8S_NAMESPACE}"

                        echo "New image deployed: ${DOCKER_IMAGE}:${DOCKER_TAG}"
                    '''
                }
            }
        }

        stage('Kubernetes Rollout Verification') {
            steps {
                echo 'Waiting for Kubernetes rollout...'

                sh '''
                    set -eu

                    kubectl rollout status \
                        deployment/"${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        --timeout=240s

                    echo "Current Kubernetes pods:"

                    kubectl get pods -n "${K8S_NAMESPACE}"
                '''
            }
        }

        stage('Application Health Check') {
            steps {
                echo 'Checking BankApp application health...'

                sh '''
                    set -eu

                    PORT_FORWARD_LOG=$(mktemp)
                    HEALTHY=false
                    PORT_FORWARD_PID=""

                    cleanup() {
                        if [ -n "${PORT_FORWARD_PID}" ]; then
                            kill "${PORT_FORWARD_PID}" 2>/dev/null || true
                        fi

                        rm -f "${PORT_FORWARD_LOG}" /tmp/bankapp-health.json
                    }

                    trap cleanup EXIT

                    kubectl port-forward \
                        service/"${K8S_SERVICE}" \
                        18082:8080 \
                        -n "${K8S_NAMESPACE}" \
                        >"${PORT_FORWARD_LOG}" 2>&1 &

                    PORT_FORWARD_PID=$!

                    for attempt in $(seq 1 30); do

                        if curl -fsS \
                            http://127.0.0.1:18082/actuator/health \
                            -o /tmp/bankapp-health.json; then

                            if grep -q '"status":"UP"' /tmp/bankapp-health.json; then
                                HEALTHY=true
                                break
                            fi
                        fi

                        if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
                            echo "kubectl port-forward process stopped."
                            cat "${PORT_FORWARD_LOG}"
                            exit 1
                        fi

                        sleep 2
                    done

                    if [ "${HEALTHY}" != "true" ]; then
                        echo "Application health check failed."
                        cat "${PORT_FORWARD_LOG}"
                        exit 1
                    fi

                    echo "Application health check successful!"

                    cat /tmp/bankapp-health.json
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
            SonarQube Quality Gate: PASSED
            Trivy security scans: PASSED
            Deployment Health: PASSED
            ==========================================
            """
        }

        failure {
            echo 'CI/CD pipeline failed.'

            script {
                boolean deploymentAttempted =
                    fileExists('.deployment-attempted')

                boolean previousImageAvailable =
                    fileExists('.rollback-previous-image')

                if (deploymentAttempted && previousImageAvailable) {

                    def previousImage = readFile(
                        file: '.rollback-previous-image'
                    ).trim()

                    if (previousImage) {

                        echo """
                        ==========================================
                             AUTOMATIC ROLLBACK STARTED
                        ==========================================
                        Restoring previous image:
                        ${previousImage}
                        ==========================================
                        """

                        int rollbackStatus = sh(
                            returnStatus: true,
                            script: """
                                set -eu

                                kubectl set image \
                                    deployment/"${K8S_DEPLOYMENT}" \
                                    "${K8S_CONTAINER}"="${previousImage}" \
                                    -n "${K8S_NAMESPACE}"

                                kubectl rollout status \
                                    deployment/"${K8S_DEPLOYMENT}" \
                                    -n "${K8S_NAMESPACE}" \
                                    --timeout=240s

                                echo "Rollback deployment status:"

                                kubectl get deployment "${K8S_DEPLOYMENT}" \
                                    -n "${K8S_NAMESPACE}"

                                echo "Rollback pod status:"

                                kubectl get pods \
                                    -n "${K8S_NAMESPACE}" \
                                    -l app=bankapp

                                echo "AUTOMATIC ROLLBACK COMPLETED"
                            """
                        )

                        if (rollbackStatus == 0) {
                            echo """
                            ==========================================
                             AUTOMATIC ROLLBACK COMPLETED
                            ==========================================
                            Restored image: ${previousImage}
                            ==========================================
                            """
                        } else {
                            echo """
                            ==========================================
                             AUTOMATIC ROLLBACK FAILED
                            ==========================================
                             Manual investigation is required.
                            ==========================================
                            """
                        }

                    } else {
                        echo 'Rollback skipped: previous image file is empty.'
                    }

                } else {
                    echo 'Rollback skipped: deployment was not attempted or previous image was unavailable.'
                }
            }
        }

        always {
            archiveArtifacts(
                artifacts: 'reports/*.json',
                allowEmptyArchive: true,
                fingerprint: true
            )

            echo 'Pipeline execution finished.'
        }
    }
}
