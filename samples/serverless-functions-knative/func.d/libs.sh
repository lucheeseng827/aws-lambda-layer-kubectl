export KUBECONFIG=/tmp/kubeconfig

update_kubeconfig(){
    aws eks update-kubeconfig --name "$1" --kubeconfig /tmp/kubeconfig
}

get_nodes(){
    kubectl get no
}

get_pods(){
    kubectl get po
}

get_all(){
    kubectl get all
}

# Deploy a Knative service
deploy_knative_service(){
    local func_name=$1
    local func_image=$2
    local func_port=${3:-8080}
    local min_replicas=${4:-0}  # Knative can scale to zero
    local max_replicas=${5:-10}
    local cpu_request=${6:-100m}
    local mem_request=${7:-128Mi}
    local cpu_limit=${8:-1000m}
    local mem_limit=${9:-512Mi}
    local concurrency=${10:-100}  # Max concurrent requests per pod
    local env_vars=${11:-""}  # JSON array of env vars

    echo "Deploying Knative service: $func_name"

    # Build environment variables section
    local env_section=""
    if [ -n "$env_vars" ] && [ "$env_vars" != "null" ]; then
        env_section=$(echo "$env_vars" | jq -r 'map("        - name: " + .name + "\n          value: \"" + .value + "\"") | join("\n")')
    fi

    # Create Knative Service
    cat <<EOF | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: ${func_name}
  namespace: serverless-knative
  labels:
    app: ${func_name}
    type: knative-function
    managed-by: lambda-kubectl
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "${min_replicas}"
        autoscaling.knative.dev/maxScale: "${max_replicas}"
        autoscaling.knative.dev/target: "${concurrency}"
        autoscaling.knative.dev/metric: "concurrency"
        autoscaling.knative.dev/scale-down-delay: "30s"
        autoscaling.knative.dev/stable-window: "60s"
      labels:
        app: ${func_name}
        type: knative-function
    spec:
      containerConcurrency: ${concurrency}
      containers:
      - name: function
        image: ${func_image}
        ports:
        - containerPort: ${func_port}
          protocol: TCP
        resources:
          requests:
            cpu: ${cpu_request}
            memory: ${mem_request}
          limits:
            cpu: ${cpu_limit}
            memory: ${mem_limit}
        env:
        - name: PORT
          value: "${func_port}"
${env_section}
        livenessProbe:
          httpGet:
            path: /health
            port: ${func_port}
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: ${func_port}
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

    echo "Knative service $func_name deployed successfully"

    # Wait for service to be ready
    echo "Waiting for service to be ready..."
    kubectl wait --for=condition=Ready ksvc/${func_name} -n serverless-knative --timeout=120s 2>/dev/null || true

    # Get the service URL
    local service_url=$(kubectl get ksvc ${func_name} -n serverless-knative -o jsonpath='{.status.url}' 2>/dev/null || echo "pending")
    echo "Service URL: $service_url"
}

# Delete a Knative service
delete_knative_service(){
    local func_name=$1

    echo "Deleting Knative service: $func_name"
    kubectl delete ksvc ${func_name} -n serverless-knative --ignore-not-found=true
    echo "Service $func_name deleted successfully"
}

# List all Knative services
list_knative_services(){
    echo "Listing all Knative services:"
    kubectl get ksvc -n serverless-knative
}

# Get Knative service status
get_knative_service_status(){
    local func_name=$1

    echo "Service: $func_name"
    echo "---"
    kubectl get ksvc ${func_name} -n serverless-knative -o yaml
    echo "---"
    echo "Revisions:"
    kubectl get revisions -n serverless-knative -l serving.knative.dev/service=${func_name}
    echo "---"
    echo "Routes:"
    kubectl get routes -n serverless-knative -l serving.knative.dev/service=${func_name}
    echo "---"
    echo "Pods:"
    kubectl get pods -n serverless-knative -l serving.knative.dev/service=${func_name}
}

# Update Knative service with new image
update_knative_service_image(){
    local func_name=$1
    local new_image=$2

    echo "Updating Knative service $func_name to image $new_image"

    kubectl patch ksvc ${func_name} -n serverless-knative --type='json' \
      -p="[{'op': 'replace', 'path': '/spec/template/spec/containers/0/image', 'value': '${new_image}'}]"

    echo "Service updated. New revision will be created."
    kubectl wait --for=condition=Ready ksvc/${func_name} -n serverless-knative --timeout=120s 2>/dev/null || true
}

# Set traffic split between revisions (for blue/green deployment)
set_traffic_split(){
    local func_name=$1
    local revision1=$2
    local percent1=$3
    local revision2=$4
    local percent2=$5

    echo "Setting traffic split for $func_name:"
    echo "  $revision1: $percent1%"
    echo "  $revision2: $percent2%"

    cat <<EOF | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: ${func_name}
  namespace: serverless-knative
spec:
  traffic:
  - revisionName: ${revision1}
    percent: ${percent1}
  - revisionName: ${revision2}
    percent: ${percent2}
EOF

    echo "Traffic split configured"
}

# Scale Knative service (by setting min/max replicas)
scale_knative_service(){
    local func_name=$1
    local min_replicas=$2
    local max_replicas=$3

    echo "Scaling Knative service $func_name to min:$min_replicas, max:$max_replicas"

    kubectl patch ksvc ${func_name} -n serverless-knative --type='json' \
      -p="[
        {'op': 'replace', 'path': '/spec/template/metadata/annotations/autoscaling.knative.dev~1minScale', 'value': '${min_replicas}'},
        {'op': 'replace', 'path': '/spec/template/metadata/annotations/autoscaling.knative.dev~1maxScale', 'value': '${max_replicas}'}
      ]"

    echo "Service scaling updated"
}

# Get service URL
get_service_url(){
    local func_name=$1
    kubectl get ksvc ${func_name} -n serverless-knative -o jsonpath='{.status.url}' 2>/dev/null || echo "Service not found"
}

# Get service metrics
get_service_metrics(){
    local func_name=$1

    echo "Service Metrics for $func_name:"
    echo "---"
    kubectl get ksvc ${func_name} -n serverless-knative -o json | jq '.status.traffic'
    echo "---"
    echo "Active Revisions:"
    kubectl get revisions -n serverless-knative -l serving.knative.dev/service=${func_name} \
      -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status,REASON:.status.conditions[?(@.type==\"Ready\")].reason
}

# List all revisions for a service
list_revisions(){
    local func_name=$1
    echo "Revisions for service $func_name:"
    kubectl get revisions -n serverless-knative -l serving.knative.dev/service=${func_name}
}

# Rollback to a specific revision
rollback_revision(){
    local func_name=$1
    local revision_name=$2

    echo "Rolling back $func_name to revision $revision_name"

    kubectl patch ksvc ${func_name} -n serverless-knative --type='json' \
      -p="[{'op': 'add', 'path': '/spec/traffic', 'value': [{'revisionName': '${revision_name}', 'percent': 100}]}]"

    echo "Rollback complete"
}
