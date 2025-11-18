# Serverless Functions on Kubernetes with Knative

This sample demonstrates how to deploy and manage serverless functions on Kubernetes using **Knative Serving** with AWS Lambda as the control plane.

## Why Knative?

Knative is a Kubernetes-based platform for deploying and managing modern serverless workloads. It provides:

- **Scale to Zero**: Automatically scale down to zero replicas when idle
- **Request-based Autoscaling**: Scale based on concurrent requests, not just CPU/memory
- **Revision Management**: Built-in blue/green deployments and traffic splitting
- **Auto-generated URLs**: Automatic ingress and DNS configuration
- **Gradual Rollouts**: Canary deployments with traffic percentage control

## Architecture

```
┌──────────────┐        ┌──────────────────┐        ┌─────────────────────┐
│              │        │                  │        │                     │
│  AWS Lambda  │───────▶│  Amazon EKS      │───────▶│  Knative Services   │
│  Controller  │        │  + Knative       │        │  (Auto-scaling)     │
│              │        │                  │        │                     │
└──────────────┘        └──────────────────┘        └─────────────────────┘
                                                              │
                                                              ▼
                                                     ┌─────────────────┐
                                                     │  Revisions      │
                                                     │  (Versioning)   │
                                                     └─────────────────┘
```

## Key Features

- **Scale to Zero**: Save costs by scaling to 0 when no traffic
- **Traffic Splitting**: Gradual rollouts and A/B testing
- **Revision Tracking**: Every deployment creates a new revision
- **Auto URLs**: Each service gets an automatic HTTP endpoint
- **Request-based Autoscaling**: More intelligent than CPU/memory metrics
- **No Vendor Lock-in**: Pure Knative, works on any K8s

## Prerequisites

1. Amazon EKS cluster running
2. kubectl access to the cluster
3. Lambda execution role with EKS permissions
4. Lambda Layer for kubectl deployed
5. Knative Serving installed on the cluster

## Quick Start

### 1. Install Knative on EKS

```bash
cd samples/serverless-functions-knative

# Install Knative Serving and networking
make install-knative

# Verify installation
make verify-knative
```

This will install:
- Knative Serving CRDs and core components
- Kourier (lightweight networking layer)
- Magic DNS (for automatic domain assignment)

### 2. Deploy the Lambda Controller

```bash
# Set your parameters
export CLUSTER_NAME=your-eks-cluster
export LAYER_ARN=arn:aws:lambda:region:account:layer:eks-kubectl-layer:version
export LAMBDA_ROLE_ARN=arn:aws:iam::account:role/LambdaEKSRole
export S3BUCKET=your-s3-bucket

# Deploy using SAM
make deploy-controller
```

### 3. Deploy Your First Knative Service

```bash
# Deploy a sample Knative service
make invoke-deploy
```

This deploys the official Knative "Hello World" sample!

### 4. Test Your Service

Get the service URL:

```bash
kubectl get ksvc -n serverless-knative
```

Test it:

```bash
# Get the URL from the output
SERVICE_URL=$(kubectl get ksvc hello-knative -n serverless-knative -o jsonpath='{.status.url}')
curl $SERVICE_URL
```

## Available Actions

### Deploy a Knative Service

```json
{
  "action": "deploy",
  "cluster_name": "my-eks-cluster",
  "function": {
    "name": "my-service",
    "image": "gcr.io/knative-samples/helloworld-go",
    "port": 8080,
    "replicas": {
      "min": 0,
      "max": 10
    },
    "concurrency": 100,
    "env": [
      {"name": "TARGET", "value": "World"}
    ]
  }
}
```

**Key differences from native K8s:**
- `min: 0` enables scale-to-zero
- `concurrency` sets max concurrent requests per pod
- Automatic URL generation and ingress

### Delete a Service

```json
{
  "action": "delete",
  "function": {
    "name": "my-service"
  }
}
```

### List All Services

```json
{
  "action": "list"
}
```

### Get Service Status

```json
{
  "action": "status",
  "function": {
    "name": "my-service"
  }
}
```

Returns detailed information including:
- Service configuration
- All revisions
- Traffic distribution
- Active pods
- Service URL

### Update Service (Creates New Revision)

```json
{
  "action": "update",
  "function": {
    "name": "my-service",
    "image": "gcr.io/knative-samples/helloworld-go:v2"
  }
}
```

This automatically:
- Creates a new revision
- Gradually shifts traffic
- Keeps old revision for rollback

### Traffic Splitting (Blue/Green, Canary)

```json
{
  "action": "traffic-split",
  "function": {
    "name": "my-service"
  },
  "traffic": [
    {
      "revision": "my-service-00001",
      "percent": 80
    },
    {
      "revision": "my-service-00002",
      "percent": 20
    }
  ]
}
```

Use cases:
- **Canary deployment**: 90% old, 10% new
- **Blue/Green**: 0% old, 100% new (instant switch)
- **A/B testing**: 50% variant A, 50% variant B

### List Revisions

```json
{
  "action": "revisions",
  "function": {
    "name": "my-service"
  }
}
```

Shows all historical revisions for the service.

### Rollback to Previous Revision

```json
{
  "action": "rollback",
  "function": {
    "name": "my-service"
  },
  "revision": "my-service-00001"
}
```

Instant rollback to any previous revision.

## Knative vs Native Kubernetes

| Feature | Knative | Native K8s (Deployment) |
|---------|---------|-------------------------|
| **Scale to Zero** | ✅ Yes | ❌ No |
| **Request-based Autoscaling** | ✅ Yes | ❌ No (CPU/memory only) |
| **Revision Management** | ✅ Built-in | ❌ Manual |
| **Traffic Splitting** | ✅ Built-in | ❌ Manual with Ingress |
| **Auto URLs** | ✅ Yes | ❌ Manual Ingress |
| **Blue/Green** | ✅ Easy | ❌ Manual |
| **Canary Deployments** | ✅ Easy | ❌ Complex |
| **Learning Curve** | Medium | Easy |
| **Resource Overhead** | Higher | Lower |
| **Maturity** | Production-ready | Battle-tested |
| **Portability** | Any K8s + Knative | Any K8s |

**When to use Knative:**
- You need scale-to-zero for cost savings
- You want built-in canary deployments
- Request-based autoscaling is important
- You prefer declarative traffic management

**When to use Native K8s:**
- You want simplicity and less overhead
- Your services always need to be running
- You already have custom deployment workflows
- You want full control over every detail

## Advanced Features

### Scale to Zero Configuration

Knative automatically scales to zero when there's no traffic. Configure the grace period:

```bash
# Edit autoscaler config
kubectl edit configmap config-autoscaler -n knative-serving

# Set scale-to-zero-grace-period (default: 30s)
# Set stable-window (default: 60s)
```

### Custom Domain

Configure your own domain instead of Magic DNS:

```bash
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"example.com":""}}'
```

### Metrics and Monitoring

Knative exposes Prometheus metrics:

```bash
# Get autoscaler metrics
kubectl get podautoscaler -n serverless-knative

# View metrics
kubectl port-forward -n knative-serving \
  svc/activator-service 9090:9090
```

### TLS/HTTPS

Enable automatic TLS with cert-manager:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Configure Knative for TLS
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"auto-tls":"Enabled"}}'
```

## Cost Optimization

### Scale to Zero Savings

With scale-to-zero, you only pay for:
- Compute when requests are active
- Cold start latency (typically < 2 seconds)

Example savings:
- Service receiving traffic 10% of the time: **~90% cost reduction**
- Service receiving sporadic requests: **~95% cost reduction**

### Request-based Autoscaling

More efficient than CPU-based:
- Scales based on actual load (concurrent requests)
- Faster scale-up response
- Better resource utilization

## Production Considerations

### Networking

For production, consider alternatives to Kourier:

**Istio** (recommended for production):
```bash
# Install Istio
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.12.0/net-istio.yaml
```

Benefits:
- Advanced traffic management
- mTLS between services
- Observability (tracing, metrics)

**Contour**:
```bash
# Install Contour
kubectl apply -f https://github.com/knative/net-contour/releases/download/knative-v1.12.0/net-contour.yaml
```

### High Availability

Enable HA mode for Knative components:

```bash
kubectl edit deployment controller -n knative-serving
# Set replicas: 3

kubectl edit deployment activator -n knative-serving
# Set replicas: 3
```

### Resource Limits

Set reasonable limits to prevent runaway costs:

```yaml
metadata:
  annotations:
    autoscaling.knative.dev/maxScale: "100"  # Max 100 pods
    autoscaling.knative.dev/target: "100"    # 100 concurrent requests/pod
```

## Troubleshooting

### Service Not Ready

Check the service status:
```bash
kubectl describe ksvc <service-name> -n serverless-knative
```

Common issues:
- Image pull errors
- Health check failures
- Resource limits too low

### Cold Start Latency

Reduce cold starts:
```bash
# Set minimum replicas to 1
{
  "function": {
    "replicas": {
      "min": 1,  # No scale to zero
      "max": 10
    }
  }
}
```

### Traffic Routing Issues

Check routes and ingress:
```bash
kubectl get routes -n serverless-knative
kubectl get ingress -n serverless-knative
kubectl get svc kourier -n kourier-system
```

### Lambda Timeout

Knative operations might take longer than native K8s:
- Increase Lambda timeout to 120s (already configured)
- Monitor CloudWatch logs for timeout errors

## Example: Gradual Rollout

Deploy version 1:
```bash
make invoke-deploy  # Deploys hello-knative with v1
```

Update to version 2:
```bash
# Edit examples/update-function.json to use v2 image
make invoke-update
```

Knative automatically creates a new revision and routes all traffic to it.

For gradual rollout:
```bash
# Split traffic: 80% v1, 20% v2
# Edit examples/traffic-split.json
make invoke-traffic-split

# Monitor metrics, then shift more traffic
# Edit to 50/50, then 20/80, then 0/100
```

## Integration with CI/CD

See the main CI/CD pipelines in:
- `.github/workflows/build-and-deploy.yml` (GitHub Actions)
- `.gitlab-ci.yml` (GitLab CI)

Both support Knative deployments alongside native K8s deployments.

## Migration from Native K8s

To migrate from native K8s deployments:

1. Keep both controllers deployed
2. Gradually move services to Knative
3. Test scale-to-zero behavior
4. Monitor cold start latency
5. Adjust autoscaling parameters

## Resources

- [Knative Documentation](https://knative.dev/docs/)
- [Knative Samples](https://knative.dev/docs/samples/)
- [Knative Best Practices](https://knative.dev/docs/serving/best-practices/)
- [AWS EKS Best Practices for Knative](https://aws.github.io/aws-eks-best-practices/)

## License

This sample code is made available under the MIT-0 license. See the LICENSE file.
