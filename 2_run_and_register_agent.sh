#!/bin/bash
set -e

# Script to deploy Azure DevOps agent as a Docker Swarm service with N replicas
# Configuration is loaded from .env file in the same directory

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Load environment variables from .env file
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found at $ENV_FILE"
  echo "Please create a .env file based on .env.example"
  exit 1
fi

# Source the .env file
set -a
source "$ENV_FILE"
set +a

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Validate required environment variables
validate_env() {
  if [ -z "$AZP_URL" ]; then
    print_error "AZP_URL environment variable is not set"
    echo "Usage: AZP_URL=https://dev.azure.com/myorg AZP_TOKEN=<token> $0"
    exit 1
  fi

  if [ -z "$AZP_TOKEN" ]; then
    print_error "AZP_TOKEN environment variable is not set"
    exit 1
  fi

  print_success "Required environment variables validated"
}

# Set default values for optional variables
set_defaults() {
  AZP_POOL="${AZP_POOL:-Default}"
  SERVICE_NAME="${SERVICE_NAME:-ado-agent}"
  IMAGE="${IMAGE:-ado-agent:latest}"
  REPLICAS="${REPLICAS:-2}"

  # AZP_AGENT_NAME is intentionally not set here so that each replica uses its
  # container IP as a unique agent name (handled by start.sh inside the image)

  print_success "Using service name: $SERVICE_NAME"
  print_success "Using agent pool: $AZP_POOL"
  print_success "Using replicas: $REPLICAS"
}

# Check if image exists
check_image() {
  print_header "Checking Docker image"

  if ! docker images | grep -q "$IMAGE"; then
    print_warning "Image $IMAGE not found. Building..."
    bash build_docker_file.sh
  else
    print_success "Image $IMAGE found"
  fi
}

# Ensure Docker Swarm is active on this node
ensure_swarm() {
  print_header "Checking Docker Swarm"

  local swarm_state
  swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")

  if [ "$swarm_state" != "active" ]; then
    print_warning "Docker Swarm not active. Initializing..."
    # Detect the primary non-loopback IP to avoid ambiguity on multi-interface hosts
    local advertise_ip
    advertise_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
    if [ -z "$advertise_ip" ]; then
      advertise_ip=$(hostname -I | awk '{print $1}')
    fi
    print_warning "Using advertise address: $advertise_ip"
    docker swarm init --advertise-addr "$advertise_ip"
    print_success "Docker Swarm initialized"
  else
    print_success "Docker Swarm is already active"
  fi
}

# Remove existing service if present
cleanup_existing_service() {
  print_header "Cleaning up existing service"

  if docker service ls --filter="name=${SERVICE_NAME}" --format='{{.Name}}' 2>/dev/null | grep -q "^${SERVICE_NAME}$"; then
    print_warning "Removing existing service: $SERVICE_NAME"
    docker service rm "$SERVICE_NAME"

    local attempts=0
    while docker service ls --filter="name=${SERVICE_NAME}" --format='{{.Name}}' 2>/dev/null | grep -q "^${SERVICE_NAME}$"; do
      attempts=$((attempts + 1))
      if [ $attempts -ge 15 ]; then
        print_error "Timeout waiting for service removal"
        break
      fi
      sleep 2
    done
    print_success "Service removed"
  else
    print_success "No existing service found"
  fi
}

# Deploy the Swarm service with the configured number of replicas
create_service() {
  print_header "Creating Azure DevOps agent Swarm service"

  # Share host Docker Engine with agents (CLI in container → host dockerd).
  # --group grants access to docker.sock (Swarm uses --group, not --group-add).
  local group_args=()
  if [ -S /var/run/docker.sock ]; then
    local docker_gid
    docker_gid=$(stat -c '%g' /var/run/docker.sock)
    group_args=(--group "$docker_gid")
    print_success "docker.sock group access (GID $docker_gid)"
  else
    print_warning "/var/run/docker.sock not found on host"
  fi

  docker service create \
    --detach \
    --name "$SERVICE_NAME" \
    --replicas "$REPLICAS" \
    --restart-condition on-failure \
    --restart-max-attempts 3 \
    -e AZP_URL="$AZP_URL" \
    -e AZP_TOKEN="$AZP_TOKEN" \
    -e AZP_POOL="$AZP_POOL" \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    "${group_args[@]}" \
    "$IMAGE"

  print_success "Service '$SERVICE_NAME' created with $REPLICAS replicas"
}

# Wait until the desired number of replicas are running
monitor_startup() {
  print_header "Monitoring service startup"

  local max_attempts=60
  local attempt=0
  local delay=5

  while [ $attempt -lt $max_attempts ]; do
    local running_tasks
    running_tasks=$(docker service ls --filter="name=${SERVICE_NAME}" --format='{{.Replicas}}' 2>/dev/null | grep -oP '^\d+' || echo "0")

    if [ "$running_tasks" -ge "$REPLICAS" ] 2>/dev/null; then
      echo ""
      print_success "All $REPLICAS replicas are running"
      return 0
    fi

    attempt=$((attempt + 1))
    echo -ne "${BLUE}Waiting for replicas... ($running_tasks/$REPLICAS running, attempt $attempt/$max_attempts)${NC}\r"
    sleep $delay
  done

  echo ""
  print_warning "Monitoring timeout — service may still be initializing"
}

# Display service and task status
display_status() {
  print_header "Service status"
  docker service ls --filter="name=${SERVICE_NAME}"

  print_header "Service tasks"
  docker service ps "$SERVICE_NAME" \
    --format 'table {{.ID}}\t{{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Error}}'
}

# Main execution
main() {
  print_header "Azure DevOps Agent Swarm Launcher"

  validate_env
  set_defaults
  check_image
  ensure_swarm
  cleanup_existing_service
  create_service
  monitor_startup
  display_status

  print_header "Completion"
  echo ""
  print_success "Agent service is running!"
  echo "Service Name: $SERVICE_NAME"
  echo "Replicas:     $REPLICAS"
  echo "Pool:         $AZP_POOL"
  echo ""
  echo "Configuration loaded from: $ENV_FILE"
  echo "To view logs:  docker service logs -f $SERVICE_NAME"
  echo "To scale:      docker service scale ${SERVICE_NAME}=<n>"
  echo "To stop:       docker service rm $SERVICE_NAME"
  echo ""
}

main "$@"
