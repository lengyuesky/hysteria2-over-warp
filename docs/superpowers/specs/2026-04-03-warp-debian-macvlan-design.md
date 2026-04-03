# Debian 13.4 Slim + Cloudflare WARP + macvlan 设计

## 目标
构建一个基于 `debian:13.4-slim` 的容器镜像，安装 Cloudflare WARP，并通过 Docker `macvlan` 网络让容器像局域网中的独立主机一样自行请求 IPv4 DHCP 和 IPv6 DHCPv6 地址；不在 Compose 中指定固定 IP。首次启动后由用户手动执行 `warp-cli register` 与 `warp-cli connect`。

## 范围
本设计交付以下内容：
- `Dockerfile`
- 容器启动脚本（entrypoint）
- `docker-compose.yml`
- GitHub Actions 工作流：自动构建并发布镜像到 GHCR
- 使用说明：如何在宿主机创建外部 `macvlan` 网络并启动容器

不包含以下内容：
- systemd 容器化
- Zero Trust/Teams 自动注册
- 固定 IPv4/IPv6 地址分配
- 宿主机网络自动配置脚本
- 非 GHCR 的镜像发布流程

## 约束与前提
- 基础镜像固定为 `debian:13.4-slim`
- 网络模式固定为 Docker `macvlan`
- 容器内必须自行发起 DHCPv4 和 DHCPv6 请求，不由 Compose 静态分配地址
- WARP 仅做安装和服务启动；首次注册与连接由用户手动完成
- 宿主机、交换网络和上游路由器必须真实支持：
  - macvlan 所在二层网络
  - IPv4 DHCP
  - IPv6 DHCPv6
- 若上游网络仅提供 RA/SLAAC 而不提供 DHCPv6，则容器无法满足“必须 DHCPv6”这一要求

## 架构概览
采用“轻量前台容器 + 自定义 entrypoint”方案，而不是 systemd：

1. 镜像构建阶段安装：
   - Cloudflare WARP 软件包
   - `dbus`
   - `isc-dhcp-client`
   - IPv6 与证书相关基础包
2. 运行阶段由 entrypoint 顺序执行：
   - 启动 `dbus-daemon`
   - 等待网卡 `eth0` 可用
   - 对 `eth0` 执行 `dhclient -4`
   - 对 `eth0` 执行 `dhclient -6`
   - 启动 `warp-svc`
   - 保持主进程前台运行
3. `docker-compose.yml` 只负责：
   - 赋予必要能力（如 `NET_ADMIN`）
   - 挂载 `/dev/net/tun`
   - 接入外部 `macvlan` 网络
   - 不设置静态 IP

## 组件设计

### 0. GitHub Actions 工作流
职责：在 GitHub 仓库中自动构建并发布容器镜像，供 `docker-compose.yml` 直接引用。

关键行为：
- 触发条件为 `main` 分支上的 push
- 使用 GitHub Actions 构建镜像并推送到 GHCR
- 至少发布两个 tag：
  - `latest`
  - `sha-<shortsha>`
- Compose 默认引用：`ghcr.io/<github-owner>/<repo>:latest`

设计取舍：
- 采用 GHCR，因为用户已明确指定 GHCR，且与 GitHub Actions 权限集成最直接
- Compose 不再使用本地 `build:`，而是显式使用已发布镜像，保持部署方式与 CI 产物一致


### 1. Dockerfile
职责：构建可运行镜像。

关键内容：
- 使用 `debian:13.4-slim`
- 配置 Cloudflare 官方 APT 源并安装 `cloudflare-warp`
- 安装 `dbus`、`isc-dhcp-client`、`iproute2`、`iputils-ping`、`ca-certificates`
- 复制 entrypoint 脚本
- 设置默认启动命令

### 2. entrypoint 脚本
职责：在没有 systemd 的情况下，完成最小“系统启动流程”。

启动顺序：
1. 启动 D-Bus
2. 确认 `eth0` 存在
3. 清理可能遗留的 DHCP pid/lease 状态
4. 执行 `dhclient -4 eth0`
5. 执行 `dhclient -6 eth0`
6. 启动 `warp-svc`
7. 输出状态并阻塞前台，避免容器退出

设计取舍：
- 不做复杂重试编排，保持最小可理解实现
- 若 DHCPv6 获取失败，容器应直接报错退出，而不是静默降级为 SLAAC；因为用户明确要求必须 DHCPv6
- 首次 WARP 注册不自动化，避免把设备身份状态写死在镜像或启动脚本里

### 3. docker-compose.yml
职责：定义容器运行参数。

关键配置：
- 使用 `image: ghcr.io/<github-owner>/<repo>:latest`
- 不使用本地 `build:`
- `cap_add: [NET_ADMIN]`
- `devices: ["/dev/net/tun:/dev/net/tun"]`
- 接入 `external` 的 `macvlan` 网络
- `stdin_open` / `tty` 可选，便于首次进入容器执行 `warp-cli`
- 不写 `ipv4_address` / `ipv6_address`

说明：
- Compose 本身不会让容器“自动 DHCP”；真正的 DHCP 动作由容器内 `dhclient` 完成
- 外部 `macvlan` 网络需要用户先在宿主机创建
- Compose 使用 CI 已发布镜像，避免本地构建结果与部署镜像不一致

## 数据流 / 启动流
1. 开发者将代码 push 到 `main`
2. GitHub Actions 构建镜像并推送到 `ghcr.io/<github-owner>/<repo>`
3. 宿主机先创建外部 `macvlan` 网络
4. Compose 拉取 `:latest` 镜像并启动容器，把网卡接入该网络
5. entrypoint 在容器内对 `eth0` 发送 DHCPv4/DHCPv6 请求
6. 上游 DHCP / DHCPv6 服务器为该 MAC 分配地址
7. `warp-svc` 启动
8. 用户进入容器执行：
   - `warp-cli register`
   - `warp-cli connect`

## 失败处理
- `eth0` 不存在：启动失败并退出
- `dhclient -4` 失败：启动失败并退出
- `dhclient -6` 失败：启动失败并退出
- `warp-svc` 启动失败：启动失败并退出
- `/dev/net/tun` 不可用：WARP 后续连接会失败，应在启动日志中暴露问题

这样设计的原因是：本项目目标明确，失败应尽早暴露，而不是引入复杂兜底逻辑掩盖网络前提不满足的问题。

## 测试与验证
至少验证以下内容：
1. GitHub Actions 在 `main` push 后成功构建并推送 GHCR 镜像
2. GHCR 中存在 `latest` 与 `sha-<shortsha>` tag
3. Compose 可成功拉取 `ghcr.io/<github-owner>/<repo>:latest`
4. 容器启动后 `ip -4 addr show dev eth0` 能看到 DHCPv4 地址
5. 容器启动后 `ip -6 addr show dev eth0` 能看到通过 DHCPv6 获取到的地址
6. `warp-svc` 进程存在
7. 手动执行 `warp-cli register` 成功
8. 手动执行 `warp-cli connect` 成功
9. `warp-cli status` 返回已连接状态

## 已确认决策
- 交付形式：`Dockerfile + docker-compose.yml + GitHub Actions 工作流`
- 容器形态：普通前台容器，不使用 systemd
- WARP 接入方式：个人 WARP，首次手动注册与连接
- IPv6 要求：必须 DHCPv6，不接受仅 RA/SLAAC
- 镜像仓库：GHCR
- 发布规则：push 到 `main` 时推送 `latest` 和 `sha-<shortsha>`
- Compose 镜像引用：`ghcr.io/<github-owner>/<repo>:latest`

## 风险
1. Docker 官方文档更偏向为 macvlan 网络配置明确子网，而不是在容器中自行 DHCP；本方案属于“可实现但依赖环境”的自定义做法。
2. 某些网络环境对每个 macvlan MAC 的 DHCPv6 分配有限制，可能导致 `dhclient -6` 无法成功。
3. macvlan 容器默认无法直接与宿主机通信，这不是 WARP 问题，而是 macvlan 特性。

## 推荐实现结论
继续按本设计实施：
- 使用轻量 entrypoint 而非 systemd
- 由容器内 `dhclient` 明确申请 IPv4 DHCP 和 IPv6 DHCPv6
- 由 Compose 只负责权限和接网，不负责静态地址
- WARP 保持手动首次注册
