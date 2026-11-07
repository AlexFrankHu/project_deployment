#!/usr/bin/env bash
# 重启管理后台（live-admin），等待启动完成
# 用法：sudo bash /opt/lygg-live/restart.sh
set -uo pipefail
D=${LYGG_HOME:-/opt/lygg-live}
[ "$(id -u)" = 0 ] || { echo "请用 sudo 执行：sudo bash $0"; exit 1; }

echo "重启 live-admin ..."
systemctl restart live-admin
for i in $(seq 1 45); do
  sleep 2
  if curl -s -m 3 http://127.0.0.1:8082/captchaImage | grep -q '"code": *200'; then
    echo "live-admin 已启动（约 $((i * 2)) 秒），版本：$(cat "$D/admin/BG_VERSION" 2>/dev/null || echo 未知)"
    exit 0
  fi
done
echo "live-admin 90 秒内没有启动成功，最近日志："
journalctl -u live-admin -n 30 --no-pager
tail -n 30 "$D/admin/logs/sys-error.log" 2>/dev/null
exit 1
