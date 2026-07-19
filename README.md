# Raindrop for LazyCat

Raindrop 是一款自托管、多用户的 RSS 阅读器。本仓库将上游 Docker 镜像打包为 LazyCat LPK v2，并通过 GitHub Actions 同时发布到懒猫官方应用商店和私有应用商店。

## 安装体验

- 安装时由懒猫设置向导创建管理员用户名和随机密码。
- Raindrop 使用向导参数自动初始化 SQLite 数据库，无需读取容器日志中的 setup token。
- 打开应用后自动填充管理员凭据并登录。
- 数据持久化在 `/lzcapp/var/data`，初始化目录权限后，容器继续以原生 `10001:10001` 非 root 身份运行。

## Upstream

- Source: <https://github.com/ca-x/raindrop>
- Docker image: `czyt/raindrop:v0.1.0`
- Package: `community.lazycat.app.raindrop`
- Target: `linux/amd64`

## Build

```bash
lzc-cli project release -o .lazycat-build/raindrop.lpk
lzc-cli lpk info .lazycat-build/raindrop.lpk
```

## Automated publishing

`.github/workflows/lazycat.yml` 使用 `ca-x/lazycat-github-action@v1` 检查 Docker Hub 的稳定版本、复制镜像到懒猫官方 Registry、创建版本化 GitHub Release Asset，并分别同步两个应用商店。

工作流需要以下 GitHub Secrets；Secret 值不得提交到仓库：

- `LAZYCAT_TOKEN`
- `APPSTORE_URL`
- `APPSTORE_TOKEN`
- `APP_ID`（可选）
- `PRIVATE_STORE_GROUP_CODES`（可选）

## English

The LazyCat installer provisions the first administrator through deployment parameters, initializes the bundled SQLite database, and automatically signs in on first launch. Persistent data is stored under `/lzcapp/var/data`, while the upstream container remains non-root.
