# warp

## 概述

这个仓库用于构建一个基于 Debian 13.4 slim 的 Cloudflare WARP + Hysteria 2 容器镜像。容器接入 Docker macvlan 网络后，会在 `eth0` 上主动请求 IPv4 DHCP，移除 Docker 注入到该接口上的 IPv4，并恢复 DHCPv4 地址和默认路由；在 DHCP 就绪后执行用户提供的校园网登录脚本，随后等待 30 秒，在已经完成注册的前提下自动连接 WARP，最后启动 Hysteria 2 服务。

默认行为如下：

- Hysteria 2 密码从 `HY2_PASSWORD` 读取
- 未挂载证书时自动生成自签证书
- 默认 SNI 相关主机名为 `bing.com`
- 即使 WARP 尚未注册，Hysteria 2 也会继续启动，但此时分享出去的出口未必已经是 WARP

## 构建与发布

推送到 `main` 后，镜像会发布到 GHCR：

- `ghcr.io/lengyuesky/hysteria2-over-warp:latest`
- `ghcr.io/lengyuesky/hysteria2-over-warp:sha-<shortsha>`

## 宿主机网络前提

你的局域网在 macvlan 所连接的二层网段上必须提供以下能力：

- IPv4 DHCP
- 容器所在网段的自动 IPv6 配置能力（DHCPv6 或 RA/SLAAC）
- 允许容器使用独立 MAC 地址进行二层通信

在执行 `docker compose up` 之前，先在宿主机上创建一个外部 `warp_macvlan` 网络。Compose 只负责把容器接入这个网络；容器侧 IPv4 必须来自 `dhclient -4`，而不是 Docker IPAM。这个外部网络还必须保留 IPv6 支持，因为当前入口脚本仍会等待 IPv6 链路本地地址和 IPv6 默认路由，然后再发起可选的 DHCPv6 请求。

外部 macvlan 网络创建示例：

```bash
docker network create -d macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  -o parent=eth0 \
  warp_macvlan
```

不要让 `eth0` 同时长期保留 Docker 管理的 IPv4 和 DHCPv4 租约。双 IPv4 状态会让 `10.9.1.3` 这类路由选择错误的源地址。当前入口脚本会在 DHCP 成功后显式移除 Docker 注入的 IPv4，并恢复 DHCPv4 地址和默认路由，使 `eth0` 最终只保留 DHCP 租约。

## Compose 配置

当前 compose 约定以下本地路径和变量：

- `./config/scripts/campus-login.sh`：可选的校园网登录脚本
- `./config/hysteria/`：可选的 Hysteria 自定义配置和证书目录
- `.env`：用户可编辑的运行参数文件
- `.env` 里的 `HY2_PASSWORD`：必填的 Hysteria 2 认证密码

如果 `./config/hysteria/config.yaml` 存在，容器会直接使用它；否则自动生成默认的 Hysteria 服务端配置。如果 `server.crt` 和 `server.key` 不存在，容器会自动生成自签证书。

启动前先从示例文件生成 `.env`：

```bash
cp .env.example .env
```

## 部署

1. 在宿主机上创建外部 `warp_macvlan` 网络。
2. 准备 Hysteria 目录和 `.env`：

```bash
mkdir -p config/scripts config/hysteria
cp .env.example .env
```

3. 如果你需要校园网认证，把可执行脚本放到 `config/scripts/campus-login.sh`，然后再在 `docker-compose.yml` 里设置 `CAMPUS_LOGIN_SCRIPT=/config/scripts/campus-login.sh`。
4. 编辑 `.env`，把 `HY2_PASSWORD` 改成真实强密码。
5. 拉取并启动容器：

```bash
docker compose pull
docker compose up -d
```

## 运行流程

容器启动顺序如下：

1. 通过 DHCP 获取 `eth0` 的 IPv4
2. 删除 Docker 注入的 IPv4，并恢复 DHCP 默认路由
3. 执行校园网登录脚本
4. 等待 IPv6 就绪
5. 启动 `warp-svc`
6. 等待 30 秒；若已注册则自动连接 WARP
7. 启动 Hysteria 2

校园网登录脚本是可选的。只有在你配置了 `CAMPUS_LOGIN_SCRIPT` 之后，它才会变成强前置条件：如果脚本不存在、不可执行或返回非零退出码，容器会直接失败退出。

## 首次 WARP 注册

容器不会自动执行首次注册。第一次启动后请手动执行一次：

```bash
docker exec -it warp warp-cli --accept-tos registration new
docker exec -it warp warp-cli --accept-tos connect
docker exec -it warp warp-cli --accept-tos status
```

完成首次注册后，后续容器重启都会等待 30 秒并尝试自动连接 WARP。

## 验证

在容器内检查地址和服务状态：

```bash
docker exec -it warp ip -4 addr show dev eth0
docker exec -it warp sh -lc 'ip route get 10.9.1.3'
docker exec -it warp ip -6 addr show dev eth0
docker exec -it warp warp-cli --accept-tos status
docker exec -it warp sh -lc 'ss -lunp | grep 8443 || true'
```

已确认的正常状态应满足：

- `eth0` 只保留 DHCPv4 地址
- `ip route get 10.9.1.3` 选择 DHCPv4 作为 `src`
- IPv6 地址仍然存在
- 校园网登录脚本已经执行
- 如果之前已经注册过 WARP，30 秒后会自动连接
- Hysteria 2 在 UDP `8443` 上监听

在 macvlan 部署下，客户端通常应直接连接容器自身通过 DHCP 获取的局域网 IP 的 UDP `8443`。`ports` 映射只是兼容性兜底，不应视为主访问路径。

## 说明

- 如果 WARP 还没有注册，Hysteria 2 仍会启动，但分享出去的出口未必已经是 WARP。
- 如果 `eth0` 再次同时出现 Docker 管理的 IPv4 和 DHCPv4 租约，优先修复网络契约。容器不应该在同一接口上长期保留两套相互竞争的 IPv4 来源。
- 如果你不希望容器重建后自签证书变化，请持久化 `./config/hysteria/` 目录。
