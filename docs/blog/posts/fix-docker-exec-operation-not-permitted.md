---
authors:
  - ionling
categories:
  - Backend
  - Container
  - DevOps
date: 2023-11-30
---

# Fix `docker exec` operation not permitted

## Issue

服务器执行 `docker exec` 失败

```
# docker exec -it user-ab107i9 sh
OCI runtime exec failed: exec failed: unable to start container process: open /dev/pts/0: operation not permitted: unknown
```

搜索一下发现 Issue:

https://github.com/moby/moby/issues/43969

Issue 中提到这个问题在 `runc v1.1.4` 中已经修复.
检查一下 `runc` 版本, 为 `1.1.3`, ok, 确认为 `runc` 的问题.
想着要升级 docker 版本会造成服务停止问题, 就没处理.

直到今天 [2023-11-30 Thu] 又想起这个问题,
搜了一下, 发现阿里云的文章提到可以避免业务中断的方法[^aliyun], 尝试了一下, 没有问题.

## Solution

```sh
## Download runc binary
# https://github.com/opencontainers/runc/releases
wget https://github.com/opencontainers/runc/releases/download/v1.1.10/runc.amd64
wget https://github.com/opencontainers/runc/releases/download/v1.1.10/runc.amd64.asc
wget https://raw.githubusercontent.com/opencontainers/runc/main/runc.keyring

## Verify runc binary
gpg --import runc.keyring
gpg --verify runc.amd64.asc runc.amd64

## Replace runc
docker info | grep runc         # Show old version info
sudo mv /usr/bin/runc /usr/bin/runc_old
sudo cp runc.amd64 /usr/bin/runc
sudo chmod +x /usr/bin/runc
docker info | grep runc         # Show new version info
```

这样就替换完成了, 对于有问题的容器直接重启就可以了.

## About runc

[runc] 是最底层的容器运行时.

以最新版的 `Docker` 为例, 当我们执行运行容器时, `Docker` 会调用 [containerd],
`containerd` 再调用 `runc`, 最后通过 `runc` 来运行容器.

而 `containerd` 主要负责以下事情[^qikqiak]:

1. 管理容器的生命周期（从创建容器到销毁容器）
2. 拉取/推送容器镜像
3. 存储管理（管理镜像及容器数据的存储）
4. 调用 runc 运行容器（与 runc 等容器运行时交互）
5. 管理容器网络接口及网络

架构:

![containerd](https://github.com/adobaai/adobaai.github.io/assets/20399569/a63c250c-127a-4134-8c89-1dd7b2fd8711)

[containerd]: https://containerd.io/
[runc]: https://github.com/opencontainers/runc

[^aliyun]: https://help.aliyun.com/zh/ack/product-overview/announcement-about-fixing-the-runc-vulnerability-cve-2019-5736
[^qikqiak]: https://www.qikqiak.com/post/containerd-usage/
