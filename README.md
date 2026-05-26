# tidbx-ha-toolkit

平凯 V7.1.9 两节点敏捷模式一键部署与高可用测试工具。

## 功能特性

- **一键安装** Docker + Docker Compose 基础环境（支持 CentOS/Ubuntu）
- **一键部署** 两节点敏捷模式 TiDB 集群（含脚本仲裁）
- **一键配置** Keepalived + VIP 高可用
- **自动化 HA 测试**：节点重启、网络延迟、数据损坏、业务模拟

## 快速开始

### 1. 准备配置文件

```bash
cd tidbx-ha-toolkit
cp config/node1.env.example config/node1.env
cp config/node2.env.example config/node2.env
```

编辑 `config/node1.env`（Master 节点）和 `config/node2.env`（Backup 节点），填入实际 IP 和网络信息。

### 2. 在两个节点分别部署

**离线安装模式（推荐）:**

将离线安装包放到 `offline/` 目录：
```
offline/
├── docker/           # Docker 离线包 (.rpm/.deb/.tgz)
├── docker-compose/   # Docker Compose 二进制文件
└── tidbx-719.tar     # 平凯镜像文件
```

```bash
# 在 Node 1 执行（离线模式）
sudo bash deploy/deploy-cluster.sh --env config/node1.env --offline-dir ./offline/docker

# 在 Node 2 执行（离线模式）
sudo bash deploy/deploy-cluster.sh --env config/node2.env --offline-dir ./offline/docker
```

**在线安装模式:**

```bash
# 在 Node 1 执行
sudo bash deploy/deploy-cluster.sh --env config/node1.env

# 在 Node 2 执行
sudo bash deploy/deploy-cluster.sh --env config/node2.env
```

### 3. 验证集群

```bash
bash deploy/verify.sh --env config/node1.env
```

### 4. 运行 HA 测试

```bash
cd /root/tidbx-ha-toolkit
sudo bash ha-test/run-all.sh --env config/node1.env
```

## 项目结构

```
tidbx-ha-toolkit/
├── setup/                    # 环境安装
│   ├── install-docker.sh     # 安装 Docker CE
│   └── install-compose.sh    # 安装 Docker Compose
├── deploy/                   # 集群部署
│   ├── deploy-cluster.sh     # 一键部署入口
│   ├── deploy-keepalived.sh  # Keepalived 配置
│   ├── init-data.sh          # 数据目录初始化
│   ├── load-image.sh         # Docker 镜像加载
│   ├── verify.sh             # 集群状态验证
│   └── cleanup.sh            # 清理集群
├── ha-test/                  # 高可用测试
│   ├── run-all.sh            # 一键全量测试
│   ├── test-node-restart.sh  # 节点重启测试
│   ├── test-network-delay.sh # 网络延迟测试
│   ├── test-data-corrupt.sh  # 数据损坏测试
│   ├── test-business.sh      # 业务模拟
│   └── lib/common.sh         # 测试框架函数库
├── config/                   # 配置模板
│   ├── node1.env.example     # Node1 配置
│   ├── node2.env.example     # Node2 配置
│   ├── template/             # PD/TiKV/TiDB/Keepalived 配置
│   └── docker-compose/       # Docker Compose 文件
└── docs/                     # 文档
```

## 配置参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `NODE_ROLE` | 节点角色 (master/backup) | master |
| `NODE_IP` | 本机 IP | - |
| `PEER_IP` | 对端 IP | - |
| `NIC` | 网卡名称 | ens33 |
| `VIP` | 虚拟 IP | - |
| `VIP_PREFIX` | VIP 子网前缀 | 24 |
| `KEEPALIVED_PRIORITY` | Keepalived 优先级 | 100/99 |
| `PD_CLI_PORT` | PD 客户端端口 | 2379 |
| `PD_PEER_PORT` | PD 对等端口 | 2380 |
| `TIKV_PORT` | TiKV 端口 | 20160 |
| `TIDB_PORT` | TiDB MySQL 端口 | 4000 |
| `TIDBX_IMAGE` | Docker 镜像 | tidbx:v7.1.9-0.0 |

## HA 测试场景

### 节点重启测试
- Master 关机 → VIP 漂移到 Backup → 复制降级 ASYNC
- Master 恢复 → VIP 漂回 → 复制恢复 SYNC
- Backup 关机 → 复制降级 ASYNC
- Backup 恢复 → 复制恢复 SYNC

### 网络延迟测试
- 1s 延迟 → 复制保持 SYNC
- 10s 延迟 → 复制降级 ASYNC
- 延迟清除 → 复制恢复 SYNC

### 数据损坏测试
- 删除 Backup TiKV 数据 → 验证集群降级

### 业务模拟
- 持续通过 VIP 写入 SQL
- 统计 QPS、延迟、错误率、中断时长

## 清理

```bash
# 停止集群（保留数据）
sudo bash deploy/cleanup.sh --env config/node1.env

# 停止集群（删除数据）
sudo bash deploy/cleanup.sh --env config/node1.env --remove-data
```

## 前置条件

- 两台 Linux 服务器（CentOS 7+ / Ubuntu 18.04+）
- 至少 4GB 内存、2 CPU
- 服务器间网络互通
- Root 权限
- 平凯 tidbx Docker 镜像文件 (`tidbx-719.tar`)

## License

Apache 2.0
