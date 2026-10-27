# Shortcuts. Run `make help`.
TF_DIR := terraform/envs/dev

.PHONY: help test up down tf-init plan apply destroy grafana
help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

test: ## Run app tests
	cd app && python -m pytest -q

up: ## Run all three tiers + monitoring locally
	docker compose up --build

down: ## Stop local stack and delete its data
	docker compose down -v

tf-init: ## Init dev env (needs STATE_BUCKET=...)
	cd $(TF_DIR) && terraform init -backend-config="bucket=$(STATE_BUCKET)"

plan: ## terraform plan for dev
	cd $(TF_DIR) && terraform plan

apply: ## terraform apply for dev
	cd $(TF_DIR) && terraform apply

destroy: ## Tear down dev (do this after every session)
	cd $(TF_DIR) && terraform destroy

grafana: ## Open an SSM tunnel to Grafana on localhost:3000
	cd $(TF_DIR) && eval "$$(terraform output -raw grafana_tunnel_command)"
