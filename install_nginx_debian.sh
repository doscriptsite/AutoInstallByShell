#!/bin/bash
# Check if user is root
[ $(id -u) != "0" ] && {
  echo "${CFAILURE}Error: You must be root to run this script${CEND}"
  exit 1
}

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

echo=echo
for cmd in echo /bin/echo; do
  $cmd >/dev/null 2>&1 || continue
  if ! $cmd -e "" | grep -qE '^-e'; then
    echo=$cmd
    break
  fi
done
CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"
CSUCCESS="$CDGREEN"
CFAILURE="$CRED"
CQUESTION="$CMAGENTA"
CWARNING="$CYELLOW"
CMSG="$CCYAN"
THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)

Download_src() {
  [ -s "${src_url##*/}" ] && echo "[${CMSG}${src_url##*/}${CEND}] found" || {
    wget --limit-rate=100M --tries=6 -c ${src_url}
    sleep 1
  }
  if [ ! -e "${src_url##*/}" ]; then
    echo "${CFAILURE}Auto download failed! You can manually download ${src_url} into the current directory [${PWD}].${CEND}"
    kill -9 $$
    exit 1
  fi
}

jemalloc_ver="5.2.1"
openssl11_ver="1.1.1m"
pcre_ver="8.45"
nginx_ver="1.20.2"
run_group="www"
run_user="www"
wwwroot_dir="/mnt/wwwroot"
wwwlogs_dir="/mnt/wwwlogs"
nginx_install_dir="/usr/local/nginx"
nginx_modules_options="--with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-http_ssl_module --with-http_gzip_static_module --with-http_realip_module --with-http_flv_module --with-http_mp4_module"
ngx_brotli_module_flag=0

[ -e "${nginx_install_dir}/sbin/nginx" ] && { echo "${CWARNING}Nginx already installed! ${CEND}"; exit 1; }

while :; do
  echo
  read -e -p "Do you want to add ngx_brotli module? [y/n]: " enable_ngx_brotli
  if [[ ! ${enable_ngx_brotli} =~ ^[y,n]$ ]]; then
    echo "${CWARNING}Input error! Please only input 'y' or 'n'${CEND}"
  else
    if [ "${enable_ngx_brotli}" == 'y' ]; then
      while :; do echo
        echo 'Please select the installation method of ngx_brotli (See https://github.com/google/ngx_brotli):'
        echo -e "\t${CMSG}1${CEND}. Dynamically loaded"
        echo -e "\t${CMSG}2${CEND}. Statically compiled"
        read -e -p "Please input a number:(Default 1 press Enter) " ngx_brotli_install_method
        ngx_brotli_install_method=${ngx_brotli_install_method:-1}
        if [[ ! ${ngx_brotli_install_method} =~ ^[1,2]$ ]]; then
          echo "${CWARNING}Input error! Please only input number 1~2${CEND}"
        else
          break
        fi
      done
    fi
    break
  fi
done

echo
read -e -p "Please enter your custom nginx server name(Leave blank to not modify): " server_name

echo
read -e -p "Please enter your custom nginx server version(Leave blank to not modify): " server_version


Install_Jemalloc() {
  if [ ! -e "/usr/local/lib/libjemalloc.so" ]; then
    # jemalloc
    echo "Download Jemalloc${jemalloc_ver}..."
    src_url=https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_ver}/jemalloc-${jemalloc_ver}.tar.bz2 && Download_src

    if [ -d ./jemalloc-${jemalloc_ver} ]; then
      echo "${CWARNING} Dir jemalloc-${jemalloc_ver} [found]${CEND}"
      rm -rf ./jemalloc-${jemalloc_ver}
    fi

    tar xjf jemalloc-${jemalloc_ver}.tar.bz2

    pushd jemalloc-${jemalloc_ver} >/dev/null
    ./configure
    if [ $? -ne 0 ]; then
      popd >/dev/null
      echo "${CFAILURE}Jemalloc install failed! ${CEND}"
      kill -9 $$
      exit 1
    fi

    make -j ${THREAD} && make install
    if [ $? -ne 0 ]; then
      popd >/dev/null
      echo "${CFAILURE}Jemalloc install failed! ${CEND}"
      kill -9 $$
      exit 1
    fi

    popd >/dev/null
    if [ -f "/usr/local/lib/libjemalloc.so" ]; then
      ln -s /usr/local/lib/libjemalloc.so.2 /usr/lib/libjemalloc.so.1
      [ -z "$(grep /usr/local/lib /etc/ld.so.conf.d/*.conf)" ] && echo '/usr/local/lib' >/etc/ld.so.conf.d/local.conf
      ldconfig
      echo "${CSUCCESS}Jemalloc module installed successfully! ${CEND}"
      rm -rf jemalloc-${jemalloc_ver}
    else
      echo "${CFAILURE}Jemalloc install failed! ${CEND}" && lsb_release -a
      kill -9 $$
      exit 1
    fi
    popd >/dev/null
  fi
}
Download_Nginx_Brotli() {
  # ngx_brotli
  if [ -d ./ngx_brotli ]; then
    echo "${CWARNING} Dir ngx_brotli [found]${CEND}"
    rm -rf ./ngx_brotli
  fi
  mkdir -p ./ngx_brotli

  command -v git >/dev/null 2>&1 || { apt-get install -y git; }
  git clone https://github.com/google/ngx_brotli --recursive
}
Install_Nginx() {
  # start Time
  startTime=$(date +%s)
  Install_Jemalloc

  id -g ${run_group} >/dev/null 2>&1
  [ $? -ne 0 ] && groupadd ${run_group}
  id -u ${run_user} >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -g ${run_group} -M -s /sbin/nologin ${run_user}

  [ ! -d ${wwwroot_dir} ] && mkdir -p ${wwwroot_dir}
  [ ! -d ${wwwroot_dir}/default ] && mkdir -p ${wwwroot_dir}/default
  [ ! -d ${wwwlogs_dir} ] && mkdir -p ${wwwlogs_dir}

  # openssl
  echo "Download openSSL${openssl11_ver}..."
  src_url=https://www.openssl.org/source/openssl-${openssl11_ver}.tar.gz && Download_src
  # pcre
  echo "Download pcre${pcre_ver}..."
  src_url=https://downloads.sourceforge.net/project/pcre/pcre/${pcre_ver}/pcre-${pcre_ver}.tar.gz && Download_src
  # nginx
  echo "Download nginx${nginx_ver}..."
  src_url=http://nginx.org/download/nginx-${nginx_ver}.tar.gz && Download_src

  if [ "${enable_ngx_brotli}" == 'y' ]; then
    echo "Download ngx_brotli..."
    Download_Nginx_Brotli
  fi

  if [ -d ./nginx-${nginx_ver} ]; then
    echo "${CWARNING} Dir nginx-${nginx_ver} [found]${CEND}"
    rm -rf ./nginx-${nginx_ver}
  fi

  tar xzf pcre-${pcre_ver}.tar.gz
  tar xzf nginx-${nginx_ver}.tar.gz
  tar xzf openssl-${openssl11_ver}.tar.gz
  pushd nginx-${nginx_ver} >/dev/null

  # Modify Nginx version
  if [ "$server_version" != "" ]; then
    sed -i 's@#define NGINX_VERSION.*$@#define NGINX_VERSION      "'${server_version}'"@' src/core/nginx.h
  fi
  if [ "$server_name" != "" ]; then
    sed -i "s@Server: nginx@Server: ${server_name}@" src/http/ngx_http_header_filter_module.c
    sed -i 's@#define NGINX_VER.*NGINX_VERSION$@#define NGINX_VER          "'${server_name}'/" NGINX_VERSION@' src/core/nginx.h
  fi

  # close debug
  sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' auto/cc/gcc

  [ ! -d "${nginx_install_dir}" ] && mkdir -p ${nginx_install_dir}
  if [ "${enable_ngx_brotli}" == 'y' ]; then
    case "${ngx_brotli_install_method}" in
      1)
        nginx_modules_options="${nginx_modules_options} --add-dynamic-module=../ngx_brotli"
        ;;
      2)
        nginx_modules_options="${nginx_modules_options} --add-module=../ngx_brotli"
        ;;
    esac
  fi
  ./configure --prefix=${nginx_install_dir} --user=${run_user} --group=${run_group} --modules-path=${nginx_install_dir}/modules --with-openssl=../openssl-${openssl11_ver} --with-pcre=../pcre-${pcre_ver} --with-pcre-jit --with-ld-opt='-ljemalloc' ${nginx_modules_options}
  if [ $? -ne 0 ]; then
    popd >/dev/null
    echo "${CFAILURE}Nginx install failed! ${CEND}"
    kill -9 $$
    exit 1
  fi
  make -j ${THREAD} && make install
  if [ $? -ne 0 ]; then
    popd >/dev/null
    echo "${CFAILURE}Nginx install failed! ${CEND}"
    kill -9 $$
    exit 1
  fi
  if [ -e "${nginx_install_dir}/conf/nginx.conf" ]; then
    rm -rf pcre-${pcre_ver} openssl-${openssl11_ver} nginx-${nginx_ver}
    echo "${CSUCCESS}Nginx installed successfully! ${CEND}"
  else
    popd >/dev/null
    rm -rf ${nginx_install_dir}
    echo "${CFAILURE}Nginx install failed! ${CEND}"
    kill -9 $$
    exit 1
  fi
  if [ "${enable_ngx_brotli}" == 'y' ]; then
    if [ "${ngx_brotli_install_method}" == '1' ]; then
      # ngx_brotli Dynamically loaded https://www.majlovesreg.one/adding-brotli-to-a-built-nginx-instance
      echo "Make ngx_brotli dynamic module..."
      make modules
      if [ $? -ne 0 ]; then
        echo "${CFAILURE}Make ngx_brotli module failed! ${CEND}"
      else
        [ ! -f ${nginx_install_dir}/modules/ngx_http_brotli_filter_module.so ] && cp objs/ngx_http_brotli_filter_module.so ${nginx_install_dir}/modules/ngx_http_brotli_filter_module.so
        [ ! -f ${nginx_install_dir}/modules/ngx_http_brotli_static_module.so ] && cp objs/ngx_http_brotli_static_module.so ${nginx_install_dir}/modules/ngx_http_brotli_static_module.so
        #cp objs/*.so ${nginx_install_dir}/modules/
        chmod 644 ${nginx_install_dir}/modules/ngx_http_brotli_filter_module.so
        chmod 644 ${nginx_install_dir}/modules/ngx_http_brotli_static_module.so
        ngx_brotli_module_flag=1
      fi
    else
      ngx_brotli_module_flag=1
    fi
  fi
  popd >/dev/null

  [ -e /usr/bin/nginx ] && rm -f /usr/bin/nginx
  ln -s ${nginx_install_dir}/sbin/nginx /usr/bin/nginx
  #[ -z "$(grep ^'export PATH=' /etc/profile)" ] && echo "export PATH=${nginx_install_dir}/sbin:\$PATH" >>/etc/profile
  #[ -n "$(grep ^'export PATH=' /etc/profile)" -a -z "$(grep ${nginx_install_dir} /etc/profile)" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${nginx_install_dir}/sbin:\1@" /etc/profile
  #. /etc/profile

  if [ -e /bin/systemctl ]; then
    cat >/lib/systemd/system/nginx.service <<"EOF"
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPost=/bin/sleep 0.1
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
TimeoutStartSec=120
LimitNOFILE=1000000
LimitNPROC=1000000
LimitCORE=1000000

[Install]
WantedBy=multi-user.target
EOF
    sed -i "s@/usr/local/nginx@${nginx_install_dir}@g" /lib/systemd/system/nginx.service
    systemctl enable nginx
  else
    cat >/etc/init.d/nginx <<"EOF"
#! /bin/sh

### BEGIN INIT INFO
# Provides:          nginx
# Required-Start:    $all
# Required-Stop:     $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts the nginx web server
# Description:       starts nginx using start-stop-daemon
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DAEMON=/usr/local/nginx/sbin/nginx
DAEMON_OPTS='-c /usr/local/nginx/conf/nginx.conf'
NAME=nginx
DESC=nginx

test -x $DAEMON || exit 0

# Include nginx defaults if available
if [ -f /etc/default/nginx ] ; then
  . /etc/default/nginx
fi

set -e

case "$1" in
  start)
    echo -n "Starting $DESC: "
    start-stop-daemon --start --quiet --pidfile /var/run/nginx.pid --exec $DAEMON -- $DAEMON_OPTS
    echo "$NAME."
    ;;
  stop)
    echo -n "Stopping $DESC: "
    start-stop-daemon --stop --quiet --pidfile /var/run/nginx.pid --exec $DAEMON
    echo "$NAME."
    ;;
  restart|force-reload)
    echo -n "Restarting $DESC: "
    start-stop-daemon --stop --quiet --pidfile /var/run/nginx.pid --exec $DAEMON
    sleep 1
    start-stop-daemon --start --quiet --pidfile /var/run/nginx.pid --exec $DAEMON -- $DAEMON_OPTS
    echo "$NAME."
    ;;
  reload)
    echo -n "Reloading $DESC configuration: "
    start-stop-daemon --stop --signal HUP --quiet --pidfile /var/run/nginx.pid \
        --exec $DAEMON
    echo "$NAME."
    ;;
  configtest)
    $DAEMON -t $DAEMON_OPTS
    ;;
  *)
    N=/etc/init.d/$NAME
    echo "Usage: $N {start|stop|restart|configtest|force-reload}" >&2
    exit 1
    ;;
esac

exit 0
EOF
    sed -i "s@/usr/local/nginx@${nginx_install_dir}@g" /etc/init.d/nginx
    update-rc.d nginx defaults
  fi

  mv ${nginx_install_dir}/conf/nginx.conf{,_bk}
  cat >${nginx_install_dir}/conf/nginx.conf <<"EOF"
user www www;
worker_processes auto;

error_log /data/wwwlogs/error_nginx.log crit;
pid /var/run/nginx.pid;
worker_rlimit_nofile 51200;

events {
  use epoll;
  worker_connections 51200;
  multi_accept on;
}

http {
  include mime.types;
  default_type application/octet-stream;
  server_names_hash_bucket_size 128;
  client_header_buffer_size 32k;
  large_client_header_buffers 4 32k;
  client_max_body_size 1024m;
  client_body_buffer_size 10m;
  sendfile on;
  tcp_nopush on;
  keepalive_timeout 120;
  server_tokens off;
  tcp_nodelay on;

  ##fastcgi
  #fastcgi_connect_timeout 300;
  #fastcgi_send_timeout 300;
  #fastcgi_read_timeout 300;
  #fastcgi_buffer_size 64k;
  #fastcgi_buffers 4 64k;
  #fastcgi_busy_buffers_size 128k;
  #fastcgi_temp_file_write_size 128k;
  #fastcgi_intercept_errors on;

  #Gzip Compression
  gzip on;
  gzip_buffers 16 8k;
  gzip_comp_level 6;
  gzip_http_version 1.1;
  gzip_min_length 256;
  gzip_proxied any;
  gzip_vary on;
  gzip_types
    text/xml application/xml application/atom+xml application/rss+xml application/xhtml+xml image/svg+xml
    text/javascript application/javascript application/x-javascript
    text/x-json application/json application/x-web-app-manifest+json
    text/css text/plain text/x-component
    font/opentype application/x-font-ttf application/vnd.ms-fontobject
    image/x-icon;
  gzip_disable "MSIE [1-6]\.(?!.*SV1)";

  #Brotli Compression   https://github.com/google/ngx_brotli/
  #brotli on;
  #brotli_comp_level 6;
  #brotli_types application/atom+xml application/javascript application/json application/rss+xml application/vnd.ms-fontobject application/x-font-opentype application/x-font-truetype application/x-font-ttf application/x-javascript application/xhtml+xml application/xml font/eot font/opentype font/otf font/truetype image/svg+xml image/vnd.microsoft.icon image/x-icon image/x-win-bitmap text/css text/javascript text/plain text/xml;

  ##If you have a lot of static files to serve through Nginx then caching of the files' metadata (not the actual files' contents) can save some latency.
  #open_file_cache max=1000 inactive=20s;
  #open_file_cache_valid 30s;
  #open_file_cache_min_uses 2;
  #open_file_cache_errors on;

  log_format json escape=json '{"@timestamp":"$time_iso8601",'
                      '"server_addr":"$server_addr",'
                      '"remote_addr":"$remote_addr",'
                      '"scheme":"$scheme",'
                      '"request_method":"$request_method",'
                      '"request_uri": "$request_uri",'
                      '"request_length": "$request_length",'
                      '"uri": "$uri", '
                      '"request_time":$request_time,'
                      '"body_bytes_sent":$body_bytes_sent,'
                      '"bytes_sent":$bytes_sent,'
                      '"status":"$status",'
                      '"upstream_time":"$upstream_response_time",'
                      '"upstream_host":"$upstream_addr",'
                      '"upstream_status":"$upstream_status",'
                      '"host":"$host",'
                      '"http_referer":"$http_referer",'
                      '"http_user_agent":"$http_user_agent"'
                      '}';

######################## default ############################
  server {
    listen 80;
    server_name _;
    access_log /data/wwwlogs/access_nginx.log combined;
    root /data/wwwroot/default;
    index index.html index.htm index.php;
    #error_page 404 /404.html;
    #error_page 502 /502.html;
    location /nginx_status {
      stub_status on;
      access_log off;
      allow 127.0.0.1;
      deny all;
    }
    location ~ [^/]\.php(/|$) {
      #fastcgi_pass remote_php_ip:9000;
      fastcgi_pass unix:/dev/shm/php-cgi.sock;
      fastcgi_index index.php;
      include fastcgi.conf;
    }
    location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
      expires 30d;
      access_log off;
    }
    location ~ .*\.(js|css)?$ {
      expires 7d;
      access_log off;
    }
    location ~ ^/(\.user.ini|\.ht|\.git|\.svn|\.project|LICENSE|README.md) {
      deny all;
    }
    location /.well-known {
      allow all;
    }
  }
########################## vhost #############################
  include vhost/*.conf;
}
EOF
  [ -e ${nginx_install_dir}/conf/proxy.conf ] && mv ${nginx_install_dir}/conf/proxy.conf{,_bk}
  cat >${nginx_install_dir}/conf/proxy.conf <<"EOF"
proxy_connect_timeout 300s;
proxy_send_timeout 900;
proxy_read_timeout 900;
proxy_buffer_size 32k;
proxy_buffers 4 64k;
proxy_busy_buffers_size 128k;
proxy_redirect off;
proxy_hide_header Vary;
proxy_set_header Accept-Encoding '';
proxy_set_header Referer $http_referer;
proxy_set_header Cookie $http_cookie;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
EOF
  sed -i "s@/data/wwwroot/default@${wwwroot_dir}/default@" ${nginx_install_dir}/conf/nginx.conf
  sed -i "s@/data/wwwlogs@${wwwlogs_dir}@g" ${nginx_install_dir}/conf/nginx.conf
  sed -i "s@^user www www@user ${run_user} ${run_group}@" ${nginx_install_dir}/conf/nginx.conf

  if [ "${enable_ngx_brotli}" == 'y' ] && [ ${ngx_brotli_module_flag} == 1 ]; then
    sed -i "s@#brotli on@brotli on@" ${nginx_install_dir}/conf/nginx.conf
    sed -i "s@#brotli_@brotli_@g" ${nginx_install_dir}/conf/nginx.conf
    if [ "${ngx_brotli_install_method}" == '1' ]; then
      sed -i "1i load_module modules/ngx_http_brotli_filter_module.so;" ${nginx_install_dir}/conf/nginx.conf
      sed -i "2i load_module modules/ngx_http_brotli_static_module.so;\n" ${nginx_install_dir}/conf/nginx.conf
    fi
  fi

  # logrotate nginx log
  cat >/etc/logrotate.d/nginx <<EOF
${wwwlogs_dir}/*nginx.log {
  daily
  rotate 5
  missingok
  dateext
  compress
  notifempty
  sharedscripts
  postrotate
    [ -e /var/run/nginx.pid ] && kill -USR1 \`cat /var/run/nginx.pid\`
  endscript
}
EOF
  ldconfig

  rm -rf ./nginx-${nginx_ver}
  rm -rf ./openssl-${openssl11_ver}
  rm -rf ./pcre-${pcre_ver}
  [ -d ./ngx_brotli ] && rm -rf ./ngx_brotli

  echo -e "${CSUCCESS} \nNginx ${nginx_ver} Installed Successfully!${CEND}"

  if [ "${enable_ngx_brotli}" == 'y' ] && [ ${ngx_brotli_module_flag} != 1 ]; then
    echo "${CFAILURE}ngx_brotli dynamic module install failed! ${CEND}"
  fi

  echo -e "\nInstalled Nginx version and configure options: "
  nginx -V

  service nginx start

  endTime=$(date +%s)
  ((installTime = ($endTime - $startTime) / 60))
  echo "####################Congratulations########################"
  echo "Total Install Time: ${CQUESTION}${installTime}${CEND} minutes"
  echo -e "\n$(printf "%-32s" "Nginx install dir":)${CMSG}${nginx_install_dir}${CEND}"
  echo -e "\n$(printf "%-32s" "Nginx config dir":)${CMSG}${nginx_install_dir}/conf${CEND}"
  echo -e "\n$(printf "%-32s" "Nginx modules dir":)${CMSG}${nginx_install_dir}/modules${CEND}"
  echo -e "\n$(printf "%-32s" "Web dir":)${CMSG}${wwwroot_dir}${CEND}"
  echo -e "\n$(printf "%-32s" "Web logs dir":)${CMSG}${wwwlogs_dir}${CEND}"
}
Install_Nginx 2>&1 | tee -a ./install.log
