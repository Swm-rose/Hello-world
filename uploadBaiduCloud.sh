#!/bin/bash
#########常量区##############
tokenFile=~/.baiduDiskTokenFile

#########变量区##############
filePath=${1}
uploadFilePath=${2}
fileSize=$(ls -l ${filePath} | awk '{print $5}')
fileSplitPath="/tmp/bdyDiskUpload/$(uuidgen | sed 's/-//g')/"

refreshAccessToken="https://openapi.baidu.com/oauth/2.0/token?grant_type=refresh_token&"
accessToken=
preCreateUrl=
uploadUrl=
createUrl=

splitFileMd5=
fileMd5=
uploadId=

###########函数区#############
#打印输出
function wlog() {
  content_str=$1
  var_color=$2
  var_curr_timestamp=$(date "+%Y-%m-%d %H:%M:%S.%N" | cut -b 1-23)
  content_echo_str=""

  ## 判断参数1 是否是空字符串
  if [ "x${content_str}" == "x" ]; then
    return
  else
    content_str="[${var_curr_timestamp}] ${content_str}"
  fi
  content_echo_str="${content_str}"

  ## 判断颜色
  if [ "${var_color}" == "green" ]; then
    content_echo_str="\033[32m${content_str}\033[0m"
  elif [ "${var_color}" == "yellow" ]; then
    content_echo_str="\033[33m${content_str}\033[0m"
  elif [ "${var_color}" == "red" ]; then
    content_echo_str="\033[1;41;33m${content_str}\033[0m"
  fi

  ## 打印输出
  echo -e "${content_echo_str}"
}

function refreshAccessToken() {
  refreshToken=$(cat ${tokenFile} | grep -E 'refreshToken')
  refreshToken=$(echo ${refreshToken#*=} | tr -d '"')

  appKey=$(cat ${tokenFile} | grep -E 'appKey')
  appKey=$(echo ${appKey#*=} | tr -d '"')

  secretKey=$(cat ${tokenFile} | grep -E 'secretKey')
  secretKey=$(echo ${secretKey#*=} | tr -d '"')

  if [ x"${refreshToken}" = x ]; then
    wlog "refreshToken不存在，程序退出" red
    exit
  fi

  if [ x"${appKey}" = x ]; then
    wlog "appKey不存在，程序退出" red
    exit
  fi

  if [ x"${secretKey}" = x ]; then
    wlog "secretKey不存在，程序退出" red
    exit
  fi
  refreshAccessTokenResult=$(curl "${refreshAccessToken}refresh_token=${refreshToken}&client_id=${appKey}&client_secret=${secretKey}")
  wlog "刷新token结果：${refreshAccessTokenResult}" green

  newAccessToken=$(echo "${refreshAccessTokenResult}" | grep -oP "access_token\S{1,}?," | tr -d '\,' | awk -F ':' '{print $2}')
  newRefreshToken=$(echo "${refreshAccessTokenResult}" | grep -oP "refresh_token\S{1,}?," | tr -d '\,' | awk -F ':' '{print $2}')
  newExpiresIn=$(date -d "${DATE} 20 days" "+%Y%m%d")

  if [ x"${newAccessToken}" = x ] || [ x"${newRefreshToken}" = x ]; then
    wlog "获取新的Token失败" red
    exit
  fi

  wlog "新的newAccessToken结果：${newAccessToken}" green
  wlog "新的newRefreshToken结果：${newRefreshToken}" green

  sed -i "s#refreshToken=.*#refreshToken=${newRefreshToken}#" ~/.baiduDiskTokenFile
  sed -i "s#accessToken=.*#accessToken=${newAccessToken}#" ~/.baiduDiskTokenFile
  sed -i "s#expiresDate=.*#expiresDate=${newExpiresIn}#" ~/.baiduDiskTokenFile

}

function getAccessToken() {
  expiresDate=$(cat ${tokenFile} | grep -E 'expiresDate')
  expiresDate=$(echo ${expiresDate#*=} | tr -d '"')
  today="$(date +%Y%m%d)"

  if [ x"${expiresDate}" = x ] || [[ ${today} > ${expiresDate} ]]; then
    echo "Token可能已过期，刷新获取新的Token"
    refreshAccessToken
  fi

  if [ -f ${tokenFile} ]; then
    accessToken=$(cat ${tokenFile} | grep -E 'accessToken')
    accessToken=$(echo ${accessToken#*=} | tr -d '"')
    if [ x"${accessToken}" = x ]; then
      wlog "accessToken不存在，退出" red
      exit
    fi
  else
    wlog "accessToken不存在，退出" red
    exit
  fi
}

function initBaseUrl() {
  preCreateUrl="http://pan.baidu.com/rest/2.0/xpan/file?method=precreate&access_token=${accessToken}"
  uploadUrl="https://d.pcs.baidu.com/rest/2.0/pcs/superfile2?method=upload&access_token=${accessToken}&type=tmpfile&"
  createUrl="https://pan.baidu.com/rest/2.0/xpan/file?method=create&access_token=${accessToken}"
}

function generateSubFile() {
  mkdir -p ${fileSplitPath}
  split ${filePath} -b 4M "${fileSplitPath}sFile_"
  splitFileMd5=$(md5sum ${fileSplitPath}sFile_* | awk '{print $1}' | tr '\n' ',' | sed 's/,/","/g')
  splitFileMd5="[\"${splitFileMd5/%\",\"/}\"]"
  wlog "获取分片的文件MD5：${splitFileMd5}" green
  fileMd5=$(md5sum ${filePath} | awk '{print $1}')
  wlog "获取文件MD5：${fileMd5}" green
}

function preCreateUpload() {
  preCreateResult=$(curl "${preCreateUrl}" -d "path=${uploadFilePath}&size=${fileSize}&isdir=0&autoinit=1&rtype=3&block_list=${splitFileMd5}&content-md5=${fileMd5}" -H User-Agent: pan.baidu.com)
  wlog "预上传请求结果：${preCreateResult}" green
  resultCode=$(echo "${preCreateResult}" | grep -oP "errno\S{1,}?," | tr -d '\,' | awk -F ':' '{print $2}')
  if [ "${resultCode}" -ne "0" ]; then
    wlog "预上传请求失败！错误码：${resultCode}" red
    wlog "可参考官方文档对照错误码：https://pan.baidu.com/union/doc/3ksg0s9r7#%E9%94%99%E8%AF%AF%E7%A0%81" red
    exit
  fi
  uploadId=$(echo ${preCreateResult} | grep -oP "uploadid\S{1,}?\," | tr -d '"\,' | awk -F ':' '{print $2}')
}

function upload() {
  idx=0
  for itFile in ${fileSplitPath}*; do
    if [ -f "${itFile}" ]; then
      uploadResult=$(curl -F "file=@${itFile}" "${uploadUrl}path=${uploadFilePath}&uploadid=${uploadId}&partseq=${idx}")
      wlog "第${idx}个分片文件上传结果：${uploadResult}" green

      ##提取返回码
      resultCode=$(echo "${uploadResult}" | grep -oP "error_code\S{1,}?," | tr -d '\,' | awk -F ':' '{print $2}')
      if [ -n "${resultCode}" ]; then
        wlog "分片上传请求失败！错误码：${resultCode}" red
        wlog "可参考官方文档对照错误码：https://pan.baidu.com/union/doc/nksg0s9vi#%E9%94%99%E8%AF%AF%E7%A0%81" red
        exit
      fi
      idx=$((${idx} + 1))
    fi
  done
}

function createFile() {
  createFileResult=$(curl "${createUrl}" -d "path=${uploadFilePath}&size=${fileSize}&isdir=0&rtype=3&uploadid=${uploadId}&block_list=${splitFileMd5}" -H User-Agent: pan.baidu.com)
  wlog "创建文件结果：${createFileResult}" green
  ##提取返回码
  resultCode=$(echo "${createFileResult}" | grep -oP "errno\S{1,}?," | tr -d '\,' | awk -F ':' '{print $2}')
  if [ "${resultCode}" -ne "0" ]; then
    wlog "创建文件请求失败！错误码：${resultCode}" red
    wlog "可参考官方文档对照错误码：https://pan.baidu.com/union/doc/rksg0sa17#%E9%94%99%E8%AF%AF%E7%A0%81" red
    exit
  fi
}

function success() {
  wlog "文件上传成功" green
  rm -rf ${fileSplitPath}
  wlog "文件夹${fileSplitPath}已清理" green
}

function main() {
  getAccessToken
  initBaseUrl
  generateSubFile
  preCreateUpload
  upload
  createFile
  success
}
main
