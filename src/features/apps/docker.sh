#!/usr/bin/env bash

# Docker 入口：资产查询、Compose、容器操作和菜单分别维护。
. "$ROOT_DIR/src/features/apps/docker/inventory.sh"
. "$ROOT_DIR/src/features/apps/docker/compose.sh"
. "$ROOT_DIR/src/features/apps/docker/containers.sh"
. "$ROOT_DIR/src/features/apps/docker/volumes.sh"
. "$ROOT_DIR/src/features/apps/docker/menu.sh"
