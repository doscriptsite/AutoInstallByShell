# AutoInstallByShell
一些Linux软件自动安装脚本, 交互式安装 Python, Nginx, PostgreSQL, Redis, Nodejs 等.....

## 脚本说明

#### 部分脚本的部分代码借鉴[OneinStack](https://github.com/oneinstack/oneinstack)
> 安装中使用的源码包均来自软件官网或GitHub，所以可能需要科学网络环境。但也可提前下载并放在脚本同目录下。

> 大部分脚本使用变量来指定软件包的安装版本，可自行修改

* [install_python_centos.sh](./install_python_centos.sh) - CentOS 7+ 下自动安装Python的Shell脚本，支持指定版本和自动添加国内pypi源
* [install_python_debian.sh](./install_python_debian.sh) - Debian 8+ 或 Ubuntu 16+ 下自动安装Python的Shell脚本，支持指定版本和自动添加国内pypi源
* [install_nginx_debian.sh](./install_nginx_debian.sh) - Debian 8+ 或 Ubuntu 16+ 下自动安装Nginx的Shell脚本，支持安装Brotli压缩模块（安装Brotli需要git环境，脚本会自动安装git）

&nbsp;
&nbsp;
### ‼注意！！！在使用这些脚本前，请检查代码是否适合您的环境。造成的任何错误后果与本人无关😂
