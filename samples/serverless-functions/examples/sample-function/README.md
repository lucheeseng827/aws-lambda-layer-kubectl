# Sample Serverless Function

A simple Node.js/Express application demonstrating how to build a serverless function for Kubernetes.

## Requirements

- Node.js 18+
- Docker

## Running Locally

```bash
npm install
npm start
```

Test the endpoints:

```bash
# Main endpoint
curl http://localhost:8080/

# Health check
curl http://localhost:8080/health

# Ready check
curl http://localhost:8080/ready

# Echo endpoint
curl -X POST http://localhost:8080/echo \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello World"}'
```

## Building Docker Image

```bash
docker build -t my-serverless-function:latest .
```

## Running in Docker

```bash
docker run -p 8080:8080 my-serverless-function:latest
```

## Deploying to Kubernetes via Lambda

1. Push your image to a container registry (ECR, Docker Hub, etc.):

```bash
# Tag for ECR
docker tag my-serverless-function:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-function:latest

# Push to ECR
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-function:latest
```

2. Create the deployment payload:

```json
{
  "action": "deploy",
  "cluster_name": "my-eks-cluster",
  "function": {
    "name": "my-function",
    "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-function:latest",
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

3. Deploy via Lambda:

```bash
aws lambda invoke \
  --function-name serverless-k8s-controller \
  --payload file://deploy.json \
  response.json
```

## Required Endpoints

Your function **must** implement these endpoints:

- `/health` - Liveness probe (returns 200 if healthy)
- `/ready` - Readiness probe (returns 200 if ready to serve traffic)

## Best Practices

1. **Graceful Shutdown**: Handle SIGTERM signals properly
2. **Health Checks**: Implement meaningful health checks
3. **Logging**: Use structured logging (JSON format recommended)
4. **Metrics**: Expose Prometheus metrics at `/metrics` (optional)
5. **Security**: Run as non-root user in production
6. **Resource Limits**: Set appropriate CPU/memory limits

## Example with Other Languages

### Python (Flask)

```python
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({
        'message': 'Hello from Python!',
        'hostname': os.environ.get('HOSTNAME', 'unknown')
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'}), 200

@app.route('/ready')
def ready():
    return jsonify({'status': 'ready'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### Go

```go
package main

import (
    "encoding/json"
    "log"
    "net/http"
    "os"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        json.NewEncoder(w).Encode(map[string]string{
            "message":  "Hello from Go!",
            "hostname": os.Getenv("HOSTNAME"),
        })
    })

    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
    })

    http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
    })

    log.Fatal(http.ListenAndServe(":8080", nil))
}
```
