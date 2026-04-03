# Debian 13.4 Slim + Cloudflare WARP + macvlan 设计

## 目标
构建一个基于 `debian:13.4-slim` 的容器镜像，安装 Cloudflare WARP，并通过 Docker `macvlan` 网络让容器像局域网中的独立主机一样自行请求 IPv4 DHCP，并自动获得 IPv6 地址；不在 Compose 中指定固定 IP。首次启动后由用户手动执行 `warp-cli register` 与 `warp-cli connect`。

## 范围
本设计交付以下内容：
- `Dockerfile`
- 容器启动脚本（entrypoint）
- `docker-compose.yml`
  - 通过 `external` 网络引用宿主机已创建的 `macvlan`
- GitHub Actions 工作流：自动构建并发布镜像到 GHCR
- 使用说明：如何先在宿主机创建外部 `macvlan` 网络，再启动容器

不包含以下内容：
- systemd 容器化
- Zero Trust/Teams 自动注册
- 固定 IPv4/IPv6 地址分配
- 宿主机网络自动配置脚本
- 非 GHCR 的镜像发布流程

## 约束与前提
- 基础镜像固定为 `debian:13.4-slim`
- 网络模式固定为 Docker `macvlan`
- 容器内必须自行发起 IPv4 DHCP 请求，不由 Compose 静态分配容器 IPv4 地址
- IPv6 地址由上游网络自动配置提供，可来自 DHCPv6 或 RA/SLAAC
- Compose 只负责引用外部 `macvlan` 网络，不在仓库内直接定义 `parent`、IPv4 `subnet/gateway` 或 `enable_ipv6`
- 宿主机侧必须预先创建好供 compose 引用的外部 `warp_macvlan` 网络
- WARP 仅做安装和服务启动；首次注册与连接由用户手动完成
- 宿主机、交换网络和上游路由器必须真实支持：
  - macvlan 所在二层网络
  - IPv4 DHCP
  - 自动 IPv6 配置传播到容器所在网段

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
   - 清理 DHCP 状态
   - 对 `eth0` 执行 `dhclient -4`
   - 等待 IPv6 自动配置就绪（至少出现链路本地地址）
   - 启动 `warp-svc`
   - 保持主进程前台运行
3. `docker-compose.yml` 负责：
   - 赋予必要能力（如 `NET_ADMIN`）
   - 挂载 `/dev/net/tun`
   - 接入外部 `macvlan` 网络
   - 不设置静态容器 IP

## 组件设计

### 0. GitHub Actions 工作流
职责：在 GitHub 仓库中自动构建并发布容器镜像，供 `docker-compose.yml` 直接引用。

关键行为：
- 触发条件为 `main` 分支上的 push
- 使用 GitHub Actions 构建镜像并推送到 GHCR
- 至少发布两个 tag：
  - `latest`
  - `sha-<shortsha>`
- Compose 默认引用：`ghcr.io/lengyuesky/hysteria2-over-warp:latest`

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
5. 等待 IPv6 自动配置就绪（至少出现链路本地地址）
6. 启动 `warp-svc`
7. 输出状态并阻塞前台，避免容器退出

设计取舍：
- 不做复杂重试编排，保持最小可理解实现
- IPv6 由上游网络自动配置提供，不把 DHCPv6 成功作为容器启动前提
- 首次 WARP 注册不自动化，避免把设备身份状态写死在镜像或启动脚本里

### 3. docker-compose.yml
职责：定义容器运行参数，并把服务接入宿主机预先创建的外部 `macvlan` 网络。

关键配置：
- 使用 `image: ghcr.io/lengyuesky/hysteria2-over-warp:latest`
- 不使用本地 `build:`
- `cap_add: [NET_ADMIN]`
- `devices: ["/dev/net/tun:/dev/net/tun"]`
- 引用 `external` 的 `warp_macvlan` 网络
- `stdin_open` / `tty` 可选，便于首次进入容器执行 `warp-cli`
- 不写 `ipv4_address` / `ipv6_address`

说明：
- Compose 本身不会让容器“自动 DHCP”；真正的 IPv4 DHCP 动作由容器内 `dhclient` 完成
- `warp_macvlan` 网络应由宿主机提前创建，负责把容器接入目标二层网络
- 仓库内 compose 不再声明 `driver`、`parent`、`enable_ipv6` 或 `ipam` 参数，避免同时保留 Docker 管理的 IPv4 与容器内 DHCPv4
- README 中保留宿主机侧 `docker network create` 命令，便于部署或排障
- Compose 使用 CI 已发布镜像，避免本地构建结果与部署镜像不一致

## 数据流 / 启动流
1. 开发者将代码 push 到 `main`
2. GitHub Actions 构建镜像并推送到 `ghcr.io/lengyuesky/hysteria2-over-warp`
3. 用户先在宿主机创建外部 `warp_macvlan` 网络
4. Compose 拉取 `:latest` 镜像并把容器网卡接入该外部网络
5. entrypoint 在容器内对 `eth0` 发送 DHCPv4 请求，并等待 IPv6 自动配置就绪
6. 上游 DHCP 服务器为该 MAC 分配 IPv4 地址，上游网络自动向该网段传播 IPv6 配置
7. `warp-svc` 启动
8. 用户进入容器执行：
   - `warp-cli register`
   - `warp-cli connect`

若 Compose 同时内联 macvlan IPv4 IPAM，而容器内又执行 `dhclient -4`，同一接口会出现双 IPv4。到校园网登录地址等 IPv4 目标时，内核可能默认选中 Docker IPAM 地址作为 `src`，从而导致访问异常。

## 失败处理
- `eth0` 不存在：启动失败并退出
- `dhclient -4` 失败：启动失败并退出
- IPv6 自动配置在启动阶段未就绪：启动失败并退出
- `warp-svc` 启动失败：启动失败并退出
- `/dev/net/tun` 不可用：WARP 后续连接会失败，应在启动日志中暴露问题
- 若 `eth0` 同时出现 Docker 管理的 IPv4 和 DHCPv4：视为部署契约错误，应回退到“外部 macvlan + 容器内 DHCPv4”的单一来源模型，而不是在运行时通过脚本修路由或删地址

这样设计的原因是：本项目目标明确，失败应尽早暴露，而不是引入复杂兜底逻辑掩盖网络前提不满足的问题。

## 测试与验证
至少验证以下内容：
1. GitHub Actions 在 `main` push 后成功构建并推送 GHCR 镜像
2. GHCR 中存在 `latest` 与 `sha-<shortsha>` tag
3. `docker-compose.yml` 以 `external: true` / `name: warp_macvlan` 成功通过 `docker compose config` 渲染
4. Compose 可成功拉取 `ghcr.io/lengyuesky/hysteria2-over-warp:latest`
5. 容器启动后 `ip -4 addr show dev eth0` 能看到 DHCPv4 地址，且不再并存 Docker IPAM 主地址
6. `ip route get 10.9.1.3` 的 `src` 指向 DHCPv4 地址
7. 容器启动后 `ip -6 addr show dev eth0` 能看到自动获得的 IPv6 地址
8. `warp-svc` 进程存在
9. 手动执行 `warp-cli register` 成功
10. 手动执行 `warp-cli connect` 成功
11. `warp-cli status` 返回已连接状态

## 已确认决策
- 交付形式：`Dockerfile + docker-compose.yml + GitHub Actions 工作流`
- 容器形态：普通前台容器，不使用 systemd
- WARP 接入方式：个人 WARP，首次手动注册与连接
- IPv6 要求：自动获得 IPv6，接受 DHCPv6 或 RA/SLAAC
- 镜像仓库：GHCR
- 发布规则：push 到 `main` 时推送 `latest` 和 `sha-<shortsha>`
- Compose 镜像引用：`ghcr.io/lengyuesky/hysteria2-over-warp:latest`
- macvlan 参数写法：compose 仅引用外部 `warp_macvlan`，宿主机侧网络参数通过 `docker network create` 或等价方式预先准备

## 风险
1. Docker 官方文档更偏向为 macvlan 网络配置明确子网，而不是在容器中自行 DHCP；本方案属于“可实现但依赖环境”的自定义做法。
2. 某些网络环境若不向 macvlan 容器传播 RA/SLAAC 或 DHCPv6，容器可能无法自动获得 IPv6。
3. macvlan 容器默认无法直接与宿主机通信，这不是 WARP 问题，而是 macvlan 特性。
4. 若部署时再次把 compose 改回内联 `macvlan` + IPv4 IPAM，同时保留容器内 `dhclient -4`，会重新制造双 IPv4，并让校园网登录链路选错源地址。

## 推荐实现结论
继续按本设计实施：
- 使用轻量 entrypoint 而非 systemd
- 由容器内 `dhclient` 明确申请 IPv4 DHCP
- 由上游网络向容器自动提供 IPv6 配置
- 由 Compose 只负责权限和接网，不负责静态地址
- WARP 保持手动首次注册
