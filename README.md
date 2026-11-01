# OpenVPN 服务端与账号管理

本目录包含 OpenVPN 安装脚本。脚本会同时安装仓库里的 `psw-admin` 管理程序：网页可新增、删除、停用用户、设置到期时间并查看在线状态。用户密码保存在 `/etc/openvpn/psw-file`，停用和到期信息保存在旁边的元数据文件中。

## 安装前构建管理程序

在仓库根目录执行以下命令（需在目标 Linux 服务器构建，或交叉编译为目标架构）：

```sh
npm ci
npm run build
go build -o psw-admin .
sudo PSW_ADMIN_BIN="$PWD/psw-admin" bash ./OpenVPN-Server/openvpn-install.sh
```

安装脚本会将程序安装到 `/usr/local/bin/psw-admin`，配置 OpenVPN 使用 `via-file` 认证，并写入 `/etc/openvpn/server/openvpn-status.log` 在线状态。脚本创建 systemd 服务 `psw-admin.service`，管理页面默认监听 `0.0.0.0:8088`。首次安装会在终端显示随机管理员密码，请立即保存。

首次安装时脚本会让你输入网段编号 `x`。例如输入 `22` 就使用 `172.16.22.0/24`，服务器隧道地址为 `172.16.22.1`；直接回车默认使用 `172.16.8.0/24`。

安装完成后会生成 `/etc/openvpn/iptables`，其中网段和本机 IP 会使用安装时选择的值；服务器在 NAT 后时，脚本里写入的是服务器本机网卡 IP。需要重新应用规则时运行 `sudo /etc/openvpn/iptables`。该脚本保留 `iptables -F -t nat` 命令，会清空 NAT 表现有规则。

已有 OpenVPN 服务器再次运行脚本时，选择 **4) Install or update psw-admin**。升级管理程序时先重新构建，再运行脚本并选择该项。

## 访问管理页面

浏览器打开 `http://服务器地址:8088`，使用首次安装时输出的管理员密码登录。默认监听所有网卡，请通过防火墙限制来源，或放在 HTTPS 反向代理后再开放远程访问。

独立安装管理程序可在仓库根目录构建 `OpenVPN-Server/openvpn-admin` 后运行 `sudo ./OpenVPN-Server/install-openvpn-admin.sh`。安装脚本默认设置 `CLIENT_FILE=/root/client.ovpn`；把客户端 `.ovpn` 文件放到该路径后，登录页面点击“下载客户端配置”即可下载。自定义路径可通过 `sudo env CLIENT_FILE=/path/to/client.ovpn ./OpenVPN-Server/install-openvpn-admin.sh` 指定。

批量增加、批量禁用和批量删除位于用户列表操作区。批量新增支持逗号或换行分隔，成功后会将账号密码复制到剪贴板。新增用户默认生成 16 位随机密码并设置 60 天后到期。

## 注意事项

- OpenVPN 用户名密码认证仍叠加在客户端证书校验之上；客户端配置需要 `auth-user-pass`。
- 到期会在用户下一次连接认证时生效，不会自动断开已在线连接。
- 删除或停用账号会阻止后续认证，不会撤销对应客户端证书。
- 移除 OpenVPN 时脚本会停止并移除管理服务及程序，但保留 `/etc/openvpn/psw-file` 和 `/etc/default/psw-admin`，避免删除账号与管理员配置数据。
