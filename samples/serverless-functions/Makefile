.PHONY: help install-crd deploy-controller invoke-deploy invoke-list invoke-status clean

CLUSTER_NAME ?= default
LAMBDA_FUNC_NAME ?= serverless-k8s-controller
LAMBDA_REGION ?= us-east-1
LAYER_ARN ?= $(shell aws cloudformation describe-stacks --stack-name eks-kubectl-layer-stack --query 'Stacks[0].Outputs[0].OutputValue' --output text --region $(LAMBDA_REGION))
LAMBDA_ROLE_ARN ?= arn:aws:iam::$(shell aws sts get-caller-identity --query Account --output text):role/LambdaEKSAdminRole
S3BUCKET ?= your-s3-bucket
AWS_PROFILE ?= default

help:
	@echo "Available targets:"
	@echo "  install-crd          - Install CRD and RBAC to K8s cluster"
	@echo "  deploy-controller    - Deploy Lambda controller function"
	@echo "  invoke-deploy        - Deploy a sample function"
	@echo "  invoke-list          - List all functions"
	@echo "  invoke-status        - Get function status"
	@echo "  invoke-delete        - Delete a function"
	@echo "  build-sample         - Build sample function Docker image"
	@echo "  test-local           - Test function handler locally"
	@echo "  clean                - Clean up resources"

install-crd:
	@echo "Installing CRD and RBAC resources..."
	kubectl apply -f k8s-manifests/namespace.yaml
	kubectl apply -f k8s-manifests/rbac.yaml
	kubectl apply -f k8s-manifests/function-crd.yaml
	@echo "Done!"

deploy-controller:
	@echo "Deploying Lambda controller..."
	@echo "Using Layer ARN: $(LAYER_ARN)"
	sam deploy \
		--template-file sam.yaml \
		--stack-name $(LAMBDA_FUNC_NAME)-stack \
		--parameter-overrides \
			ClusterName=$(CLUSTER_NAME) \
			FunctionName=$(LAMBDA_FUNC_NAME) \
			LambdaLayerKubectlArn=$(LAYER_ARN) \
			LambdaRoleArn=$(LAMBDA_ROLE_ARN) \
		--capabilities CAPABILITY_IAM \
		--region $(LAMBDA_REGION) \
		--s3-bucket $(S3BUCKET) \
		--profile $(AWS_PROFILE)
	@echo "Lambda controller deployed!"

invoke-deploy:
	@echo "Deploying sample function..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/deploy-function.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		--log-type Tail \
		response.json | jq -r '.LogResult' | base64 -d
	@cat response.json | jq .
	@rm response.json

invoke-list:
	@echo "Listing all functions..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/list-functions.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-status:
	@echo "Getting function status..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/get-status.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-scale:
	@echo "Scaling function..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/scale-function.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-delete:
	@echo "Deleting function..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/delete-function.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

build-sample:
	@echo "Building sample function Docker image..."
	cd examples/sample-function && \
	docker build -t sample-serverless-function:latest .
	@echo "Image built: sample-serverless-function:latest"

test-sample-local:
	@echo "Testing sample function locally..."
	cd examples/sample-function && \
	docker run -d -p 8080:8080 --name test-function sample-serverless-function:latest
	@sleep 3
	@echo "Testing endpoints..."
	@curl -s http://localhost:8080/ | jq .
	@curl -s http://localhost:8080/health | jq .
	@docker stop test-function
	@docker rm test-function
	@echo "Test completed!"

test-local:
	@echo "Testing Lambda handler locally (requires kubectl configured)..."
	@cd func.d && \
	export cluster_name=$(CLUSTER_NAME) && \
	./main.sh '{"action":"list"}'

clean:
	@echo "Cleaning up..."
	@rm -f response.json
	@echo "Done!"

destroy:
	@echo "Destroying Lambda controller stack..."
	aws cloudformation delete-stack \
		--stack-name $(LAMBDA_FUNC_NAME)-stack \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE)
	@echo "Stack deletion initiated"

uninstall-crd:
	@echo "WARNING: This will delete all serverless functions!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		kubectl delete -f k8s-manifests/function-crd.yaml; \
		kubectl delete -f k8s-manifests/rbac.yaml; \
		kubectl delete -f k8s-manifests/namespace.yaml; \
		echo "CRD and resources removed"; \
	fi
