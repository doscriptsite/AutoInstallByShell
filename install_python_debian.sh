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

name="Python"
default_version="3.7.12"

command -v curl >/dev/null 2>&1 || { apt-get install -y curl; }

while :; do
  echo
  read -e -p "Please enter the version number you need (Default version: ${default_version}): " version
  if [ "$version" = "" ]; then
    version="${default_version}"
  fi
  pyfile="${name}-${version}.tgz"
  src_url=https://www.python.org/ftp/python/${version}/${pyfile}
  if [[ $(echo $(curl -sIL -w "%{http_code}" -o /dev/null ${src_url})) != '200' ]]; then
    echo "${CWARNING}The python version is wrong, please re-enter${CEND}"
  else
    break
  fi
done
while :; do
  echo
  read -e -p "Do you want to use Chinese pypi? [y/n]: " switch_pypi
  if [[ ! ${switch_pypi} =~ ^[y,n]$ ]]; then
    echo "${CWARNING}Input error! Please only input 'y' or 'n'${CEND}"
  else
    break
  fi
done
check_ver=$(echo $version | awk '{printf ("%3.1f\n",$1)}')
main_version=${check_ver//./}
dir="/usr/local/python${main_version}"

if [ -d ${dir} ]; then
  while :; do
    echo
    read -e -p "Dir ${dir} [found]. Python${main_version} already installed! Whether to remove the existing directory and reinstall python${main_version}? [y]: " continue_flag
    if [[ ! ${continue_flag} == 'y' ]]; then
      echo "${CWARNING}Input error! Please only input 'y'${CEND}"
      kill -9 $$
      exit 1
    else
      break
    fi
  done
  echo "${CWARNING} Python${main_version} [no found] ${CEND}"
fi

Install_Python() {
  # start Time
  startTime=$(date +%s)
  pkgList="gcc wget make dialog libaugeas0 augeas-lenses zlib1g-dev libssl-dev libffi-dev ca-certificates"
  for Package in ${pkgList}; do
    apt-get -y install ${Package}
  done

  if [ -d ${dir} ]; then
    rm -rf /usr/local/python${main_version}
    rm -rf /usr/bin/python${main_version}
    rm -rf /usr/bin/pip${main_version}
  else
    echo "${CWARNING} Python${main_version} [no found] ${CEND}"
  fi

  if [ -s ./${pyfile} ]; then
    echo "${CWARNING} ${pyfile} [found]${CEND}"
    rm -f ./${pyfile}
  fi
  if [ -d ./${name}-${version} ]; then
    echo "${CWARNING} Dir ${name}-${version} [found]${CEND}"
    rm -rf ./${name}-${version}
  fi

  echo "Download python..."
  wget --limit-rate=100M --tries=6 -c ${src_url}
  sleep 1
  if [ ! -s ./${pyfile} ]; then
    echo "${CFAILURE}Auto download failed! You can manually download ${src_url} into the current directory [${PWD}].${CEND}"
    kill -9 $$
    exit 1
  fi
  tar zxf ./${pyfile}

  pushd ./${name}-${version} >/dev/null
  ./configure --prefix=${dir}
  #./configure --prefix=${dir} --enable-optimizations --with-ssl
  if [ $? -ne 0 ]; then
    popd >/dev/null
    echo "${CFAILURE}Python install failed! ${CEND}"
    kill -9 $$
    exit 1
  fi
  make && make install
  if [ $? -ne 0 ]; then
    popd >/dev/null
    echo "${CFAILURE}Python install failed! ${CEND}"
    kill -9 $$
    exit 1
  fi
  popd >/dev/null

  # eg: link python37 to /usr/bin/
  ln -s ${dir}/bin/python${check_ver} /usr/bin/python${main_version}
  ln -s ${dir}/bin/pip${check_ver} /usr/bin/pip${main_version}

  if [ -e "${dir}/bin/python${check_ver}" ]; then
    echo "${CSUCCESS}Python ${version} installed successfully!${CEND}"
    rm -rf ./${name}-${version}
  fi
  if [ "${switch_pypi}" == 'y' ]; then
    if [ ! -e "/root/.pip/pip.conf" ]; then
      [ ! -d "/root/.pip" ] && mkdir /root/.pip
      cat >/root/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host=pypi.tuna.tsinghua.edu.cn
disable-pip-version-check = true
timeout = 6000
EOF
    else
      echo "${CWARNING}Pip file is [found]${CEND}"
    fi
  fi

  pip${main_version} install --upgrade pip

  echo -e "${CSUCCESS} \nPython ${version} Installed Successfully!${CEND}"

  echo -e "\nInstalled Python and pip version is ... "
  python${main_version} -V && pip${main_version} -V

  endTime=$(date +%s)
  ((installTime = ($endTime - $startTime) / 60))
  echo "####################Congratulations########################"
  echo "Total Install Time: ${CQUESTION}${installTime}${CEND} minutes"
  echo -e "\n$(printf "%-32s" "Python install dir":)${CMSG}${dir}${CEND}"
  echo -e "\n$(printf "%-32s" "Python bin file":)${CMSG}/usr/bin/python${main_version}${CEND}"
  echo -e "\n$(printf "%-32s" "Pip bin file":)${CMSG}/usr/bin/pip${main_version}${CEND}"
}
Install_Python 2>&1 | tee -a ./install_python.log
