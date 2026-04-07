# Hysteria2 over Warp Docker 项目设计

**日期：** 2026-04-07  
**主题：** 基于 Debian slim 的 Warp + Hysteria2 单容器项目，使用 GitHub Actions 构建并发布到 GHCR

---

## 1. 目标

构建一个可通过 `docker-compose` 运行的 Docker 项目，满足以下目标：

- 基于 `debian:stable-slim` 构建镜像
- 容器内建立 Warp 网络连接
- 使用 Hysteria 2 协议对外提供连接服务
- 通过 GitHub Actions 自动构建镜像
- 将镜像发布到 GHCR
- 在未提供证书时，容器自动生成自签证书并启动

该项目优先目标是先做出**可运行、可构建、可发布**的最小可用版本，而不是一开始就覆盖所有部署场景。

---

## 2. 范围

### 本次设计范围内

- 初始化 Git 仓库
- 提供 Dockerfile
- 提供容器启动入口脚本
- 提供 Hysteria2 配置模板或生成逻辑
- 提供 `docker-compose.yml`
- 提供 GitHub Actions 工作流
- 支持通过外部挂载证书运行
- 支持未提供证书时自动生成自签证书运行
- 支持 GHCR 镜像发布

### 本次设计范围外

- Kubernetes 部署清单
- 自动申请 ACME/Let's Encrypt 证书
- 复杂的容器内进程管理器（如 systemd、supervisord）
- 完整在线联通性 CI 测试
- 多容器拆分架构

---

## 3. 设计结论

采用**单容器直连版**作为总体方案，但实现风格保持工程化：

- 一个镜像内包含 Warp 运行所需组件与 Hysteria2
- 用一个清晰的 `entrypoint.sh` 串起启动顺序
- 用 `docker-compose.yml` 管理权限、挂载、端口和环境变量
- 用 GitHub Actions 在 GitHub 上构建并发布到 GHCR

这样既能保持项目结构简单，又能避免后续难维护的问题。

---

## 4. 项目结构设计

计划中的仓库结构如下：

```text
.
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── README.md
├── entrypoint.sh
├── config/
│   └── hysteria.yaml.template
├── scripts/
│   └── generate-self-signed-cert.sh
└── .github/
    └── workflows/
        └── docker.yml
```

### 各文件职责

- `Dockerfile`：定义基础镜像、安装依赖、拷贝脚本与默认配置
- `entrypoint.sh`：容器启动总入口，负责检查参数、建立 Warp、准备证书、启动 Hysteria2
- `config/hysteria.yaml.template`：Hysteria2 配置模板，供启动时生成实际配置
- `scripts/generate-self-signed-cert.sh`：生成自签证书
- `docker-compose.yml`：定义运行权限、设备映射、卷挂载、环境变量和端口
- `.github/workflows/docker.yml`：构建并发布镜像到 GHCR
- `README.md`：说明如何构建、配置和运行

---

## 5. 运行架构

### 5.1 基础镜像

基础镜像固定为：

```dockerfile
FROM debian:stable-slim
```

原因：

- 满足用户要求
- Debian slim 足够轻量，同时包管理简单
- 便于安装网络工具、证书工具和 Hysteria2 运行依赖

### 5.2 容器内运行模型

容器内不引入 systemd 或 supervisor，只采用：

- 一个入口脚本 `entrypoint.sh`
- 一个前台主进程 `hysteria server`

Warp 的初始化在入口脚本中完成，Hysteria2 作为最终前台进程运行。这样做的好处是：

- 容器行为可预测
- 退出语义简单
- 更符合容器最佳实践

### 5.3 启动顺序

启动顺序固定如下：

1. 检查环境变量与必要目录
2. 检查是否挂载了外部证书
3. 若没有外部证书，则自动生成自签证书
4. 启动并验证 Warp 网络环境
5. 根据模板渲染 Hysteria2 配置
6. 启动 Hysteria2 前台进程

这个顺序的关键点是：**先准备网络与证书，再启动代理服务**，避免 Hysteria2 在依赖未就绪时启动。

---

## 6. 配置设计

### 6.1 配置来源

配置分为两类：

#### 静态文件

- Hysteria2 配置模板
- 外部挂载证书与私钥（如果有）

#### 环境变量

建议至少支持以下变量：

- `HY2_LISTEN`：Hysteria2 监听地址，例如 `:443`
- `HY2_PASSWORD`：客户端认证密码
- `HY2_CERT_PATH`：证书路径
- `HY2_KEY_PATH`：私钥路径
- `HY2_DOMAIN`：用于生成自签证书时的主机名，默认可回退为 `localhost`
- `HY2_LOG_LEVEL`：日志级别

### 6.2 配置原则

- 镜像内不写死敏感信息
- 参数通过 compose 注入
- 配置模板只保留通用结构
- 运行时统一渲染成最终配置文件

这样可以保证镜像复用性，同时降低修改成本。

---

## 7. 证书策略

证书策略采用统一的两级优先级：

### 第一优先级：使用外部挂载证书

如果 `HY2_CERT_PATH` 与 `HY2_KEY_PATH` 指向的文件存在，则直接使用它们启动 Hysteria2。

### 第二优先级：自动生成自签证书

如果运行时没有提供可用证书，则容器自动生成一套自签证书并继续启动。

### 证书生成策略

- 生成位置为容器内固定目录，例如 `/var/lib/hysteria/certs/`
- 生成后的证书路径回填到统一配置路径
- 生成逻辑由独立脚本负责，避免入口脚本过于臃肿

### 设计原因

这样能满足两个目标：

- 没有预先准备证书时也能直接启动，降低首次部署门槛
- 后续切换到正式证书时，不需要改镜像逻辑，只需挂载证书并改环境变量

---

## 8. Docker Compose 设计

该项目的目标部署方式为 `docker-compose`。

compose 文件需要承担以下职责：

- 提供 `NET_ADMIN` capability
- 挂载 `/dev/net/tun`
- 暴露 Hysteria2 端口
- 注入环境变量
- 挂载可选证书目录
- 设置重启策略

### 推荐运行约束

- 容器使用 `cap_add: [NET_ADMIN]`
- 映射 `devices: ["/dev/net/tun:/dev/net/tun"]`
- 使用 `restart: unless-stopped`

### 设计原因

用户已接受使用 TUN + `NET_ADMIN` 的方式。相比更激进的 privileged 方案，这种方式权限更小、边界更清楚，也更适合 compose 场景。

---

## 9. 数据流与网络流向

系统流量路径设计为：

1. 外部客户端连接 Hysteria2 服务端端口
2. Hysteria2 接收连接并完成认证
3. Hysteria2 产生的出站流量走容器内 Warp 网络路径
4. Warp 将出站流量转发到外部网络

这意味着，项目的核心价值不是单纯“运行一个 Hysteria2 服务端”，而是**让该服务端的上游出站经过 Warp**。

因此，Warp 的可用性是启动前置条件，而不是运行中的可选增强项。

---

## 10. 错误处理策略

为保持行为清晰，本项目采用“失败即退出”的策略。

### 10.1 Warp 初始化失败

- 直接退出容器
- 输出明确错误日志
- 不允许 Hysteria2 在 Warp 未准备好时启动

### 10.2 证书生成失败

- 直接退出容器
- 日志中明确指出证书生成失败

### 10.3 配置不完整或环境变量非法

- 直接退出容器
- 明确指出缺失变量或错误参数

### 10.4 Hysteria2 进程退出

- 容器整体退出
- 交给 Docker/compose 的 `restart` 策略处理重启

### 设计原因

这是最适合 MVP 的运维模型：

- 不在容器内做复杂自愈逻辑
- 不隐藏启动失败
- 让外部编排层处理重启

---

## 11. 可观测性与日志

初版不引入复杂健康探针体系，保持最小化：

- 所有日志输出到 stdout/stderr
- `entrypoint.sh` 输出关键阶段日志
- Hysteria2 运行日志直接打印到容器日志

### 健康策略

MVP 阶段默认以“主进程是否存活”为基础健康判断，不引入额外复杂的 `healthcheck` 逻辑。

原因是：

- Warp 相关联通性检查在不同环境中很难做成稳定、通用的探针
- 初版更应优先保证启动逻辑清晰可诊断

---

## 12. GitHub Actions 设计

CI/CD 采用 GitHub Actions，并发布到 GHCR。

### 12.1 触发策略

建议至少支持：

- `pull_request`：验证 Docker 项目是否可构建
- `push`：在默认分支构建镜像
- `tag`：发布版本镜像

### 12.2 工作流职责

工作流主要完成：

1. 检出代码
2. 登录 GHCR（仅在需要发布时）
3. 构建 Docker 镜像
4. 进行基础校验
5. 推送镜像到 GHCR
6. 生成镜像标签

### 12.3 标签策略

建议支持：

- `latest`
- 分支名标签
- tag 版本标签
- commit sha 短标签（可选）

### 12.4 设计原因

这样可以覆盖常见仓库生命周期：

- PR 提前发现构建错误
- 主分支持续产出可用镜像
- 打 tag 后生成明确版本镜像

---

## 13. 测试与验证策略

### 13.1 本地验证目标

本项目初版优先验证以下事项：

- Dockerfile 可以成功构建
- compose 文件语法与运行参数合理
- 启动脚本可执行
- 未提供证书时能生成自签证书
- Hysteria2 配置能够被正确渲染

### 13.2 不纳入强制 CI 的内容

以下内容不作为初版 GitHub Actions 的必过项：

- Warp 在线联通性测试
- 真实公网环境下的端到端 Hysteria2 连接测试

### 设计原因

这些联通性测试通常依赖外部网络环境，在通用 CI 中不稳定，容易让工作流结果失真。初版应该先把 CI 聚焦在“构建正确”和“启动逻辑正确”。

---

## 14. README 预期内容

README 应至少覆盖：

- 项目简介
- 运行前提（Docker、docker-compose、TUN 支持）
- 如何配置环境变量
- 如何挂载证书
- 未提供证书时会自动生成自签证书
- 如何启动与查看日志
- GHCR 镜像地址格式说明

---

## 15. 后续实施原则

进入实施阶段后，建议坚持以下原则：

- 先做最小可运行版本
- 优先保证启动链路完整
- 不额外加入复杂抽象
- 不过早引入多容器或复杂进程管理
- 将 Warp 初始化、证书生成、配置渲染分别保持为清晰边界

---

## 16. 最终结论

本项目的最终设计结论是：

- 使用 `debian:stable-slim` 作为基础镜像
- 使用单容器承载 Warp 与 Hysteria2
- 使用 `docker-compose` 作为主要部署方式
- 使用 `NET_ADMIN` + `/dev/net/tun` 支持 Warp
- 未提供证书时自动生成自签证书
- 使用 GitHub Actions 构建并发布镜像到 GHCR
- 保持容器模型简单，失败即退出，交由 compose 负责重启

该设计可以在保持实现复杂度可控的前提下，满足你当前的核心需求。