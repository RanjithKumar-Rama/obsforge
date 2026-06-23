.PHONY: setup create-secrets deploy teardown status logs \
        port-forward-grafana port-forward-querier docker-up docker-down

KUBECTL    = kubectl
NAMESPACE  = monitoring

# Bootstrap then deploy
setup: create-secrets deploy

create-secrets:
	./scripts/create-secrets.sh

deploy:
	./scripts/deploy.sh

teardown:
	./scripts/teardown.sh

status:
	$(KUBECTL) get pods -n $(NAMESPACE) -o wide

# Stream logs from every ObsForge pod at once
logs:
	$(KUBECTL) logs -n $(NAMESPACE) -l app.kubernetes.io/part-of=obsforge --prefix -f

port-forward-grafana:
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/grafana 3000:3000

port-forward-querier:
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/thanos-querier 10902:10902

docker-up:
	docker compose up -d

docker-down:
	docker compose down -v
