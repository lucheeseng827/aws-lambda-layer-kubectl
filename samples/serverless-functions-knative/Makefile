.PHONY: help install-knative deploy-controller invoke-deploy invoke-list invoke-status clean

CLUSTER_NAME ?= default
LAMBDA_FUNC_NAME ?= serverless-knative-controller
LAMBDA_REGION ?= us-east-1
LAYER_ARN ?= $(shell aws cloudformation describe-stacks --stack-name eks-kubectl-layer-stack --query 'Stacks[0].Outputs[0].OutputValue' --output text --region $(LAMBDA_REGION))
LAMBDA_ROLE_ARN ?= arn:aws:iam::$(shell aws sts get-caller-identity --query Account --output text):role/LambdaEKSAdminRole
S3BUCKET ?= your-s3-bucket
AWS_PROFILE ?= default
KNATIVE_VERSION ?= 1.12.0

help:
	@echo "Available targets:"
	@echo "  install-knative      - Install Knative Serving on EKS cluster"
	@echo "  verify-knative       - Verify Knative installation"
	@echo "  deploy-controller    - Deploy Lambda Knative controller function"
	@echo "  invoke-deploy        - Deploy a sample Knative service"
	@echo "  invoke-list          - List all Knative services"
	@echo "  invoke-status        - Get Knative service status"
	@echo "  invoke-delete        - Delete a Knative service"
	@echo "  invoke-traffic-split - Configure traffic split"
	@echo "  invoke-rollback      - Rollback to previous revision"
	@echo "  test-local           - Test function handler locally"
	@echo "  clean                - Clean up resources"

install-knative:
	@echo "Installing Knative Serving v$(KNATIVE_VERSION)..."
	@echo "Step 1: Installing CRDs..."
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-v$(KNATIVE_VERSION)/serving-crds.yaml
	@echo "Step 2: Installing core components..."
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-v$(KNATIVE_VERSION)/serving-core.yaml
	@echo "Step 3: Installing Kourier networking layer..."
	kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v$(KNATIVE_VERSION)/kourier.yaml
	@echo "Step 4: Configuring Knative to use Kourier..."
	kubectl patch configmap/config-network \
		--namespace knative-serving \
		--type merge \
		--patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
	@echo "Step 5: Installing Magic DNS (for development)..."
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-v$(KNATIVE_VERSION)/serving-default-domain.yaml
	@echo "Step 6: Creating namespace..."
	kubectl apply -f k8s-manifests/namespace.yaml
	@echo "Knative installation complete!"
	@echo "Waiting for Knative to be ready..."
	@sleep 10
	@kubectl wait --for=condition=Ready pods --all -n knative-serving --timeout=300s
	@kubectl wait --for=condition=Ready pods --all -n kourier-system --timeout=300s
	@echo "Knative is ready!"

verify-knative:
	@echo "Verifying Knative installation..."
	@echo "---"
	@echo "Knative Serving Pods:"
	kubectl get pods -n knative-serving
	@echo "---"
	@echo "Kourier Pods:"
	kubectl get pods -n kourier-system
	@echo "---"
	@echo "Knative Services:"
	kubectl get ksvc -A

deploy-controller:
	@echo "Deploying Lambda Knative controller..."
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
	@echo "Lambda Knative controller deployed!"

invoke-deploy:
	@echo "Deploying sample Knative service..."
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
	@echo "Listing all Knative services..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/list-functions.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-status:
	@echo "Getting Knative service status..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/get-status.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-scale:
	@echo "Scaling Knative service..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/scale-function.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-update:
	@echo "Updating Knative service..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/update-function.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-traffic-split:
	@echo "Configuring traffic split..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/traffic-split.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-revisions:
	@echo "Listing revisions..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/list-revisions.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-rollback:
	@echo "Rolling back to previous revision..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/rollback.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

invoke-delete:
	@echo "Deleting Knative service..."
	aws lambda invoke \
		--function-name $(LAMBDA_FUNC_NAME) \
		--payload file://examples/delete-function.json \
		--region $(LAMBDA_REGION) \
		--profile $(AWS_PROFILE) \
		response.json
	@cat response.json | jq .
	@rm response.json

test-local:
	@echo "Testing Lambda handler locally (requires kubectl configured and Knative installed)..."
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

uninstall-knative:
	@echo "WARNING: This will delete all Knative services and Knative itself!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		kubectl delete -f https://github.com/knative/serving/releases/download/knative-v$(KNATIVE_VERSION)/serving-default-domain.yaml; \
		kubectl delete -f https://github.com/knative/net-kourier/releases/download/knative-v$(KNATIVE_VERSION)/kourier.yaml; \
		kubectl delete -f https://github.com/knative/serving/releases/download/knative-v$(KNATIVE_VERSION)/serving-core.yaml; \
		kubectl delete -f https://github.com/knative/serving/releases/download/knative-v$(KNATIVE_VERSION)/serving-crds.yaml; \
		kubectl delete namespace serverless-knative; \
		echo "Knative uninstalled"; \
	fi
