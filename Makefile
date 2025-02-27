TEST_DIR := tests

.DEFAULT_GOAL := help

.PHONY: init plan apply destroy test clean

help: ## Show this help
	@echo ""
	@echo "${YELLOW}Available Commands:${RESET}"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

init: ## Initialize terraform
	terraform init

plan: ## Plan terraform
	terraform plan

apply: ## Apply terraform
	terraform apply -auto-approve

destroy: ## Destroy terraform
	terraform destroy -auto-approve

clean: ## Clean up
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
