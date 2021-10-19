#!/bin/bash
# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script, please use root to install"
  exit 1
fi

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

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

Install_Python() {
  name="Python"
  version="3.7.12"
  pyfile="$name-$version.tgz"
  while :; do echo
    read -e -p "Please enter the version number you need (Default version: 3.7.12): " version
    if [ "$version" = "" ]; then
      version="3.7.12"
    fi
    pyfile="$name-$version.tgz"
    if [[ $(echo $(curl -sIL -w "%{http_code}" -o /dev/null https://www.python.org/ftp/python/$version/$pyfile)) != '200' ]]; then
      echo "${CWARNING}The python version is wrong, please re-enter${CEND}"
    else
      break
    fi
  done
  while :; do echo
    read -e -p "Do you want to use Chinese pypi? [y/n]: " switch_pypi
    if [[ ! ${switch_pypi} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
  check_ver=$(echo $version | awk '{printf ("%3.1f\n",$1)}')
  main_version=${check_ver//./}
  dir="/usr/local/python$main_version"

  [ -z "$(grep -w epel /etc/yum.repos.d/*.repo)" ] && yum -y install epel-release
  pkgList="wget gcc gcc-c++ make bzip2-devel dialog augeas-libs openssl openssl-devel libffi-devel redhat-rpm-config ca-certificates"
  for Package in ${pkgList}; do
    yum -y install ${Package}
  done

  if [ -e $dir ]; then
    rm -rf /usr/local/python$main_version
    rm -rf /usr/bin/python$main_version
    rm -rf /usr/bin/pip$main_version
  else
    echo -e "${CWARNING} python [no found] ${CEND}"
  fi

  if [ -s ./$pyfile ]; then
    echo -e "${CWARNING} $pyfile [found]${CEND}"
    rm -f ./$pyfile
  fi
  if [ -d ./$name-$version ]; then
    echo -e "${CWARNING} Dir $name-$version [found]${CEND}"
    rm -rf ./$name-$version
  fi
  wget https://www.python.org/ftp/python/$version/$pyfile
  tar zxf ./$pyfile

  cd ./$name-$version
  ./configure --prefix=$dir
  #./configure --prefix=$dir --enable-optimizations --with-ssl
  make && make install

  ln -s /usr/local/python$main_version/bin/python$check_ver /usr/bin/python$main_version
  ln -s /usr/local/python$main_version/bin/pip$check_ver /usr/bin/pip$main_version

  if [ -e "${dir}/bin/python" ]; then
    echo "${CSUCCESS}Python ${version} installed successfully!${CEND}"
    rm -rf ./$name-$version
  fi
  if [ "${switch_pypi}" == 'y' ]; then
    if [ ! -e "/root/.pip/pip.conf" ] ;then
      # get the IP information
      [ ! -d "/root/.pip" ] && mkdir /root/.pip
      cat >~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
[install]
trusted-host=pypi.tuna.tsinghua.edu.cn
disable-pip-version-check = true
timeout = 6000
EOF
    else
      echo -e "${CWARNING}pip file is [found]${CEND}"
    fi
  fi

  pip$main_version install --upgrade pip

  echo -e "\nInstalled Python and pip version is ... "
  python$main_version -V && pip$main_version -V

  echo -e "${CSUCCESS} \nInstall Successfully! ${CEND}"
}
Install_Python 2>&1 | tee -a ./install.log
