# Serverless Functions on Kubernetes - Deployment Guide

This comprehensive guide walks you through deploying a complete serverless platform on Kubernetes using AWS Lambda as the control plane.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step-by-Step Deployment](#step-by-step-deployment)
4. [CI/CD Setup](#cicd-setup)
5. [Production Considerations](#production-considerations)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- AWS CLI configured with appropriate credentials
- kubectl configured to access your EKS cluster
- SAM CLI installed (`pip install aws-sam-cli`)
- Docker installed (for building functions)
- jq (for JSON processing)

### AWS Resources

- Amazon EKS cluster (running and accessible)
- S3 bucket for SAM deployment artifacts
- IAM role for Lambda with EKS permissions

### Verify Prerequisites

```bash
# Check AWS CLI
aws --version

# Check kubectl
kubectl version --client

# Check SAM CLI
sam --version

# Check Docker
docker --version

# Verify EKS cluster access
kubectl get nodes
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                            │
│  ┌──────────────────┐         ┌─────────────────────────┐  │
│  │  Lambda Function │────────▶│   Amazon EKS Cluster    │  │
│  │   (Controller)   │         │                         │  │
│  └──────────────────┘         │  ┌──────────────────┐   │  │
│          │                    │  │ Serverless Funcs │   │  │
│          │                    │  │  (Deployments)   │   │  │
│          │                    │  └──────────────────┘   │  │
│  ┌──────────────────┐         │  ┌──────────────────┐   │  │
│  │  Lambda Layer    │         │  │   Services       │   │  │
│  │  (kubectl, aws)  │         │  └──────────────────┘   │  │
│  └──────────────────┘         │  ┌──────────────────┐   │  │
│                               │  │      HPA         │   │  │
│                               │  └──────────────────┘   │  │
│                               └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Step-by-Step Deployment

### Step 1: Prepare IAM Role

Create an IAM role for Lambda with the following trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Attach the following policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name LambdaEKSAdminRole \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name LambdaEKSAdminRole \
  --policy-name LambdaEKSPolicy \
  --policy-document file://eks-policy.json

aws iam attach-role-policy \
  --role-name LambdaEKSAdminRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

### Step 2: Update EKS aws-auth ConfigMap

Add the Lambda role to your EKS cluster's aws-auth ConfigMap:

```bash
kubectl edit configmap aws-auth -n kube-system
```

Add this entry under `mapRoles`:

```yaml
- rolearn: arn:aws:iam::YOUR_ACCOUNT_ID:role/LambdaEKSAdminRole
  username: lambda-admin
  groups:
    - system:masters
```

### Step 3: Build and Deploy Lambda Layer

From the repository root:

```bash
# Build the layer
make build

# Deploy the layer
export S3BUCKET=your-s3-bucket
export LAMBDA_REGION=us-east-1

make sam-layer-package
make sam-layer-deploy
```

Get the Layer ARN:

```bash
export LAYER_ARN=$(aws cloudformation describe-stacks \
  --stack-name eks-kubectl-layer-stack \
  --query 'Stacks[0].Outputs[0].OutputValue' \
  --output text \
  --region $LAMBDA_REGION)

echo "Layer ARN: $LAYER_ARN"
```

### Step 4: Install Kubernetes Resources

```bash
cd samples/serverless-functions

# Install CRD, namespace, and RBAC
make install-crd

# Verify installation
kubectl get crd serverlessfunctions.serverless.eks.io
kubectl get namespace serverless-functions
kubectl get serviceaccount -n serverless-functions
```

### Step 5: Deploy Lambda Controller

```bash
# Set environment variables
export CLUSTER_NAME=your-eks-cluster-name
export S3BUCKET=your-s3-bucket
export LAMBDA_REGION=us-east-1
export LAMBDA_ROLE_ARN=arn:aws:iam::YOUR_ACCOUNT:role/LambdaEKSAdminRole

# Deploy the controller
make deploy-controller
```

Verify deployment:

```bash
aws lambda get-function \
  --function-name serverless-k8s-controller \
  --region $LAMBDA_REGION
```

### Step 6: Deploy Your First Function

Update the cluster name in `examples/deploy-function.json`:

```json
{
  "action": "deploy",
  "cluster_name": "your-eks-cluster-name",
  "function": {
    "name": "hello-world",
    "image": "nginx:alpine",
    "port": 80,
    "replicas": {
      "min": 2,
      "max": 10
    }
  }
}
```

Deploy:

```bash
make invoke-deploy
```

Verify the function is running:

```bash
kubectl get deployments -n serverless-functions
kubectl get pods -n serverless-functions
kubectl get svc -n serverless-functions
kubectl get hpa -n serverless-functions
```

### Step 7: Test Your Function

Port-forward to test:

```bash
kubectl port-forward -n serverless-functions svc/sfn-hello-world 8080:80
```

In another terminal:

```bash
curl http://localhost:8080
```

### Step 8: Deploy a Custom Function

Build the sample function:

```bash
cd examples/sample-function
docker build -t my-function:latest .

# Tag and push to ECR
aws ecr get-login-password --region $LAMBDA_REGION | \
  docker login --username AWS --password-stdin \
  YOUR_ACCOUNT.dkr.ecr.$LAMBDA_REGION.amazonaws.com

docker tag my-function:latest \
  YOUR_ACCOUNT.dkr.ecr.$LAMBDA_REGION.amazonaws.com/my-function:latest

docker push YOUR_ACCOUNT.dkr.ecr.$LAMBDA_REGION.amazonaws.com/my-function:latest
```

Create deployment payload:

```json
{
  "action": "deploy",
  "cluster_name": "your-eks-cluster",
  "function": {
    "name": "my-custom-function",
    "image": "YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/my-function:latest",
    "port": 8080,
    "replicas": {
      "min": 2,
      "max": 10
    },
    "resources": {
      "requests": {
        "cpu": "100m",
        "memory": "128Mi"
      },
      "limits": {
        "cpu": "500m",
        "memory": "512Mi"
      }
    }
  }
}
```

Deploy:

```bash
aws lambda invoke \
  --function-name serverless-k8s-controller \
  --payload file://my-function-deploy.json \
  response.json

cat response.json | jq .
```

## CI/CD Setup

### GitHub Actions

The repository includes GitHub Actions workflows. To enable:

1. Add secrets to your GitHub repository:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `S3_BUCKET`
   - `EKS_CLUSTER_NAME`
   - `LAMBDA_ROLE_ARN`

2. Push to main branch or create a PR

3. Workflow will:
   - Build the layer
   - Run tests
   - Deploy to AWS (on main branch)

### GitLab CI

The repository includes GitLab CI configuration. To enable:

1. Add CI/CD variables in GitLab:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `S3_BUCKET`
   - `EKS_CLUSTER_NAME`
   - `LAMBDA_ROLE_ARN`

2. Push to main branch

3. Pipeline will:
   - Build the layer
   - Validate templates
   - Deploy to AWS

## Production Considerations

### Security

1. **Least Privilege**: Don't use `system:masters` for Lambda role in production
   ```yaml
   # Create a custom ClusterRole instead
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: serverless-function-operator
   rules:
     - apiGroups: ["apps", "", "autoscaling"]
       resources: ["deployments", "services", "hpa"]
       verbs: ["get", "list", "create", "update", "delete"]
   ```

2. **Network Policies**: Restrict function network access
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: serverless-function-policy
     namespace: serverless-functions
   spec:
     podSelector:
       matchLabels:
         type: serverless-function
     policyTypes:
       - Ingress
       - Egress
   ```

3. **Image Security**: Use private registries and image scanning

### Monitoring

1. **CloudWatch Logs**: Monitor Lambda execution
   ```bash
   aws logs tail /aws/lambda/serverless-k8s-controller --follow
   ```

2. **Kubernetes Metrics**: Install Prometheus and Grafana
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install prometheus prometheus-community/kube-prometheus-stack
   ```

3. **Function Metrics**: View pod metrics
   ```bash
   kubectl top pods -n serverless-functions
   ```

### Scaling

1. **Cluster Autoscaler**: Enable for automatic node scaling
2. **Metrics Server**: Required for HPA
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

### High Availability

1. **Multi-AZ**: Deploy EKS nodes across multiple AZs
2. **Pod Disruption Budgets**: Ensure availability during updates
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: sfn-pdb
     namespace: serverless-functions
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         type: serverless-function
   ```

## Troubleshooting

### Function Not Deploying

**Check Lambda logs:**
```bash
aws logs tail /aws/lambda/serverless-k8s-controller --follow
```

**Check kubectl access:**
```bash
# Test locally with same credentials
aws eks update-kubeconfig --name your-cluster
kubectl get nodes
```

**Check IAM role:**
```bash
kubectl get configmap aws-auth -n kube-system -o yaml
```

### Function Not Scaling

**Check HPA:**
```bash
kubectl describe hpa -n serverless-functions
```

**Install metrics-server if missing:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Image Pull Errors

**Check ECR permissions:**
```bash
# Ensure nodes can pull from ECR
aws ecr get-login-password --region $REGION | \
  kubectl create secret docker-registry ecr-secret \
  --docker-server=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(cat)" \
  -n serverless-functions
```

### Network Connectivity Issues

**Check service:**
```bash
kubectl get svc -n serverless-functions
kubectl describe svc sfn-your-function -n serverless-functions
```

**Check endpoints:**
```bash
kubectl get endpoints -n serverless-functions
```

## Next Steps

1. **Custom Domains**: Set up Ingress with custom domains
2. **Service Mesh**: Integrate with Istio or Linkerd
3. **Observability**: Add distributed tracing with Jaeger
4. **GitOps**: Integrate with ArgoCD or Flux

## Support

For issues and questions:
- GitHub Issues: [aws-samples/aws-lambda-layer-kubectl](https://github.com/aws-samples/aws-lambda-layer-kubectl/issues)
- AWS Support: Contact AWS Support for EKS-related issues
