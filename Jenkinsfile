# =============================================================================
# Jenkinsfile – Declarative Pipeline
# Lab 4: Advanced Deployment Strategies & Enterprise DevOps
# =============================================================================
# Pipeline Stages:
#   1. Checkout
#   2. Static Analysis & Lint
#   3. Unit Tests + Coverage
#   4. Integration Tests
#   5. Security Scan (Trivy)
#   6. Build Docker Image
#   7. Push to Registry
#   8. Blue-Green Deploy (Kubernetes)
#   9. Smoke Test
#  10. Promote / Rollback Decision
#  11. Canary Deploy (optional gate)
#  12. Performance Test
#  13. Notify
# =============================================================================

pipeline {

    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-agent
spec:
  serviceAccountName: jenkins-agent-sa
  containers:
  - name: python
    image: python:3.12-slim
    command: ['cat']
    tty: true
  - name: docker
    image: docker:24-dind
    securityContext:
      privileged: true
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
  - name: kubectl
    image: bitnami/kubectl:1.30
    command: ['cat']
    tty: true
  - name: trivy
    image: aquasec/trivy:0.52.2
    command: ['cat']
    tty: true
"""
        }
    }

    // ── Environment Variables ─────────────────────────────────────────────────
    environment {
        // Registry & image
        REGISTRY         = "ghcr.io/your-org"
        IMAGE_NAME       = "sample-app"
        IMAGE_TAG        = "${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE       = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

        // Kubernetes
        NAMESPACE        = "devops-lab"
        KUBECONFIG       = credentials("kubeconfig-prod")

        // Credentials (stored in Jenkins Credential Store / Vault)
        REGISTRY_CREDS   = credentials("ghcr-credentials")
        SLACK_WEBHOOK    = credentials("slack-webhook-url")

        // Feature flags
        RUN_PERF_TESTS   = "true"
        CANARY_WEIGHT    = "10"    // % traffic to canary
        CANARY_THRESHOLD = "1.0"  // max error-rate % before auto-rollback
    }

    options {
        timeout(time: 45, unit: "MINUTES")
        buildDiscarder(logRotator(numToKeepStr: "10"))
        disableConcurrentBuilds()
        timestamps()
    }

    // ── Triggers ──────────────────────────────────────────────────────────────
    triggers {
        // Poll SCM every 5 min; replace with webhook for production
        pollSCM("H/5 * * * *")
    }

    stages {

        // ── 1. Checkout ───────────────────────────────────────────────────────
        stage("Checkout") {
            steps {
                checkout scm
                script {
                    env.GIT_BRANCH   = sh(script: "git rev-parse --abbrev-ref HEAD", returnStdout: true).trim()
                    env.GIT_AUTHOR   = sh(script: "git log -1 --format='%an'",       returnStdout: true).trim()
                    env.COMMIT_MSG   = sh(script: "git log -1 --format='%s'",         returnStdout: true).trim()
                    echo "Branch: ${env.GIT_BRANCH} | Author: ${env.GIT_AUTHOR}"
                }
            }
        }

        // ── 2. Static Analysis & Lint ─────────────────────────────────────────
        stage("Lint & Static Analysis") {
            steps {
                container("python") {
                    sh """
                        pip install --quiet flake8 bandit pylint
                        echo '=== flake8 ===' && flake8 app/ --max-line-length=120 || true
                        echo '=== bandit security lint ===' && bandit -r app/ -ll
                        echo '=== pylint ===' && pylint app/app.py --fail-under=7.0 || true
                    """
                }
            }
        }

        // ── 3. Unit Tests ─────────────────────────────────────────────────────
        stage("Unit Tests") {
            steps {
                container("python") {
                    sh """
                        pip install --quiet -r app/requirements.txt
                        pytest tests/unit/ -v \
                            --cov=app \
                            --cov-report=xml:reports/coverage.xml \
                            --cov-report=html:reports/coverage_html \
                            --junitxml=reports/unit_results.xml \
                            --cov-fail-under=80
                    """
                }
            }
            post {
                always {
                    junit "reports/unit_results.xml"
                    publishHTML(target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: "reports/coverage_html",
                        reportFiles: "index.html",
                        reportName: "Coverage Report"
                    ])
                    cobertura coberturaReportFile: "reports/coverage.xml"
                }
            }
        }

        // ── 4. Integration Tests ──────────────────────────────────────────────
        stage("Integration Tests") {
            steps {
                container("python") {
                    sh """
                        # Start app in background
                        APP_COLOR=blue APP_ENV=test python app/app.py &
                        APP_PID=$!
                        sleep 3

                        pytest tests/integration/ -v \
                            --base-url=http://localhost:5000 \
                            --junitxml=reports/integration_results.xml

                        kill $APP_PID || true
                    """
                }
            }
            post {
                always {
                    junit "reports/integration_results.xml"
                }
            }
        }

        // ── 5. Security Scan ──────────────────────────────────────────────────
        stage("Security Scan") {
            steps {
                // Scan filesystem for known vulnerable packages BEFORE building image
                container("trivy") {
                    sh """
                        trivy fs . \
                            --exit-code 1 \
                            --severity HIGH,CRITICAL \
                            --format table \
                            --output reports/trivy_fs_report.txt || \
                        (echo 'HIGH/CRITICAL vulnerabilities found – aborting!' && exit 1)
                    """
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: "reports/trivy_fs_report.txt", fingerprint: true
                }
            }
        }

        // ── 6. Build Docker Image ─────────────────────────────────────────────
        stage("Build Image") {
            steps {
                container("docker") {
                    sh """
                        docker build \
                            --build-arg APP_VERSION=${IMAGE_TAG} \
                            --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
                            --build-arg GIT_COMMIT=${env.GIT_COMMIT} \
                            -f app/Dockerfile \
                            -t ${FULL_IMAGE} \
                            app/
                    """
                }
            }
        }

        // ── 7. Image Security Scan & Push ─────────────────────────────────────
        stage("Scan & Push Image") {
            steps {
                container("trivy") {
                    sh """
                        trivy image ${FULL_IMAGE} \
                            --exit-code 1 \
                            --severity CRITICAL \
                            --format sarif \
                            --output reports/trivy_image_report.sarif || \
                        (echo 'CRITICAL image vulnerabilities – aborting!' && exit 1)
                    """
                }
                container("docker") {
                    sh """
                        echo "${REGISTRY_CREDS_PSW}" | \
                            docker login ${REGISTRY} -u ${REGISTRY_CREDS_USR} --password-stdin
                        docker push ${FULL_IMAGE}
                        docker tag  ${FULL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:latest
                        docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: "reports/trivy_image_report.sarif", fingerprint: true
                }
            }
        }

        // ── 8. Blue-Green Deploy ──────────────────────────────────────────────
        stage("Blue-Green Deploy") {
            steps {
                container("kubectl") {
                    script {
                        // Determine which color is currently LIVE
                        def liveColor = sh(
                            script: "kubectl get svc sample-app-service -n ${NAMESPACE} -o jsonpath='{.spec.selector.color}' 2>/dev/null || echo 'blue'",
                            returnStdout: true
                        ).trim()
                        def targetColor = (liveColor == "blue") ? "green" : "blue"
                        env.LIVE_COLOR   = liveColor
                        env.TARGET_COLOR = targetColor

                        echo "Live: ${liveColor} → Deploying to: ${targetColor}"

                        // Update image in the target deployment
                        sh """
                            kubectl set image deployment/sample-app-${TARGET_COLOR} \
                                sample-app=${FULL_IMAGE} \
                                -n ${NAMESPACE}

                            kubectl rollout status deployment/sample-app-${TARGET_COLOR} \
                                -n ${NAMESPACE} --timeout=5m
                        """
                    }
                }
            }
        }

        // ── 9. Smoke Test ──────────────────────────────────────────────────────
        stage("Smoke Test") {
            steps {
                container("kubectl") {
                    sh "bash scripts/smoke-test.sh ${env.TARGET_COLOR} ${NAMESPACE}"
                }
            }
        }

        // ── 10. Promote or Rollback ───────────────────────────────────────────
        stage("Promote / Rollback") {
            steps {
                container("kubectl") {
                    script {
                        def smokeStatus = sh(
                            script: "bash scripts/smoke-test.sh ${env.TARGET_COLOR} ${NAMESPACE} --quiet",
                            returnStatus: true
                        )

                        if (smokeStatus == 0) {
                            echo "Smoke tests passed. Switching traffic to ${env.TARGET_COLOR}"
                            sh """
                                bash scripts/blue-green-switch.sh \
                                    ${env.TARGET_COLOR} ${NAMESPACE}
                            """
                        } else {
                            echo "Smoke tests FAILED. Initiating rollback to ${env.LIVE_COLOR}"
                            sh "bash scripts/rollback.sh ${env.LIVE_COLOR} ${NAMESPACE}"
                            error("Deployment rolled back – smoke tests failed!")
                        }
                    }
                }
            }
        }

        // ── 11. Canary Deploy (main branch only) ──────────────────────────────
        stage("Canary Deploy") {
            when {
                branch "main"
            }
            steps {
                container("kubectl") {
                    sh """
                        kubectl set image deployment/sample-app-canary \
                            sample-app=${FULL_IMAGE} \
                            -n ${NAMESPACE}

                        kubectl rollout status deployment/sample-app-canary \
                            -n ${NAMESPACE} --timeout=3m

                        echo "Canary deployed at ${CANARY_WEIGHT}% traffic weight."
                    """
                }
            }
        }

        // ── 12. Performance Tests ─────────────────────────────────────────────
        stage("Performance Tests") {
            when {
                environment name: "RUN_PERF_TESTS", value: "true"
                branch "main"
            }
            steps {
                container("python") {
                    sh """
                        pip install --quiet locust
                        SERVICE_IP=$(kubectl get svc sample-app-service -n ${NAMESPACE} \
                            -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

                        locust -f tests/performance/locustfile.py \
                            --host=http://${SERVICE_IP} \
                            --users=50 --spawn-rate=5 \
                            --run-time=2m --headless \
                            --html=reports/perf_report.html \
                            --exit-code-on-error 1
                    """
                }
            }
            post {
                always {
                    publishHTML(target: [
                        reportDir: "reports",
                        reportFiles: "perf_report.html",
                        reportName: "Performance Report"
                    ])
                }
            }
        }
    }

    // ── Post-Pipeline Actions ─────────────────────────────────────────────────
    post {
        success {
            script {
                def msg = """
                ✅ *Build SUCCESS* – `${env.JOB_NAME}` #${env.BUILD_NUMBER}
                Branch: `${env.GIT_BRANCH}` | Author: `${env.GIT_AUTHOR}`
                Commit: `${env.COMMIT_MSG}`
                Active color: *${env.TARGET_COLOR ?: 'N/A'}*
                Build URL: ${env.BUILD_URL}
                """.stripIndent()
                sh "curl -s -X POST '${SLACK_WEBHOOK}' -H 'Content-type: application/json' --data '{\"text\":\"${msg}\"}'"
            }
        }
        failure {
            script {
                def msg = """
                ❌ *Build FAILED* – `${env.JOB_NAME}` #${env.BUILD_NUMBER}
                Branch: `${env.GIT_BRANCH}` | Author: `${env.GIT_AUTHOR}`
                Build URL: ${env.BUILD_URL}
                """.stripIndent()
                sh "curl -s -X POST '${SLACK_WEBHOOK}' -H 'Content-type: application/json' --data '{\"text\":\"${msg}\"}'"
            }
        }
        always {
            cleanWs()
        }
    }
}
