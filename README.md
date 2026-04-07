# hysteria2-over-warp

基于 `debian:stable-slim` 的单容器项目：容器启动后先建立 Cloudflare WARP 连接，再启动 Hysteria 2 服务端，并通过 GitHub Actions 构建并发布 GHCR 镜像。

## 前置条件

- Docker
- Docker Compose v2
- 宿主机可用的 `/dev/net/tun`
- 允许容器使用 `NET_ADMIN`

## 使用 compose 部署

1. 复制环境变量模板：

   ```bash
   cp .env.example .env
   ```

2. 修改 `.env` 中至少以下字段：

   ```env
   HY2_PASSWORD=replace-with-a-strong-password
   ```

3. 拉取并启动服务：

   ```bash
   docker compose up -d
   ```

启动命令会读取 `.env` 中的变量，并通过 `docker-compose.yml` 使用 `ghcr.io/lengyuesky/hysteria2-over-warp:latest` 镜像。

查看日志：

```bash
docker compose logs -f proxy
```

停止服务：

```bash
docker compose down
```

## 证书策略

默认情况下，容器会在未提供可用证书时自动生成自签证书，并写入持久化卷 `/var/lib/hysteria/certs/`。

如果要使用外部证书：

1. 把证书文件放到宿主机 `./certs/` 目录
2. 在 `.env` 中设置：

   ```env
   HY2_CERT_PATH=/certs/server.crt
   HY2_KEY_PATH=/certs/server.key
   ```

如果指定路径下证书文件不存在或为空，容器仍会回退到自动生成自签证书。

## 关键环境变量

- `HY2_PORT`：宿主机暴露的 UDP 端口
- `HY2_LISTEN`：容器内 Hysteria 监听地址，默认 `:443`
- `HY2_PASSWORD`：Hysteria 认证密码
- `HY2_DOMAIN`：自动生成自签证书时写入的主机名
- `HY2_CERT_PATH` / `HY2_KEY_PATH`：容器内证书路径
- `WARP_MAX_ATTEMPTS`：WARP 轮询次数
- `WARP_RETRY_SECONDS`：WARP 轮询间隔秒数

## 直接使用 GHCR 镜像

默认镜像地址格式：

```text
ghcr.io/lengyuesky/hysteria2-over-warp:latest
```

当前 `docker-compose.yml` 已默认直接使用 GHCR 镜像，不会在本地重新构建。

## GitHub Actions

工作流会在：

- `pull_request` 时执行测试与构建校验
- 推送到 `main` 时发布 `latest`
- 推送 `v*` tag 时发布版本标签
