#!/usr/bin/env bash
# 管理后台（若依 live-admin + 管理页面）更新脚本
# 从 GitHub AlexFrankHu/project_deployment 的 lygg-live-bg/ 下载更新包，解压到 /opt/lygg-live 对应目录。
# 用法：sudo bash /opt/lygg-live/update.sh
# 脚本不会重启服务；结束时会提示是否需要执行 restart.sh。
set -euo pipefail

D=${LYGG_HOME:-/opt/lygg-live}
RAW=https://raw.githubusercontent.com/AlexFrankHu/project_deployment/main/lygg-live-bg
# 国内连不上 GitHub，按顺序尝试加速镜像，最后直连。可在 $D/update.env 里用 MIRRORS="..." 覆盖
MIRRORS="https://gh-proxy.com/ https://ghfast.top/ https://gh-proxy.org/ https://cdn.gh-proxy.com/ https://hk.gh-proxy.com/ direct"
KEEP_BACKUPS=3
[ -f "$D/update.env" ] && . "$D/update.env"

[ "$(id -u)" = 0 ] || { echo "请用 sudo 执行：sudo bash $0"; exit 1; }

# 更新包里可能带新版 update.sh，先复制到临时文件再执行，避免运行中被覆盖
if [ "${LYGG_BG_COPY:-}" != 1 ]; then
  T=$(mktemp /tmp/lygg-bg-update.XXXXXX)
  cp "$0" "$T"
  LYGG_BG_COPY=1 exec bash "$T" "$@"
fi

WORK=$(mktemp -d /tmp/lygg-bg-work.XXXXXX)
trap 'rm -rf "$WORK" "$0"' EXIT
NOW=$(date +%s)

command -v unzip >/dev/null || { echo "安装 unzip ..."; apt-get install -y -qq unzip >/dev/null; }
[ -d "$D/admin" ] || { echo "没找到 $D/admin，请先用安装包装好管理后台"; exit 1; }

# fetch 相对路径 输出文件 [sha256]
fetch() {
  local path=$1 out=$2 sha=${3:-} m url
  for m in $MIRRORS; do
    if [ "$m" = direct ]; then url="$RAW/$path"; else url="$m$RAW/$path"; fi
    rm -f "$out"
    if curl -fsL --connect-timeout 8 -m 900 -o "$out" "$url?t=$NOW"; then
      if [ -z "$sha" ] || [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$sha" ]; then
        return 0
      fi
      echo "  校验不通过，换下一个地址（$m）" >&2
    else
      echo "  下载失败，换下一个地址（$m）" >&2
    fi
  done
  return 1
}

VF=$D/admin/BG_VERSION
CUR=$(cat "$VF" 2>/dev/null || echo 0)
echo "当前版本：$CUR"

fetch versions.txt "$WORK/versions.txt" || { echo "所有下载地址都失败，检查网络或在 $D/update.env 里换 MIRRORS"; exit 1; }
awk -F'\t' -v c="$CUR" '!/^#/ && NF >= 3 && ($1 + 0) > (c + 0)' "$WORK/versions.txt" > "$WORK/pending.txt"
if [ ! -s "$WORK/pending.txt" ]; then
  echo "已是最新版本，不需要更新。"
  exit 0
fi
echo "待安装的更新："
awk -F'\t' '{printf "  %s  %s\n", $1, $4}' "$WORK/pending.txt"

NEED_RESTART=0
SQL_LIST=""
mkdir -p "$D/backup"

while IFS=$'\t' read -r VER SHA RESTART NOTES; do
  echo ""
  echo ">> 安装 $VER"
  W=$WORK/$VER
  X=$W/x
  mkdir -p "$X"
  fetch "bg-$VER.zip" "$W/pkg.zip" "$SHA" || { echo "bg-$VER.zip 下载失败，已停止（已安装的版本不受影响）"; exit 1; }
  unzip -q "$W/pkg.zip" -d "$X"
  B=$D/backup/bg-$VER
  rm -rf "$B" && mkdir -p "$B"

  if [ -f "$X/admin/live-admin.jar" ]; then
    [ -f "$D/admin/live-admin.jar" ] && cp -p "$D/admin/live-admin.jar" "$B/"
    install -m 644 "$X/admin/live-admin.jar" "$D/admin/live-admin.jar"
    echo "  更新 admin/live-admin.jar"
  fi
  if ls "$X"/admin/lib/*.jar >/dev/null 2>&1; then
    mkdir -p "$D/admin/lib"
    cp "$X"/admin/lib/*.jar "$D/admin/lib/"
    echo "  新增依赖 $(ls "$X"/admin/lib/*.jar | wc -l) 个：admin/lib/"
  fi
  if [ -f "$X/lib-delete.txt" ]; then
    mkdir -p "$B/lib"
    while read -r J; do
      if [ -n "$J" ] && [ -f "$D/admin/lib/$J" ]; then
        mv "$D/admin/lib/$J" "$B/lib/"
        echo "  删除旧依赖 admin/lib/$J"
      fi
    done < "$X/lib-delete.txt"
  fi
  if [ -d "$X/admin-ui" ]; then
    rm -rf "$D/admin-ui.new"
    cp -r "$X/admin-ui" "$D/admin-ui.new"
    [ -d "$D/admin-ui" ] && mv "$D/admin-ui" "$B/admin-ui"
    mv "$D/admin-ui.new" "$D/admin-ui"
    echo "  更新 admin-ui（管理页面）"
  fi
  if ls "$X"/admin-sql/*.sql >/dev/null 2>&1; then
    mkdir -p "$D/admin-sql"
    for F in "$X"/admin-sql/*.sql; do
      cp "$F" "$D/admin-sql/"
      SQL_LIST="$SQL_LIST $D/admin-sql/$(basename "$F")"
      echo "  新 SQL：admin-sql/$(basename "$F")"
    done
  fi
  for S in update.sh restart.sh; do
    if [ -f "$X/$S" ]; then
      install -m 755 "$X/$S" "$D/$S"
      echo "  更新 $S"
    fi
  done
  if [ -f "$X/lib.list" ]; then
    MISSING=$(while read -r J; do [ -z "$J" ] || [ -f "$D/admin/lib/$J" ] || echo "$J"; done < "$X/lib.list")
    if [ -n "$MISSING" ]; then
      echo "  警告：admin/lib/ 缺少以下依赖，后台会启动失败，请把输出发给 Devin："
      echo "$MISSING" | sed 's/^/    /'
    fi
  fi
  [ -f "$X/UPDATE.txt" ] && sed 's/^/  | /' "$X/UPDATE.txt"
  echo "$VER" > "$VF"
  [ "$RESTART" = yes ] && NEED_RESTART=1
done < "$WORK/pending.txt"

ls -1dt "$D"/backup/bg-* 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -rf

echo ""
echo "==== 更新完成：$CUR -> $(cat "$VF") ===="
echo "旧文件备份在 $D/backup/（保留最近 $KEEP_BACKUPS 次）"
if [ -n "$SQL_LIST" ]; then
  echo ""
  echo "【需要执行 SQL】请先执行："
  for F in $SQL_LIST; do echo "  sudo mysql lygg_live < $F"; done
fi
echo ""
if [ "$NEED_RESTART" = 1 ]; then
  echo "【需要重启】本次更新了 jar，请执行：sudo bash $D/restart.sh"
else
  echo "【无需重启】只更新了页面，浏览器按 Ctrl+F5 刷新即可"
fi
