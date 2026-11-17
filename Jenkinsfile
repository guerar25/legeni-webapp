// Projet CI/CD : du commit à la production
//   CI (toutes les branches et PR) : qualité en parallèle -> build -> scan Trivy
//   CD (main uniquement)           : push registre -> staging (Ansible) -> validation -> prod (Ansible) -> tag Git
// Aucun secret ici : uniquement des credentials Jenkins
//   registry-credentials (Username/Password Docker Hub), kubeconfig (Secret file),
//   ansible-vault-pass (Secret file), github (Username/Password), discord-webhook (Secret text, optionnel)
pipeline {
    agent any

    environment {
        IMAGE   = 'guerar/legeni-webapp'
        VERSION = readFile('VERSION').trim()          // version sémantique gérée dans le dépôt
        TAG     = "${VERSION}-${env.BUILD_NUMBER}"    // ex. 1.1.0-37 : jamais "latest"
    }

    options {
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()                     // jamais deux déploiements en même temps
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Qualité') {
            parallel {
                stage('Tests + couverture') {
                    agent {
                        docker { image 'python:3.12-slim'; args '-e HOME=/tmp'; reuseNode true }
                    }
                    steps {
                        sh '''
                            python -m venv /tmp/venv
                            /tmp/venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt
                            mkdir -p reports
                            /tmp/venv/bin/pytest --junitxml=reports/junit.xml \
                                --cov=app --cov-report=xml:reports/coverage.xml --cov-fail-under=80
                        '''
                    }
                    post {
                        always {
                            junit 'reports/junit.xml'
                            recordCoverage(tools: [[parser: 'COBERTURA', pattern: 'reports/coverage.xml']])
                        }
                    }
                }
                stage('Lint Python') {
                    agent {
                        docker { image 'python:3.12-slim'; args '-e HOME=/tmp'; reuseNode true }
                    }
                    steps {
                        sh '''
                            python -m venv /tmp/venv-lint
                            /tmp/venv-lint/bin/pip install -q flake8==7.1.1
                            mkdir -p reports
                            /tmp/venv-lint/bin/flake8 --output-file=reports/flake8.txt --tee .
                        '''
                    }
                    post {
                        always { recordIssues(tools: [flake8(pattern: 'reports/flake8.txt')]) }
                    }
                }
                stage('Lint Dockerfile') {
                    steps {
                        sh 'docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile'
                    }
                }
                stage('Syntaxe Ansible') {
                    steps {
                        withCredentials([file(credentialsId: 'ansible-vault-pass', variable: 'VAULT_PASS')]) {
                            dir('ansible') {
                                sh 'ansible-playbook --syntax-check --vault-password-file "$VAULT_PASS" provision.yml deploy.yml'
                            }
                        }
                    }
                }
                stage('Secrets') {
                    agent {
                        docker { image 'zricethezav/gitleaks:v8.21.2'; args '--entrypoint='; reuseNode true }
                    }
                    steps {
                        sh 'gitleaks detect --source . --no-banner --redact'
                    }
                }
            }
        }

        stage('Build image') {
            steps {
                sh 'docker build --build-arg APP_VERSION=$TAG -t $IMAGE:$TAG .'
            }
        }

        stage('Scan Trivy') {
            steps {
                // échoue si une vulnérabilité CRITICAL corrigeable est trouvée
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
                        aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 $IMAGE:$TAG
                '''
            }
        }

        stage('Push registre') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry-credentials',
                                                  usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
                    sh '''
                        echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin
                        docker push $IMAGE:$TAG
                        docker logout
                    '''
                }
            }
        }

        stage('Déploiement staging') {
            when { branch 'main' }
            steps {
                deployWithAnsible('staging')
            }
        }

        stage('Validation production') {
            when { branch 'main' }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Déployer ${TAG} en production ? (staging : http://192.168.49.2:30081)", ok: 'Déployer'
                }
            }
        }

        stage('Déploiement production') {
            when { branch 'main' }
            steps {
                deployWithAnsible('prod')
            }
        }

        stage('Tag Git') {
            when { branch 'main' }
            steps {
                // un tag v<VERSION> par mise en production (créé une seule fois par version)
                withCredentials([gitUsernamePassword(credentialsId: 'github')]) {
                    sh '''
                        if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null; then
                            echo "Tag v$VERSION déjà présent"
                        else
                            git -c user.name=jenkins -c user.email=jenkins@legeni.local \
                                tag -a "v$VERSION" -m "Mise en production $TAG"
                            git push origin "v$VERSION"
                        fi
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} : ${TAG}"
        }
        failure {
            script {
                // Notification d'échec : la notification ne doit jamais faire échouer le pipeline
                try {
                    withCredentials([string(credentialsId: 'discord-webhook', variable: 'WEBHOOK')]) {
                        sh '''
                            curl -fsS -H "Content-Type: application/json" -X POST "$WEBHOOK" \
                                -d "{\\"content\\": \\"❌ Échec ${JOB_NAME} #${BUILD_NUMBER} (${TAG}) : ${BUILD_URL}console\\"}"
                        '''
                    }
                } catch (err) {
                    echo "Notification non envoyée : ${err.message}"
                }
            }
        }
        cleanup {
            sh 'docker image rm $IMAGE:$TAG >/dev/null 2>&1 || true'   // le registre garde l'image : on libère le disque
            cleanWs()
        }
    }
}

// Déploiement Kubernetes par Ansible (deploy.yml : rolling update, smoke test, rollback automatique)
def deployWithAnsible(String targetEnv) {
    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG'),
                     file(credentialsId: 'ansible-vault-pass', variable: 'VAULT_PASS')]) {
        dir('ansible') {
            sh """
                ansible-playbook deploy.yml --vault-password-file "\$VAULT_PASS" \
                    -e target_env=${targetEnv} -e app_image=\$IMAGE -e app_version=\$TAG
            """
        }
    }
}
