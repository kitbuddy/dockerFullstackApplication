pipeline {
  agent any
  environment {
    AWS_REGION = 'us-east-1'
    AWS_ACCOUNT_ID = credentials('aws-account-id') // Jenkins credential storing account id (or set as plain string)
    ECR_REPO = 'my-java-angular-app'
    IMAGE_TAG = "${env.BUILD_NUMBER ?: 'latest'}"
    ECR_URI = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Build Frontend') {
      steps {
        dir('frontend') {
          sh 'npm ci'
          sh 'npm run build'
        }
      }
    }
    stage('Build Backend') {
      steps {
        dir('backend') {
          sh 'mvn clean package -DskipTests'
        }
      }
    }
    stage('Docker Build & Push') {
      steps {
        script {
          sh 'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URI}'
          sh "docker build -t ${ECR_REPO}:${IMAGE_TAG} ."
          sh "docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}"
          sh "docker push ${ECR_URI}:${IMAGE_TAG}"
        }
      }
    }
    stage('Deploy to ECS') {
      steps {
        script {
          // Register a new task definition revision with the new image
          sh '''
          aws ecs describe-task-definition \
            --task-definition my-java-angular-task \
            --region ${AWS_REGION} \
            > taskdef.json

          # Update the container image
          cat taskdef.json | jq '.taskDefinition | del(.taskDefinitionArn, .revision, .status, .compatibilities, .registeredAt, .registeredBy, .requiresAttributes)' > new-taskdef.json
          jq --arg IMAGE "${ECR_URI}:${IMAGE_TAG}" '.containerDefinitions[0].image=$IMAGE' new-taskdef.json > new-taskdef-updated.json

          aws ecs register-task-definition \
            --cli-input-json file://new-taskdef-updated.json \
            --region ${AWS_REGION} > registered.json

          NEW_TASK_DEF_ARN=$(jq -r '.taskDefinition.taskDefinitionArn' registered.json)

          aws ecs update-service \
            --cluster my-java-angular-cluster \
            --service my-java-angular-service \
            --task-definition ${NEW_TASK_DEF_ARN} \
            --region ${AWS_REGION}
          '''
        }
      }
    }
  }
}
