# lygg-live-bg：直播管理后台（若依）更新包

业务机目录 `/opt/lygg-live/`。每个 `bg-版本.zip` 只包含这次有变化的文件，没有任何配置文件（配置在业务机的 `*.env` 里）。

| 文件 | 说明 |
|---|---|
| `versions.txt` | 版本列表：版本、sha256、是否需要重启、说明 |
| `bg-版本.zip` | 更新包，目录结构和 `/opt/lygg-live/` 一致 |
| `update.sh` | 更新脚本：按顺序安装比本机新的版本，不会自动重启 |
| `restart.sh` | 重启 live-admin 并等待启动完成 |
| `lib.list`、`state.txt` | 打包用的记录，业务机用不到 |

## 第一次安装脚本（业务机执行，国内经过加速镜像下载）

```bash
for f in update.sh restart.sh; do sudo curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/AlexFrankHu/project_deployment/main/lygg-live-bg/$f -o /opt/lygg-live/$f; done
sudo chmod +x /opt/lygg-live/update.sh /opt/lygg-live/restart.sh
```

## 以后每次更新

```bash
sudo bash /opt/lygg-live/update.sh
# 结尾会提示【需要重启】或【无需重启】，需要重启时：
sudo bash /opt/lygg-live/restart.sh
```

- 本机版本记录在 `/opt/lygg-live/admin/BG_VERSION`。
- 旧文件备份在 `/opt/lygg-live/backup/bg-版本/`，保留最近 3 次。
- 镜像都连不上时，在 `/opt/lygg-live/update.env` 里写 `MIRRORS="https://其他镜像/ direct"`。
