
#!/usr/bin/env bash                         
# 
# 说明 : 用于删除物理备库已经应用过的归档日志.
#        在使用之前根据实际情况设置环境变量.
#        在备库上执行该脚本. 在使用前请进行测试
#
# 用法： ./del_archivelog.sh                                                            
#                                                                                                                               
# =================================================================================

#----------------------------------------------------------------------------------
###设置环境变量
export ORACLE_HOME=/data/u01/app/oracle/product/11.2.0/dbhome_1
export ORACLE_SID=sygas
export PATH=$ORACLE_HOME/bin:$PATH
#export ARCHIVE_DIR=+DATA/standby/archivelog
export LOG_FILE=$HOME/cronjobs/logs/del_archive.log
#----------------------------------------------------------------------------------

###判断用户 
if [ `whoami` != 'oracle' ];then
echo "Warning: Please use oracle execute.">>$LOG_FILE
exit 99
fi

###定义要删除的 archivelog sequence 
sqlplus -s / as sysdba << EOF > tmp.log
set lines 100 feedback off echo off heading off;
select thread#,max(sequence#) from v\$archived_log where applied='YES' group by thread# order by thread#;
EOF

MAXLINE=`cat tmp.log|wc -l`

for (( i=1;i<$MAXLINE;i++ )); do

i=$(( i + 1 ))
THREAD=`sed -n "$i,$i"p tmp.log|awk -F' ' '{print $1}'`
MAXSEQ=`sed -n "$i,$i"p tmp.log|awk -F' ' '{print $2}'`

###保留最近5个归档
MAXSEQ=$(( $MAXSEQ - 5 ))

###删除从库已经应用的归档
echo "****************************************************************************" >> $LOG_FILE
echo ">>> 开始删除已应用的归档 : `date` <<<">>$LOG_FILE

i=$(( i - 1 ))

rman target / <<EOF >> $LOG_FILE
##catalog start with '$ARCHIVE_DIR' noprompt;
delete noprompt archivelog until sequence $MAXSEQ thread $THREAD;
EOF

echo >> $LOG_FILE
echo ">>> 删除归档结束 : `date` <<<">>$LOG_FILE

echo "****************************************************************************" >> $LOG_FILE
echo >> $LOG_FILE

done

rm -f tmp.log

