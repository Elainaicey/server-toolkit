#!/usr/bin/env bash

# 服务中心入口：状态查询、Journal、Unit 和审计保持独立职责。
. "$ROOT_DIR/src/features/services/overview.sh"
. "$ROOT_DIR/src/features/services/journal.sh"
. "$ROOT_DIR/src/features/services/units.sh"
. "$ROOT_DIR/src/features/services/audit.sh"
. "$ROOT_DIR/src/features/services/menu.sh"
