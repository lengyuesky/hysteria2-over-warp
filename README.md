# hysteria2-over-warp

基于 `debian:stable-slim` 的单容器项目：容器先建立 Cloudflare WARP 连接，再启动 Hysteria 2 服务端，并使用 GitHub Actions 发布镜像到 GHCR。

## 前置条件

- Docker
- Docker Compose v2
- 宿主机可用的 `/dev/net/tun`
- 允许容器使用 `NET_ADMIN`

## 本地运行

```bash
cp .env.example .env
docker compose up --build -d
```

查看日志：

```bash
docker compose logs -f
```

停止服务：

```bash
docker compose down
```

## 证书策略

默认情况下，容器会在未提供证书时自动生成自签证书并写入 `/var/lib/hysteria/certs/`。

如果要使用外部证书：

1. 把证书文件放到宿主机 `./certs/` 目录
2. 在 `.env` 中设置：

```env
HY2_CERT_PATH=/certs/server.crt
HY2_KEY_PATH=/certs/server.key
```

## 关键环境变量

- `HY2_PORT`：宿主机暴露的 UDP 端口
- `HY2_LISTEN`：容器内 Hysteria 监听地址，默认 `:443`
- `HY2_PASSWORD`：Hysteria 认证密码
- `HY2_DOMAIN`：自动生成自签证书时写入的主机名
- `WARP_MAX_ATTEMPTS`：WARP 轮询次数
- `WARP_RETRY_SECONDS`：WARP 轮询间隔秒数

## GHCR 镜像

工作流会在：

- `pull_request` 时验证项目能否通过测试与构建
- 推送到 `main` 时发布 `latest`
- 推送 `v*` tag 时发布版本标签

默认镜像地址格式：

```text
ghcr.io/<owner>/<repo>:<tag>
```
