#!/bin/bash
# Serverless Functions on Kubernetes via Lambda
# This Lambda function deploys and manages serverless functions on K8s

set -euo pipefail

# Include the common-used shortcuts
source libs.sh

# Load .env.config cache and read previously used cluster_name
[ -f /tmp/.env.config ] && cat /tmp/.env.config && source /tmp/.env.config

# Parse input
input_data=$1
action=$(echo $input_data | jq -r '.action // "deploy"')
input_cluster_name=$(echo $input_data | jq -r '.cluster_name // ""')

# Update kubeconfig if cluster name changed
if [ -n "${input_cluster_name}" ] && [ "${input_cluster_name}" != "${cluster_name:-}" ]; then
    echo "Got new cluster_name=$input_cluster_name - updating kubeconfig now..."
    update_kubeconfig "$input_cluster_name" || exit 1
    cluster_name="$input_cluster_name"
    echo "Writing new cluster_name=${cluster_name} to /tmp/.env.config"
    echo "cluster_name=${cluster_name}" > /tmp/.env.config
fi

# Ensure namespace exists
kubectl create namespace serverless-functions --dry-run=client -o yaml | kubectl apply -f - 2>&1

# Main business logic
case $action in
    "deploy")
        # Deploy a new serverless function
        func_name=$(echo $input_data | jq -r '.function.name')
        func_image=$(echo $input_data | jq -r '.function.image')
        func_port=$(echo $input_data | jq -r '.function.port // 8080')
        min_replicas=$(echo $input_data | jq -r '.function.replicas.min // 1')
        max_replicas=$(echo $input_data | jq -r '.function.replicas.max // 10')
        cpu_request=$(echo $input_data | jq -r '.function.resources.requests.cpu // "100m"')
        mem_request=$(echo $input_data | jq -r '.function.resources.requests.memory // "128Mi"')
        cpu_limit=$(echo $input_data | jq -r '.function.resources.limits.cpu // "500m"')
        mem_limit=$(echo $input_data | jq -r '.function.resources.limits.memory // "512Mi"')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        if [ -z "$func_image" ] || [ "$func_image" == "null" ]; then
            echo "Error: function.image is required"
            exit 1
        fi

        deploy_function "$func_name" "$func_image" "$func_port" "$min_replicas" "$max_replicas" \
                       "$cpu_request" "$mem_request" "$cpu_limit" "$mem_limit"

        # Get the service endpoint
        service_ip=$(kubectl get svc sfn-${func_name} -n serverless-functions -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "pending")

        # Return response
        cat <<EOF
{
    "status": "success",
    "action": "deploy",
    "function": {
        "name": "$func_name",
        "image": "$func_image",
        "endpoint": "http://${service_ip}",
        "namespace": "serverless-functions"
    }
}
EOF
        ;;

    "delete")
        # Delete a serverless function
        func_name=$(echo $input_data | jq -r '.function.name')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        delete_function "$func_name"

        cat <<EOF
{
    "status": "success",
    "action": "delete",
    "function": {
        "name": "$func_name"
    }
}
EOF
        ;;

    "list")
        # List all serverless functions
        functions_output=$(kubectl get deployments -n serverless-functions -l type=serverless-function -o json 2>/dev/null || echo '{"items":[]}')

        cat <<EOF
{
    "status": "success",
    "action": "list",
    "functions": $functions_output
}
EOF
        ;;

    "status")
        # Get status of a specific function
        func_name=$(echo $input_data | jq -r '.function.name')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        deployment_status=$(kubectl get deployment sfn-${func_name} -n serverless-functions -o json 2>/dev/null || echo '{}')
        service_status=$(kubectl get service sfn-${func_name} -n serverless-functions -o json 2>/dev/null || echo '{}')
        hpa_status=$(kubectl get hpa sfn-${func_name} -n serverless-functions -o json 2>/dev/null || echo '{}')
        pods_status=$(kubectl get pods -n serverless-functions -l app=${func_name} -o json 2>/dev/null || echo '{"items":[]}')

        cat <<EOF
{
    "status": "success",
    "action": "status",
    "function": {
        "name": "$func_name",
        "deployment": $deployment_status,
        "service": $service_status,
        "hpa": $hpa_status,
        "pods": $pods_status
    }
}
EOF
        ;;

    "scale")
        # Scale a function
        func_name=$(echo $input_data | jq -r '.function.name')
        replicas=$(echo $input_data | jq -r '.function.replicas // 1')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        scale_function "$func_name" "$replicas"

        cat <<EOF
{
    "status": "success",
    "action": "scale",
    "function": {
        "name": "$func_name",
        "replicas": $replicas
    }
}
EOF
        ;;

    "update")
        # Update function image
        func_name=$(echo $input_data | jq -r '.function.name')
        new_image=$(echo $input_data | jq -r '.function.image')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        if [ -z "$new_image" ] || [ "$new_image" == "null" ]; then
            echo "Error: function.image is required"
            exit 1
        fi

        update_function_image "$func_name" "$new_image"

        cat <<EOF
{
    "status": "success",
    "action": "update",
    "function": {
        "name": "$func_name",
        "image": "$new_image"
    }
}
EOF
        ;;

    *)
        cat <<EOF
{
    "status": "error",
    "message": "Unknown action: $action. Valid actions: deploy, delete, list, status, scale, update"
}
EOF
        exit 1
        ;;
esac

exit 0
