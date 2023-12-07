#!/bin/bash
COLOR="echo -e \033[1;36m"
ERROR="echo -e \033[1;31m"
END='\033[0m'
local_ip=$(ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:"​)
OK=yes
TIME=$(date "+%Y-%m-%d %H:%M:%S")
$COLOR"======================================================"
$COLOR"                       基线检查"
$ERROR "                 本机IP：$local_ip "$END
$ERROR "                 当前时间：$TIME" $END
## 备份需要修改的文件

function bak_file() {
	mkdir -p /bak
	cp /etc/login.defs /bak/login.defs
	cp /etc/pam.d/system-auth /bak/system-auth
	cp /etc/pam.d/sshd /bak/sshd
	cp /etc/ssh/sshd_config /bak/sshd_config
	cp /etc/pam.d/login /bak/login
}

function check_passwd() {
	DAYS=$(cat /etc/login.defs | grep -v ^# | grep MAX_DAYS | awk -F ' ' '{print $2}')
	LEN=$(cat /etc/login.defs | grep -v ^# | grep MIN_LEN | awk -F ' ' '{print $2}')
	AGE=$(cat /etc/login.defs | grep -v ^# | grep WARN_AGE | awk -F ' ' '{print $2}')
	$COLOR "1、检测密码有效时间" $END
	if [ $DAYS != 90 ]; then

		sed -i "s/$DAYS/90/g" /etc/login.defs
		$ERROR "已将密码修改有限时间90天" $END
		$COLOR "PASS_MAX_DAYS=90" $END

	else
		$ERROR "密码有限时间为90天" $END
		$COLOR "PASS_MAX_DAYS=90" $END
	fi

	$COLOR"======================================================"

	$COLOR "2、检测密码字符长度" $END

	if [ $LEN != 8 ]; then
		sed -i "s/$LEN/8/g" /etc/login.defs
		$COLOR "已将密码长度修改为8字符" $END
		$COLOR "PASS_MIN_LEN=8" $END
	else
		$ERROR "密码长度间为8字符" $END
		$COLOR "PASS_MIN_LEN=8" $END
	fi

	$COLOR"======================================================"

	$COLOR "3、检查口令过期前警告天数不小于标准值7" $END
	if [ $AGE != 7 ]; then

		sed -i "s/$AGE/7/g" /etc/login.defs
		$ERROR "已将口令过期前警告天数修改为7天" $END
		$COLOR "PASS_WARN_AGE=7" $END
	else
		echo "口令过期前警告天数为7天"
		$COLOR "PASS_WARN_AGE=7" $END
	fi

	$COLOR"======================================================"

	$COLOR "4、检测密码复杂度" $END

	CPX=$(cat /etc/pam.d/system-auth | grep minclass=3)
	CPX2=$(cat /etc/pam.d/system-auth | grep pass | head -2 | tail -1)

	if [ ! -n "$CPX" ]; then
		$COLOR "$CPX" $EDN
		$COLOR "$CPX2" $EDN
		#read -p "查看确认是否需要修改(yes/on)": OK
		if [ $OK = yes ]; then
			sed -i 's/^password    requisite/#&/' /etc/pam.d/system-auth
			sed -i "16ipassword    requisite     pam_pwquality.so retry=3 minlen=8 minclass=3 enforce_for_root" /etc/pam.d/system-auth
			$ERROR "密码复杂度为数字、小写字母、大写字母和特殊符号4类中至少3类" $END
		else
			$ERROR "未修改 /etc/pam.d/system-auth 文件请确保符合要求" $END
		fi
	else
		$COLOR "$CPX" $EDN
	fi

	$COLOR"======================================================"

	$COLOR "5、检测密码重复使用次数" $END
	RPT=$(cat /etc/pam.d/system-auth | grep remember=5)
	RPT2=$(cat /etc/pam.d/system-auth | grep "password    sufficient")
	if [ -z "$RPT" ]; then
		$COLOR "$RPT" $EDN
		$COLOR "$RPT2" $EDN
		#read -p "查看确认是否需要修改(yes/on)": OK
		if [ $OK = yes ]; then
			sed -i '/^password\s\+sufficient\s\+pam_unix.so\s\+sha512\s\+shadow\s\+nullok\s\+try_first_pass\s\+use_authtok$/ s/$/ remember=5 enforce_for_root/' /etc/pam.d/system-auth
			$ERROR "密码重复使用次数限制不超过5次" $END
		else
			$ERROR "未修改 /etc/pam.d/system-auth 文件请确保符合要求" $END
		fi
	else
		$COLOR "$RPT" $EDN
	fi
}
## 系统设置检查修改

$COLOR"======================================================"
function check_system() {
	$COLOR "6、超出规定时间进行账户退出操作检查" $END

	TIME=$(cat /etc/profile | grep TMOUT=600)
	if [ -z "$TIME" ]; then

		sed -i '/HISTSIZE/a\TMOUT=600' /etc/profile && source /etc/profile
		$COLOR "超出规定时间进行账户退出操作已设置"$END
	else
		$COLOR $TIME $END
	fi

	$COLOR"======================================================"

	$COLOR "7、检查空口令用户" $END
	ZERO=$(awk -F : 'length($2)==2 {print $1}' /etc/shadow)

	if [ -z "$ZERO" ]; then
		echo "没有空口令用户"
	else
		for USER in $ZERO; do
			USER_INFO=$(grep "^$USER:" /etc/passwd)
			$COLOR "用户名: $USER" $END
			echo "用户信息: $USER_INFO"
			echo "-----------"
		done
	fi

	$COLOR"======================================================"

	$COLOR "8、检查账户认证失败次数限制" $END
	UNLOCK=$(cat /etc/pam.d/sshd | grep unlock_time=)
	if [ -z "$UNLOCK" ]; then
		sed -i '3i auth       required     pam_tally2.so onerr=fail deny=5 unlock_time=300' /etc/pam.d/sshd
		$COLOR "已配置账户认证失败次数限制，输错 5 次即锁定用户 600 秒"$END
	else
		$COLOR "$UNLOCK" $END
	fi
	$COLOR "9、检查是否设置除root之外UID为0的用户"$END
	USER_UID=$(awk -F : '($3 == 0)' /etc/passwd)

	echo "用户信息: $USER_UID"
}

function check_snmpd() {

	$COLOR"======================================================"

	$COLOR "10、检查是否修改snmp默认团体字"$END
	SPID=$(command -v snmpd)

	if [ "$SPID" == "" ]; then
		$COLOR "未安装snmpd" $END
		return
	else
		NP=$(systemctl is-active snmpd 2>/dev/null)

		if [ "$NP" == "active" ]; then
			PUB=$(grep -ivh '^#' /etc/snmp/snmpd.conf | grep -E 'public|private')

			if [ -n "$PUB" ]; then
				echo -e "${COLOR}$PUB${END}"
				#read -p "查看确认是否需要修改(yes/on): " OK
				if [ "$OK" == "yes" ]; then
					sed -i '/public\|private/s/^/#/' /etc/snmp/snmpd.conf
					echo "修改snmp协议默认的团体字 public 和 private"
				else
					echo "未修改，请保证符合规则"
				fi
			else
				$COLOR "snmpd 未有 public private 团体字"$END
			fi
		else
			$COLOR "snmpd 未运行" $END
		fi
	fi
}

function check_vsftpd() {

	$COLOR"======================================================"

	$COLOR "11、检查是否禁止匿名用户登录FTP & 检查是否限制FTP用户登录后能访问的目录"$END

	TP=$(command -v vsftpd)
	if [ "$TP" == "" ]; then
		echo "未安装vsftpd"
		return
	else
		NP=$(systemctl is-active vsftpd 2>/dev/null)

		if [ "$NP" == "active" ]; then
			PD=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'anonymous_enable=YES')

			if [ -n "$PD" ]; then
				$COLOR "$PD" $END
				#read -p "查看确认是否需要修改(yes/on): " OK
				if [ "$OK" == "yes" ]; then
					sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g' /etc/vsftpd/vsftpd.conf
					sed -i 's/.*chroot_local_user.*/chroot_local_user=YES/g' /etc/vsftpd/vsftpd.conf
					echo "禁止匿名用户登录FTP"
				else
					echo "未修改，请保证符合规则"
				fi
			else
				echo "未开启匿名用户登录FTP"
				PN=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'anonymous_enable=NO')
				$COLOR "$PN" $END
			fi
		else
			echo "vsftpd 未运行"
		fi
	fi
}
function check_ftp() {

	$COLOR"======================================================"

	$COLOR "12、检查是否禁止root用户登录FTP"$END
	if [ "$TP" == "" ] || [ "$NP" != "active" ]; then
		echo "未安装(启动)vsftpd"
		return
	else
		RT=$(grep -ivh '^#' /etc/vsftpd/ftpusers | grep -E 'root')
		if [ -n $RT ]; then
			$COLOR"$RT"$END
			echo "禁止root权限的用户登录FTP"
		else
			#read -p "查看确认是否需要修改(yes/on): " OK
			if [ "$OK" = "yes" ]; then
				sed -i '1 i root' /etc/vsftpd/ftpuser
				echo "禁止root权限的用户登录FTP"
			else

				echo "未修改，请保证符合规则"
			fi
		fi
	fi
	$COLOR "检查FTP用户上传的文件所具有的权限"$END
	qq=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'write_enable=YES')
	ww=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'ls_recurse_enable=YES')
	ee=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'local_umask=022')
	rr=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'anon_umask=022')

	if [ -z "$qq" ] && [ -z "$ww" ] && [ -z "$ee" ] && [ -z "$rr" ]; then
		echo "全部都没有设置"
	else
		if [ -n "$qq" ]; then
			if [ -n "$ww" ]; then
				echo "write_enable 和 ls_recurse_enable 都设置了"
			elif [ -n "$ee" ]; then
				echo "write_enable 和 local_umask 都设置了"
			elif [ -n "$rr" ]; then
				echo "write_enable 和 anon_umask 都设置了"
			else
				echo "只有 write_enable 设置了"
			fi
		elif [ -n "$ww" ]; then
			echo "只有 ls_recurse_enable 设置了"
		elif [ -n "$ee" ]; then
			echo "只有 local_umask 设置了"
		elif [ -n "$rr" ]; then
			echo "只有 anon_umask 设置了"
		else
			echo "全部都设置了"
		fi
	fi

	$COLOR "检查是否限制FTP用户登录后能访问的目录"$END
	CH=$(grep -ivh '^#' /etc/vsftpd/vsftpd.conf | grep -E 'chroot_local_user=YES')
	if [ -z "$CH" ]; then
		$EROOR "没有限制FTP用户登录后能访问的目录" $END
	else
		$COLOR "限制FTP用户登录后能访问的目录:"$CH"" $END
	fi

}

function check_remote() {

	$COLOR"======================================================"
	$COLOR "13、检查是否禁止root用户远程登录" $END

	SSH_NO=$(cat /etc/ssh/sshd_config | grep -v '^#' | grep "PermitRootLogin no")
	PAM_LOGIN=$(cat /etc/pam.d/login | grep auth | grep required | grep pam_securetty.so)

	if [ -n "$SSH_NO" ] && [ -n "$PAM_LOGIN" ]; then
		$COLOR "已经禁止root用户远程登录" $END
	elif [ -n "$SSH_NO" ] && [ -z "$PAM_LOGIN" ]; then
		$ERROR " pam.login 文件不符合" $END
		#read -p "查看确认是否需要修改(yes/on): " OK
		if [ "$OK" = "yes" ]; then
			sed -i '3i auth       required     pam_securetty.so' /etc/pam.d/login
			echo "禁止 root 的用户登录"
		else

			echo "未修改，请保证符合规则"
		fi
	elif [ -z "$SSH_NO" ] && [ -n "$PAM_LOGIN" ]; then
		$ERROR " sshd_config 文件不符合" $END
		#read -p "查看确认是否需要修改(yes/on): " OK
		if [ "$OK" = "yes" ]; then
			sed -i 's/.*PermitRootLogin .*/PermitRootLogin no/g' /etc/ssh/sshd_config
			echo "禁止 root 的用户登录"
		else

			echo "未修改，请保证符合规则"
		fi
	elif [ -z "$SSH_NO" ] && [ -z "$PAM_LOGIN" ]; then
		$ERROR " 两个文件都文件不符合" $END
		#read -p "查看确认是否需要修改(yes/on): " OK
		if [ "$OK" = "yes" ]; then
			sed -i '3i auth       required     pam_securetty.so' /etc/pam.d/login
			sed -i 's/.*PermitRootLogin .*/PermitRootLogin no/g' /etc/ssh/sshd_config
			echo "禁止 root 的用户登录"
		else

			echo "未修改，请保证符合规则"
		fi

	fi

}
function check_user() {
	$COLOR"======================================================"

	$COLOR "14、检查是否按用户分配账号" $END

	UU=$(awk -F : '$7 == "/bin/bash" {print $1}' /etc/passwd)

	if [ -z "$UU" ]; then
		echo "没有可登录的用户"
	else
		for USER in $UU; do
			USER_INFO=$(grep "^$USER:" /etc/passwd)
			$COLOR "用户名: $USER" $END
			echo "用户信息: $USER_INFO"
			echo "-----------"
		done
	fi

}

function check_usr() {
	$COLOR"======================================================"
	$COLOR "15、检查/usr/bin/目录下可执行文件的拥有者属性" $END

	UR=$(find /usr/bin/ -type f -perm -4000 -exec basename {} \;)
	if [ -z "$UR" ]; then
		echo "没有含有 s 属性的文件"
	else
		for US in $UR; do
			USR_INFO=$(ls -l "/usr/bin/$US") # 使用 ls -l 获取详细文件信息
			$ERROR "文件名:" $US $END
			echo "文件信息: $USR_INFO"
			echo "-----------"
		done
	fi
	$COLOR"======================================================"
	$COLOR "16、检查 root 用户的 path 环境变量" $END
	PH=$(echo $PATH)
	$COLOR "root用户的环境变量为:$PH" $END

	$COLOR"======================================================"
	$COLOR "17、检查是否按组进行账号管理" $END
	AD=$(grep admin /etc/group)
	SE=$(grep secures /etc/group)
	AT=$(grep audits /etc/group)
	if [ -z "$AD" ]; then
		$ERROR "admin 组未创建" $END
		groupadd admin
	else
		$COLOR "admin 组已经创建：$AD" $END
	fi

	if [ -z "$SE" ]; then
		$ERROR "secures 组未创建" $END
		groupadd secures
	else
		$COLOR "secures 组已经创建：$SE" $END
	fi

	if [ -z "$AT" ]; then
		$ERROR "audits 组未创建" $END
		groupadd audits
	else
		$COLOR "audits 组已经创建：$AT" $END
	fi
}
function check_log() {

	$COLOR"======================================================"
	$COLOR "18、检查日志文件是否非全局可写" $END

	LOG="secure cron boot.log spooler maillog messages" # 日志文件列表

	for FILE in $LOG; do
		FILE_INFO=$(ls -l "/var/log/$FILE") # 使用 ls -l 获取详细文件信息
		$ERROR 文件名: $FILE $END
		echo "文件信息: $FILE_INFO"
		echo "-----------"
	done

	$COLOR"======================================================"
	$COLOR "19、检查安全事件日志配置" $END

	$COLOR "日志保存方式" $END
	grep -ivh '^#' /etc/logrotate.conf | grep -v '^$'

	$COLOR"======================================================"
	$COLOR "20、检查是否使用NTP（网络时间协议）保持时间同步" $END

	$COLOR "是否存在 NTP 进程" $END
	ps -aux | grep ntpd

	$COLOR"======================================================"
	$COLOR "21、检查是否安装杀毒软件" $END

	$COLOR "是否存在 AliYunDun 进程" $END
	ps -aux | grep AliYunDun
	
	$COLOR"======================================================"
	$ERROR "执行结束：$(date "+%Y-%m-%d %H:%M:%S")" $END
	$COLOR"======================================================"
}

bak_file
check_passwd
check_system
check_snmpd
check_vsftpd
check_ftp
check_remote
check_user
check_usr
check_log