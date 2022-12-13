#!/bin/bash
source ~/.bash_profile
rman target / >> delarchive.log <<EOF
crosscheck archivelog all;
configure archivelog deletion policy to applied on standby;
delete expired archivelog all;
delete noprompt archivelog all completed before 'sysdate-3';
exit;
EOF
