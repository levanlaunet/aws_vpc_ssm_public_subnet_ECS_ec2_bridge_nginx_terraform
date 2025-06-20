#!/bin/bash
set -xe

# Cấu hình cluster
mkdir -p /etc/ecs
echo "ECS_CLUSTER=MyCluster" >> /etc/ecs/ecs.config

# Cài Docker nếu cần
yum update -y
yum install -y docker

systemctl enable docker
systemctl start docker

# Chờ Docker sẵn sàng
sleep 5

# Tự khởi động ECS Agent bằng tay
docker run --name ecs-agent \
  --detach=true \
  --restart=on-failure:10 \
  --volume=/var/run/docker.sock:/var/run/docker.sock \
  --volume=/var/log/ecs:/log \
  --volume=/var/lib/ecs/data:/data \
  --net=host \
  --env=ECS_LOGFILE=/log/ecs-agent.log \
  --env=ECS_DATADIR=/data \
  --env=ECS_CLUSTER=MyCluster \
  --env=ECS_ENABLE_CONTAINER_METADATA=true \
  amazon/amazon-ecs-agent:latest

echo "Started ECS agent manually via Docker" >> /var/log/userdata.log
