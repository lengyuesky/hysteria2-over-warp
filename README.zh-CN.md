# warp

## 概述

这个仓库用于构建一个基于 Debian 13.4 slim 的 Cloudflare WARP 容器镜像。容器接入 Docker macvlan 网络后，会在 `eth0` 上主动请求 IPv4 DHCP，移除 Docker 注入到该接口上的 IPv4，并恢复 DHCPv4 地址和默认路由；随后等待 IPv6 自动配置就绪并启动 `warp-svc`。

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

## 部署

1. 在宿主机上创建外部 `warp_macvlan` 网络。
2. 拉取并启动容器：

```bash
docker compose pull
docker compose up -d
```

3. 在容器内检查地址状态，确认网络已经按预期工作：

```bash
docker exec -it warp ip -4 addr show dev eth0
docker exec -it warp sh -lc 'ip route get 10.9.1.3'
docker exec -it warp ip -4 route show
docker exec -it warp ip -6 addr show dev eth0
```

4. 已确认的正常状态应满足：

- `eth0` 只保留 DHCPv4 地址
- `ip route get 10.9.1.3` 选择 DHCPv4 作为 `src`
- 容器内可以访问校园网登录地址
- IPv6 地址仍然存在

5. 首次注册并连接 WARP：

```bash
docker exec -it warp warp-cli register
docker exec -it warp warp-cli connect
docker exec -it warp warp-cli status
```

如果 `eth0` 再次同时出现 Docker 管理的 IPv4 和 DHCPv4 租约，优先修复网络契约。容器不应该在同一接口上长期保留两套相互竞争的 IPv4 来源。
