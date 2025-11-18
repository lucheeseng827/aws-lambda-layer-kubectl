#!/bin/bash
# Serverless Functions on Kubernetes via Lambda with Knative
# This Lambda function deploys and manages Knative services on K8s

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
kubectl create namespace serverless-knative --dry-run=client -o yaml | kubectl apply -f - 2>&1

# Main business logic
case $action in
    "deploy")
        # Deploy a new Knative service
        func_name=$(echo $input_data | jq -r '.function.name')
        func_image=$(echo $input_data | jq -r '.function.image')
        func_port=$(echo $input_data | jq -r '.function.port // 8080')
        min_replicas=$(echo $input_data | jq -r '.function.replicas.min // 0')
        max_replicas=$(echo $input_data | jq -r '.function.replicas.max // 10')
        cpu_request=$(echo $input_data | jq -r '.function.resources.requests.cpu // "100m"')
        mem_request=$(echo $input_data | jq -r '.function.resources.requests.memory // "128Mi"')
        cpu_limit=$(echo $input_data | jq -r '.function.resources.limits.cpu // "1000m"')
        mem_limit=$(echo $input_data | jq -r '.function.resources.limits.memory // "512Mi"')
        concurrency=$(echo $input_data | jq -r '.function.concurrency // 100')
        env_vars=$(echo $input_data | jq -c '.function.env // []')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        if [ -z "$func_image" ] || [ "$func_image" == "null" ]; then
            echo "Error: function.image is required"
            exit 1
        fi

        deploy_knative_service "$func_name" "$func_image" "$func_port" "$min_replicas" "$max_replicas" \
                               "$cpu_request" "$mem_request" "$cpu_limit" "$mem_limit" "$concurrency" "$env_vars"

        # Get the service URL
        service_url=$(get_service_url "$func_name")

        # Get service status
        ready_condition=$(kubectl get ksvc ${func_name} -n serverless-knative -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

        # Return response
        cat <<EOF
{
    "status": "success",
    "action": "deploy",
    "function": {
        "name": "$func_name",
        "image": "$func_image",
        "url": "$service_url",
        "namespace": "serverless-knative",
        "ready": "$ready_condition",
        "framework": "knative"
    }
}
EOF
        ;;

    "delete")
        # Delete a Knative service
        func_name=$(echo $input_data | jq -r '.function.name')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        delete_knative_service "$func_name"

        cat <<EOF
{
    "status": "success",
    "action": "delete",
    "function": {
        "name": "$func_name",
        "framework": "knative"
    }
}
EOF
        ;;

    "list")
        # List all Knative services
        services_output=$(kubectl get ksvc -n serverless-knative -o json 2>/dev/null || echo '{"items":[]}')

        cat <<EOF
{
    "status": "success",
    "action": "list",
    "framework": "knative",
    "services": $services_output
}
EOF
        ;;

    "status")
        # Get status of a specific Knative service
        func_name=$(echo $input_data | jq -r '.function.name')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        service_status=$(kubectl get ksvc ${func_name} -n serverless-knative -o json 2>/dev/null || echo '{}')
        revisions_status=$(kubectl get revisions -n serverless-knative -l serving.knative.dev/service=${func_name} -o json 2>/dev/null || echo '{"items":[]}')
        pods_status=$(kubectl get pods -n serverless-knative -l serving.knative.dev/service=${func_name} -o json 2>/dev/null || echo '{"items":[]}')
        service_url=$(get_service_url "$func_name")

        cat <<EOF
{
    "status": "success",
    "action": "status",
    "framework": "knative",
    "function": {
        "name": "$func_name",
        "url": "$service_url",
        "service": $service_status,
        "revisions": $revisions_status,
        "pods": $pods_status
    }
}
EOF
        ;;

    "scale")
        # Scale a Knative service
        func_name=$(echo $input_data | jq -r '.function.name')
        min_replicas=$(echo $input_data | jq -r '.function.replicas.min // 0')
        max_replicas=$(echo $input_data | jq -r '.function.replicas.max // 10')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        scale_knative_service "$func_name" "$min_replicas" "$max_replicas"

        cat <<EOF
{
    "status": "success",
    "action": "scale",
    "framework": "knative",
    "function": {
        "name": "$func_name",
        "minReplicas": $min_replicas,
        "maxReplicas": $max_replicas
    }
}
EOF
        ;;

    "update")
        # Update Knative service image
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

        update_knative_service_image "$func_name" "$new_image"

        service_url=$(get_service_url "$func_name")

        cat <<EOF
{
    "status": "success",
    "action": "update",
    "framework": "knative",
    "function": {
        "name": "$func_name",
        "image": "$new_image",
        "url": "$service_url"
    }
}
EOF
        ;;

    "traffic-split")
        # Configure traffic split between revisions
        func_name=$(echo $input_data | jq -r '.function.name')
        revision1=$(echo $input_data | jq -r '.traffic[0].revision')
        percent1=$(echo $input_data | jq -r '.traffic[0].percent')
        revision2=$(echo $input_data | jq -r '.traffic[1].revision // ""')
        percent2=$(echo $input_data | jq -r '.traffic[1].percent // 0')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        if [ -n "$revision2" ] && [ "$revision2" != "null" ]; then
            set_traffic_split "$func_name" "$revision1" "$percent1" "$revision2" "$percent2"
        else
            # Single revision, 100% traffic
            rollback_revision "$func_name" "$revision1"
        fi

        cat <<EOF
{
    "status": "success",
    "action": "traffic-split",
    "framework": "knative",
    "function": {
        "name": "$func_name",
        "traffic": [
            {"revision": "$revision1", "percent": $percent1},
            {"revision": "$revision2", "percent": $percent2}
        ]
    }
}
EOF
        ;;

    "revisions")
        # List all revisions for a service
        func_name=$(echo $input_data | jq -r '.function.name')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        revisions_output=$(kubectl get revisions -n serverless-knative -l serving.knative.dev/service=${func_name} -o json 2>/dev/null || echo '{"items":[]}')

        cat <<EOF
{
    "status": "success",
    "action": "revisions",
    "framework": "knative",
    "function": {
        "name": "$func_name",
        "revisions": $revisions_output
    }
}
EOF
        ;;

    "rollback")
        # Rollback to a specific revision
        func_name=$(echo $input_data | jq -r '.function.name')
        revision_name=$(echo $input_data | jq -r '.revision')

        if [ -z "$func_name" ] || [ "$func_name" == "null" ]; then
            echo "Error: function.name is required"
            exit 1
        fi

        if [ -z "$revision_name" ] || [ "$revision_name" == "null" ]; then
            echo "Error: revision is required"
            exit 1
        fi

        rollback_revision "$func_name" "$revision_name"

        cat <<EOF
{
    "status": "success",
    "action": "rollback",
    "framework": "knative",
    "function": {
        "name": "$func_name",
        "revision": "$revision_name"
    }
}
EOF
        ;;

    *)
        cat <<EOF
{
    "status": "error",
    "message": "Unknown action: $action. Valid actions: deploy, delete, list, status, scale, update, traffic-split, revisions, rollback"
}
EOF
        exit 1
        ;;
esac

exit 0
