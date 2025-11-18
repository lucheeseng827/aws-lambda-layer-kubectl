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

# Deploy a serverless function to K8s
deploy_function(){
    local func_name=$1
    local func_image=$2
    local func_port=${3:-8080}
    local min_replicas=${4:-1}
    local max_replicas=${5:-10}
    local cpu_request=${6:-100m}
    local mem_request=${7:-128Mi}
    local cpu_limit=${8:-500m}
    local mem_limit=${9:-512Mi}

    echo "Deploying serverless function: $func_name"

    # Create deployment
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sfn-${func_name}
  namespace: serverless-functions
  labels:
    app: ${func_name}
    type: serverless-function
    managed-by: lambda-kubectl
spec:
  replicas: ${min_replicas}
  selector:
    matchLabels:
      app: ${func_name}
  template:
    metadata:
      labels:
        app: ${func_name}
        type: serverless-function
    spec:
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

    # Create service
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sfn-${func_name}
  namespace: serverless-functions
  labels:
    app: ${func_name}
    type: serverless-function
    managed-by: lambda-kubectl
spec:
  selector:
    app: ${func_name}
  ports:
  - port: 80
    targetPort: ${func_port}
    protocol: TCP
  type: ClusterIP
EOF

    # Create HPA for auto-scaling
    cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sfn-${func_name}
  namespace: serverless-functions
  labels:
    app: ${func_name}
    type: serverless-function
    managed-by: lambda-kubectl
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sfn-${func_name}
  minReplicas: ${min_replicas}
  maxReplicas: ${max_replicas}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF

    echo "Function $func_name deployed successfully"
}

# Delete a serverless function from K8s
delete_function(){
    local func_name=$1

    echo "Deleting serverless function: $func_name"

    kubectl delete deployment sfn-${func_name} -n serverless-functions --ignore-not-found=true
    kubectl delete service sfn-${func_name} -n serverless-functions --ignore-not-found=true
    kubectl delete hpa sfn-${func_name} -n serverless-functions --ignore-not-found=true

    echo "Function $func_name deleted successfully"
}

# List all serverless functions
list_functions(){
    echo "Listing all serverless functions:"
    kubectl get deployments -n serverless-functions -l type=serverless-function
}

# Get function status and endpoint
get_function_status(){
    local func_name=$1

    echo "Function: $func_name"
    echo "---"
    kubectl get deployment sfn-${func_name} -n serverless-functions
    kubectl get service sfn-${func_name} -n serverless-functions
    kubectl get hpa sfn-${func_name} -n serverless-functions
    kubectl get pods -n serverless-functions -l app=${func_name}
}

# Scale function
scale_function(){
    local func_name=$1
    local replicas=$2

    echo "Scaling function $func_name to $replicas replicas"
    kubectl scale deployment sfn-${func_name} -n serverless-functions --replicas=$replicas
}

# Update function image
update_function_image(){
    local func_name=$1
    local new_image=$2

    echo "Updating function $func_name to image $new_image"
    kubectl set image deployment/sfn-${func_name} function=$new_image -n serverless-functions
    kubectl rollout status deployment/sfn-${func_name} -n serverless-functions
}
