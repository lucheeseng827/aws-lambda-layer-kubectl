# Serverless Functions on Kubernetes

This sample demonstrates how to deploy and manage serverless functions on Kubernetes using AWS Lambda as the control plane, without any cloud vendor lock-in.

## Architecture

```
┌──────────────┐        ┌──────────────────┐        ┌────────────────────┐
│              │        │                  │        │                    │
│  AWS Lambda  │───────▶│  Amazon EKS      │───────▶│  Serverless Funcs  │
│  Controller  │        │  Kubernetes API  │        │  (Deployments)     │
│              │        │                  │        │                    │
└──────────────┘        └──────────────────┘        └────────────────────┘
```

### Key Features

- **No Vendor Lock-in**: Uses pure Kubernetes primitives (Deployments, Services, HPA)
- **Auto-scaling**: Built-in horizontal pod autoscaling based on CPU/Memory
- **Lambda as Control Plane**: Use Lambda to deploy and manage functions on K8s
- **Flexible**: Deploy any containerized application as a serverless function
- **Cost-effective**: Functions run on your K8s cluster, not on Lambda

## Prerequisites

1. Amazon EKS cluster running
2. kubectl access to the cluster
3. Lambda execution role with EKS permissions
4. Lambda Layer for kubectl deployed

## Quick Start

### 1. Deploy the Infrastructure

First, install the CRD and RBAC resources:

```bash
kubectl apply -f k8s-manifests/namespace.yaml
kubectl apply -f k8s-manifests/rbac.yaml
kubectl apply -f k8s-manifests/function-crd.yaml
```

### 2. Deploy the Lambda Controller

```bash
# Set your parameters
export CLUSTER_NAME=your-eks-cluster
export LAYER_ARN=arn:aws:lambda:region:account:layer:eks-kubectl-layer:version
export LAMBDA_ROLE_ARN=arn:aws:iam::account:role/LambdaEKSRole

# Deploy using SAM
sam deploy \
  --template-file sam.yaml \
  --stack-name serverless-k8s-controller \
  --parameter-overrides \
    ClusterName=$CLUSTER_NAME \
    FunctionName=serverless-k8s-controller \
    LambdaLayerKubectlArn=$LAYER_ARN \
    LambdaRoleArn=$LAMBDA_ROLE_ARN \
  --capabilities CAPABILITY_IAM
```

### 3. Deploy Your First Serverless Function

Create an `event.json` file:

```json
{
  "action": "deploy",
  "cluster_name": "your-eks-cluster",
  "function": {
    "name": "hello-world",
    "image": "nginx:alpine",
    "port": 80,
    "replicas": {
      "min": 1,
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

Invoke the Lambda function:

```bash
aws lambda invoke \
  --function-name serverless-k8s-controller \
  --payload file://event.json \
  --region us-east-1 \
  response.json

cat response.json
```

## Available Actions

### Deploy a Function

```json
{
  "action": "deploy",
  "function": {
    "name": "my-function",
    "image": "your-image:tag",
    "port": 8080,
    "replicas": {
      "min": 1,
      "max": 10
    }
  }
}
```

### Delete a Function

```json
{
  "action": "delete",
  "function": {
    "name": "my-function"
  }
}
```

### List All Functions

```json
{
  "action": "list"
}
```

### Get Function Status

```json
{
  "action": "status",
  "function": {
    "name": "my-function"
  }
}
```

### Scale a Function

```json
{
  "action": "scale",
  "function": {
    "name": "my-function",
    "replicas": 5
  }
}
```

### Update Function Image

```json
{
  "action": "update",
  "function": {
    "name": "my-function",
    "image": "your-image:new-tag"
  }
}
```

## Example Functions

### Node.js HTTP Function

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
```

### Python Flask Function

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["python", "app.py"]
```

### Go HTTP Function

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o main .

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
```

## CI/CD Integration

### GitHub Actions

The repository includes a GitHub Actions workflow that:
- Builds the Lambda layer
- Tests the deployment
- Deploys to AWS automatically

See `.github/workflows/build-and-deploy.yml`

### GitLab CI

The repository includes a GitLab CI pipeline that:
- Builds the Lambda layer
- Validates templates
- Deploys to AWS
- Publishes to SAR

See `.gitlab-ci.yml`

## Required IAM Permissions

Your Lambda execution role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
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

## Accessing Your Functions

Functions are deployed with ClusterIP services by default. To access them:

### Option 1: Port Forward

```bash
kubectl port-forward -n serverless-functions svc/sfn-my-function 8080:80
curl http://localhost:8080
```

### Option 2: Ingress

Create an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-function-ingress
  namespace: serverless-functions
spec:
  rules:
  - host: my-function.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sfn-my-function
            port:
              number: 80
```

### Option 3: LoadBalancer Service

Modify the service type to LoadBalancer using kubectl:

```bash
kubectl patch svc sfn-my-function -n serverless-functions \
  -p '{"spec":{"type":"LoadBalancer"}}'
```

## Monitoring

View function logs:

```bash
kubectl logs -n serverless-functions -l app=my-function --tail=100 -f
```

Check function metrics:

```bash
kubectl top pods -n serverless-functions -l app=my-function
```

View auto-scaling status:

```bash
kubectl get hpa -n serverless-functions
```

## Troubleshooting

### Function Not Deploying

Check Lambda logs:
```bash
aws logs tail /aws/lambda/serverless-k8s-controller --follow
```

Check K8s events:
```bash
kubectl get events -n serverless-functions --sort-by='.lastTimestamp'
```

### Function Not Scaling

Check HPA status:
```bash
kubectl describe hpa sfn-my-function -n serverless-functions
```

Ensure metrics-server is installed:
```bash
kubectl get deployment metrics-server -n kube-system
```

### Permission Issues

Verify Lambda role has EKS permissions and is added to aws-auth ConfigMap:

```bash
kubectl get configmap aws-auth -n kube-system -o yaml
```

## Advanced Usage

### Custom Environment Variables

Modify the `deploy_function` in `func.d/libs.sh` to support environment variables from the payload.

### Secrets Management

Use Kubernetes Secrets:

```bash
kubectl create secret generic my-secret \
  -n serverless-functions \
  --from-literal=api-key=your-secret-key
```

Reference in deployment by modifying the libs.sh template.

### Multi-Region Deployment

Deploy the same Lambda controller in multiple regions, each managing a different EKS cluster.

## Cost Optimization

- Functions run on your existing K8s nodes (no additional Lambda runtime costs)
- Auto-scaling ensures you only run what you need
- Use spot instances for K8s nodes to reduce costs further

## Comparison with Other Solutions

| Feature | This Solution | AWS Lambda | Knative | OpenFaaS |
|---------|--------------|------------|---------|----------|
| Vendor Lock-in | None | High | Low | None |
| K8s Native | Yes | No | Yes | Yes |
| Cost | Node cost only | Per invocation | Node cost only | Node cost only |
| Cold Start | Minimal | Yes | Configurable | Minimal |
| Complexity | Low | Low | High | Medium |

## License

This sample code is made available under the MIT-0 license. See the LICENSE file.
