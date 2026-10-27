#!/bin/bash
# Boot script for app instances (Amazon Linux 2023). Logs: /var/log/cloud-init-output.log
set -euo pipefail

dnf install -y docker
systemctl enable --now docker

TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

IMAGE=$(aws ssm get-parameter --region ${region} --name "${image_param}" --query Parameter.Value --output text)
DATABASE_URL=$(aws ssm get-parameter --region ${region} --name "${database_url_param}" --with-decryption --query Parameter.Value --output text)

# Env file instead of -e flags so the DB password doesn't show up in `ps` output.
install -m 600 /dev/null /etc/chatops.env
cat > /etc/chatops.env <<ENV
DATABASE_URL=$DATABASE_URL
INSTANCE_ID=$INSTANCE_ID
LLM_PROVIDER=${llm_provider}
ENV

docker pull "$IMAGE"
docker run -d --name chatops --restart always \
  -p 8000:8000 \
  --env-file /etc/chatops.env \
  --log-driver awslogs \
  --log-opt awslogs-region=${region} \
  --log-opt awslogs-group=${log_group} \
  --log-opt awslogs-stream="$INSTANCE_ID" \
  "$IMAGE"
