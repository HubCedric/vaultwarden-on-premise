.PHONY: validate shellcheck compose-config

validate:
	./scripts/validate_repo.sh

shellcheck:
	shellcheck scripts/*.sh scripts/lib/*.sh scripts/experimental/*.sh

compose-config:
	cp deploy/node/.env.example /tmp/vaultwarden-node.env
	cp deploy/vps/.env.example /tmp/vaultwarden-vps.env
	docker compose --env-file /tmp/vaultwarden-node.env -f deploy/node/compose.yaml config --quiet
	docker compose --env-file /tmp/vaultwarden-vps.env -f deploy/vps/compose.yaml config --quiet
	rm -f /tmp/vaultwarden-node.env /tmp/vaultwarden-vps.env
