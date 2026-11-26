pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'ai-bankapp'
        DOCKER_TAG = 'ci-${BUILD_NUMBER}'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out the source code...'
                checkout scm
            }
        }

        stage('Build and Test') {
            steps {
                echo 'Building and testing the Spring Boot application...'
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
    }

    post {
        success {
            echo 'CI pipeline completed successfully!'
        }

        failure {
            echo 'CI pipeline failed. Check the stage logs.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
