#!/bin/bash

function print_new_line() {
  printf "\n" >> ${read_daily_report_file}
}

function get_stage() {
  if [ -d '/appl/tomcat/apps/ap' ]; then
    read_stage="ap"
    read_sc_ci="P-11"
    read_nfs_stage="1835-read_p"
    rvs_linux_stage="1.2.3.4"
  elif [ -d '/appl/tomcat/apps/aq' ]; then
    read_stage="aq"
    read_sc_ci="Q-11"
    read_nfs_stage="1835-read_qs"
    rvs_linux_stage="1.2.3.3"
  else
    echo "Unknown stage. This should not be used outside of READ Q or READ P."
  fi
}

#populate the *_stage variables
get_stage

oracle_driver="ojdbc-8-12.2.0.1.jar"
jdbc_driver="jdbc2csv-2.1.jar"
java_home="/appl/tomcat/java/jdk1.8.0_251/bin"
java_keytool="/appl/tomcat/java/jdk1.8.0_251/jre/bin/keytool"

current_date=$(date +%d.%m.%Y)
alert_inbox="email@domain.com"

scripts_home="/appl/tomcat/apps/${read_stage}/read/tomcat/scripts"
catalina_context_conf="/appl/tomcat/apps/${read_stage}/read/tomcat/conf/Catalina/localhost/context.xml.default"
catalina_home="/appl/tomcat/apps/${read_stage}/read/tomcat"
read_daily_report_file="${scripts_home}/read_daily_check/read_${read_stage}_daily_report_file.txt"

list_of_dbs=('jdbc/read/etl/read_gui')

function get_db_username() {
  db_to_check=$1
  conf_file=$2
  db_username_raw=$(/bin/grep "${db_to_check}" ${conf_file} | grep -oP '(?<=username=").*?(?=")')
  db_username=$(echo ${db_username_raw} | awk '{print tolower($0)}')
}

function get_db_secret() {
  db_to_check=$1
  conf_file=$2
  db_secret=$(/bin/grep "${db_to_check}" ${conf_file} | grep -oP '(?<=password=").*?(?=")' | sed 's/\&quot\;/\"/')
}

function get_db_conn_string() {
  db_to_check=$1
  conf_file=$2
  db_conn_string=$(/bin/grep "${db_to_check}" ${conf_file} | grep -oP '(?<=url=").*?(?=")' | sed 's/.*@\/\///')
}

function check_daily_report_file() {
  if [ -f ${read_daily_report_file} ]; then
    echo "The READ-NG daily report file exists. Nothing to do here."
  else
    echo "0" > ${read_daily_report_file}
  fi
}

#check the template report file
check_daily_report_file

function send_email() {
  echo "Email." | mail -s "AUTOMATIC ALERT: READ-NG ${read_sc_ci} DAILY HEALTH CHECK REPORT FOR ${current_date}" -a ${read_daily_report_file} ${alert_inbox} 
}

function get_apps_logs() {
    latest_error_archive=$(find ${catalina_home}/logs_read/archive -type f -name "error*zip" -print | sort | tail -n1)
    unzip -o ${latest_error_archive} -d ${scripts_home}/read_daily_check/
    latest_security_archive=$(find ${catalina_home}/logs_read/archive -type f -name "security*zip" -print | sort | tail -n1)
    unzip -o ${latest_security_archive} -d ${scripts_home}/read_daily_check/
    latest_readlog_archive=$(find ${catalina_home}/logs_read/archive -type f -name "read*zip" -print | sort | tail -n1)
    unzip -o ${latest_readlog_archive} -d ${scripts_home}/read_daily_check/
    latest_zsm_archive=$(find ${catalina_home}/logs_read/archive -type f -name "read_zsm*zip" -print | sort | tail -n1)
    unzip -o ${latest_zsm_archive} -d ${scripts_home}/read_daily_check/
}

function get_tomcat_logs() {
    latest_catalina_archive=$(find ${catalina_home}/logs/old -type f -name "catalina*gz" -print | sort | tail -n1)
    cp ${latest_catalina_archive} ${scripts_home}/read_daily_check/
    latest_localhost_access_archive=$(find ${catalina_home}/logs/old -type f -name "localhost_access*gz" -print | sort | tail -n1)
    cp ${latest_localhost_access_archive} ${scripts_home}/read_daily_check/
    gunzip -f ${scripts_home}/read_daily_check/*.gz
}

#the RVS logs are transferred at 07:01 server time. This should run at 8:00 AM.
function get_rvs_logs() {
  latest_rvs_log=$(find /nfs/${read_nfs_stage}/rvs -type f -name "monitor.log.*" -mtime 0)
  cp ${latest_rvs_log} ${scripts_home}/read_daily_check/
}

function summarize_apps_logs() {
  get_apps_logs
p
  number_of_read_errors=$(cat ${scripts_home}/read_daily_check/error.* | grep -c 'ERROR')
  IFS=$'\n'
  echo "The total number of application errors for yesterday: ${number_of_read_errors}" >> ${read_daily_report_file}
  echo "Overview and counter of application errors for yesterday:" >> ${read_daily_report_file}
  array_with_appl_errors=($(grep -A 1 'ERROR' ${scripts_home}/read_daily_check/error.* | sed -r 's/^([^ ]+ ){3}//' | sed -r 's/\[https-.*]//' | sed -r 's/--//'))
  printf '%s\n' "${array_with_appl_errors[@]}" | egrep -v 'Connection reset by peer|Broken pipe|already been called for this response|may not nest' | sort | uniq -c | sort -r >> ${read_daily_report_file}
  print_new_line
  number_of_user_logins=$(cat ${scripts_home}/read_daily_check/security.* | grep -c 'login user:')
  echo "The total number of user logins for yesterday: ${number_of_user_logins}" >> ${read_daily_report_file}
  number_of_zsm_warn=$(cat ${scripts_home}/read_daily_check/read_zsm.* | grep -c 'WARN')
  echo "The total number of ZSM/LEMI interface warnings: ${number_of_zsm_warn}" >> ${read_daily_report_file}
}

function summarize_tomcat_logs() {
  echo 'nothing for now. maybe later.'
}

function summarize_rvs_logs() {
  get_rvs_logs
  number_of_rvs_errors=$(cat ${scripts_home}/read_daily_check/monitor.log.* | grep -c 'ERR')
  echo "The total number of RVS errors for yesterday: ${number_of_rvs_errors}" >> ${read_daily_report_file}
  print_new_line
  echo "Overview and counter of RVS errors for yesterday:" >> ${read_daily_report_file}
  array_with_rvs_errors=($(grep 'ERR' ${scripts_home}/read_daily_check/monitor.log.* | sed -r 's/^([^ ]+ ){3}//'))
  printf '%s\n' "${array_with_rvs_errors[@]}" | sort | uniq -c | sort -r >> ${read_daily_report_file}
  print_new_line
  echo "Summary of all file transfers via RVS yesterday:" >> ${read_daily_report_file}
  print_new_line
  grep -A1 'Delivery of file' ${scripts_home}/read_daily_check/monitor.log.* | sed 's/.*JS_COMMAND//' | sed 's/ | |//' |sed -e "s/[[:space:]]\+/ /g" >> ${read_daily_report_file}
  print_new_line
  printf "Status of last read-etl runs:" >> ${read_daily_report_file}
  print_new_line
  curl -k https://localhost:8448/read-etl/infoAll | sed -r 's\<br/>\\' | sed -r 's\Status all:\\' | sed '/^\s*$/d' >> ${read_daily_report_file}
  print_new_line
  print_new_line
}

function clear_read_daily_check_dir() {
  read_daily_report_filename=$(basename ${read_daily_report_file})
  cp ${read_daily_report_file} /nfs/${read_nfs_stage}/NTT/${read_daily_report_filename}.${current_date}
  rm -f ${scripts_home}/read_daily_check/*
}

function get_tomcat_ssl_status() {
  echo "TRUSTSTORE Tomcat SSL Certificates status for READ ${read_sc_ci}:" >> ${read_daily_report_file}
  print_new_line
  echo "" | ${java_keytool} -list -v -keystore "/home/$(whoami)/.truststore" | grep -A7 "Alias name" | sed 's/Entry type: trustedCertEntry//' | sed '/Enter keystore password:/d' | sed '/^[[:space:]]*$/d' >> ${read_daily_report_file}
  print_new_line
  echo "KEYSTORE Tomcat SSL Certificates status for READ ${read_sc_ci}:" >> ${read_daily_report_file}
  print_new_line
  echo "" | ${java_keytool} -list -v -keystore "/home/$(whoami)/.keystore" | grep -A8 "Alias name" | sed 's/Entry type: trustedCertEntry//' | sed '/Enter keystore password:/d' | sed '/^[[:space:]]*$/d' >> ${read_daily_report_file}
  print_new_line
}

function get_system_loadaverage_stats() {
  sar_home="/var/log/sa"
  y=8
  z=1
  i=1
  echo "Time Day LoadAvg"
  #Stats for yesterday after 8:00 AM until 12 PM
  until [ $y -gt 12 ]; do
    la_yesterday_am=$(sar -q -f ${sar_home}/sa$(date +%d -d yesterday) -s 08:00:00 -e 23:56:00 | awk '{print $1, $2, $5, $6, $7}' | grep -i AM | egrep "*${y}:*:*" | awk -F " " '{ sum+=$4 } END {print sum}')
    div_yesterday_am=$(sar -q -f ${sar_home}/sa$(date +%d -d yesterday) -s 08:00:00 -e 23:56:00 | awk '{print $1, $2, $5, $6, $7}' | grep -i AM |egrep "*${y}:*:*" | awk '{print $2}' | wc -l)
    la_average_result_yesterday_am=$(echo "scale=3; ${la_yesterday_am}/${div_yesterday_am}" | bc)
    echo "${y}:00AM yesterday ${la_average_result_yesterday_am}" 
    ((y=y+1))
  done
  #Stats for yesterday from 12 PM to 00
  until [ $z -gt 12 ]; do
    la_yesterday_pm=$(sar -q -f ${sar_home}/sa$(date +%d -d yesterday) -s 08:00:00 -e 23:56:00 | awk '{print $1, $2, $5, $6, $7}' | grep -i PM | egrep "*${z}:*:*" | awk -F " " '{ sum+=$4 } END {print sum}')
    div_yesterday_pm=$(sar -q -f ${sar_home}/sa$(date +%d -d yesterday) -s 08:00:00 -e 23:56:00 | awk '{print $1, $2, $5, $6, $7}' | grep -i PM |egrep "*${z}:*:*" | awk '{print $2}' | wc -l)
    la_average_result_yesterday_pm=$(echo "scale=3; ${la_yesterday_pm}/${div_yesterday_pm}" | bc)

    echo "${z}:00PM yesterday ${la_average_result_yesterday_pm}"
    ((z=z+1))
  done
  until [ $i -gt 7 ]; do
    la_today_am=$(sar -q -f ${sar_home}/sa$(date +%d -d today) -e 07:56:00 | awk '{print $1, $5, $6, $7}' | egrep "*${i}:*:*" | awk -F " " '{ sum+=$4 } END {print sum}')
    div_today_am=$(sar -q -f ${sar_home}/sa$(date +%d -d today) -e 07:56:00 | awk '{print $1, $5, $6, $7}' | egrep "*${i}:*:*" | awk '{print $2}' | wc -l)
    la_average_result_today=$(echo "scale=3; ${la_today_am}/${div_today_am}" | bc)
    echo "${i}:00AM today ${la_average_result_today}" 
    ((i=i+1))
  done
}

function get_memory_stats() {
sar_home="/var/log/sa"
echo "Time Day mbmemfree mbmemused %memused mbbuffers mbcached mbcommit %commit"
for i in `seq 8 9`; do
  foo=$(sar -r -f ${sar_home}/sa$(date +%d -d yesterday) -s 0${i}:00:00 -e 0${i}:59:00 | grep -v -E 'kbmemfree|Linux' | sed '/^$/d' | grep "Average:" | awk '{ memfree=$2 / 1000; memused=$3 / 1000; buffers=$5 / 1000; cached=$6 / 1000; commit=$7 / 1000; print memfree, memused, $4"%", buffers, cached, commit, $8"%" }')
  echo "0${i}:00-0${i}:59 yesterday" ${foo}
done
for j in `seq 10 23`; do
  foo=$(sar -r -f ${sar_home}/sa$(date +%d -d yesterday) -s ${j}:00:00 -e ${j}:59:00 | grep -v -E 'kbmemfree|Linux' | sed '/^$/d' | grep "Average:" | awk '{ memfree=$2 / 1000; memused=$3 / 1000; buffers=$5 / 1000; cached=$6 / 1000; commit=$7 / 1000; print memfree, memused, $4"%", buffers, cached, commit, $8"%" }')
  echo "${j}:00-${j}:59 yesterday" ${foo}
done
for k in `seq 0 7`; do
  foo=$(sar -r -f ${sar_home}/sa$(date +%d -d today) -s 0${k}:00:00 -e 0${k}:59:00 | grep -v -E 'kbmemfree|Linux' | sed '/^$/d' | grep "Average:" | awk '{ memfree=$2 / 1000; memused=$3 / 1000; buffers=$5 / 1000; cached=$6 / 1000; commit=$7 / 1000; print memfree, memused, $4"%", buffers, cached, commit, $8"%" }')
  echo "0${k}:00-0${k}:59 today" ${foo}
done
}

function get_system_stats() {
  printf "Local disk usage:" >> ${read_daily_report_file}
  print_new_line
  df -Ph | sed s/%//g | awk '{ if($5 > 0) print $0;}' >> ${read_daily_report_file}
  print_new_line
  printf "CPU Load averages stats in the last 24hours:" >> ${read_daily_report_file}
  print_new_line
  printf "Note: Take into account that $(hostname) has $(grep -c ^processor /proc/cpuinfo) CPUs." >> ${read_daily_report_file}
  print_new_line
  #To add sar measurements for load averages here
  get_system_loadaverage_stats | column -t -c Time,Day,LoadAvg >> ${read_daily_report_file}
  print_new_line
  printf "Memory usage:" >> ${read_daily_report_file} 
  print_new_line
  free -h >> ${read_daily_report_file}
  print_new_line
  get_memory_stats | column -t -c Time," "," "," ",mbmemfree,mbmemused,%memused,mbbuffers,mbcached,mbcommit,%commit >> ${read_daily_report_file}
  print_new_line
}

function get_anbu_files() {
  find /nfs/${read_nfs_stage}/rvs/receive/anlagenbuchhaltung/ -maxdepth 1 -name *IB* -print >> ${read_daily_report_file}
  print_new_line
  echo "Summary of Anbu files backlog. To follow-up with the business based on a ticket after the 20th of the month:" >> ${read_daily_report_file}
  print_new_line
  find /nfs/${read_nfs_stage}/rvs/receive/anlagenbuchhaltung/anbu_retry/ -maxdepth 1 -name *IB* -print >> ${read_daily_report_file}
  print_new_line
  find /nfs/${read_nfs_stage}/rvs/receive/anlagenbuchhaltung/anbu_fail/ -maxdepth 1 -name *IB* -print >> ${read_daily_report_file}
  print_new_line
}

function get_oracle_status() {
  for i in "${list_of_dbs[@]}"; do
    get_db_username "${i}" ${catalina_context_conf}
    get_db_secret "${i}" ${catalina_context_conf}
    get_db_conn_string "${i}" ${catalina_context_conf}
#    if [[ $i == 'jdbc/read/etl/read_gui' ]]; then
#      READ_OUTPUT information is not kept in ${catalina_context_conf} file. Can't check the LOADER process atm securely.
#      read_loader_status=$(${java_home}/java -cp ${catalina_home}/lib/${oracle_driver}:${scripts_home}/${jdbc_driver} \ 
#      com.azsoftware.jdbc2csv.Main -u "jdbc:oracle:thin:${db_username}/\"${db_secret}\"@${db_conn_string}" \ 
#      "select * from loader_runs where start_date BETWEEN TRUNC(SYSDATE - 1) AND TRUNC(SYSDATE) - 1/86400")
      ${java_home}/java -cp ${catalina_home}/lib/${oracle_driver}:${scripts_home}/${jdbc_driver} com.azsoftware.jdbc2csv.Main -u "jdbc:oracle:thin:${db_username}/\"${db_secret}\"@${db_conn_string}" -f Oracle 'SELECT Substr(df.tablespace_name,1,20) "Tablespace Name", Substr(df.file_name,1,80) "File Name", Round(df.bytes/1024/1024,0) "Size MB", decode(e.used_bytes,NULL,0,Round(e.used_bytes/1024/1024,0)) "Used MB", decode(f.free_bytes,NULL,0,Round(f.free_bytes/1024/1024,0)) "Free MB", decode(e.used_bytes,NULL,0,Round((e.used_bytes/df.bytes)*100,0)) "% Used" FROM DBA_DATA_FILES DF, (SELECT file_id, sum(bytes) used_bytes FROM dba_extents GROUP by file_id) E, (SELECT sum(bytes) free_bytes, file_id FROM dba_free_space GROUP BY file_id) f WHERE e.file_id (+) = df.file_id AND df.file_id  = f.file_id (+) ORDER BY df.tablespace_name, df.file_name' -f Oracle | column -t -s ',' >> ${read_daily_report_file} 
#   fi
      print_new_line
  
      echo "READ-NG Reporting LOADER process status:" >> ${read_daily_report_file}
      ${java_home}/java -cp ${catalina_home}/lib/${oracle_driver}:${scripts_home}/${jdbc_driver} com.azsoftware.jdbc2csv.Main -u "jdbc:oracle:thin:${db_username}/\"${db_secret}\"@${db_conn_string}" -f Oracle 'select * from read_output.loader_runs order by end_date desc fetch next 5 rows only' -f Oracle | column -t -s ',' >> ${read_daily_report_file}
      print_new_line
  
      echo "READ_OUTPUT Materialized Views Refresh dates:" >> ${read_daily_report_file}
      ${java_home}/java -cp ${catalina_home}/lib/${oracle_driver}:${scripts_home}/${jdbc_driver} com.azsoftware.jdbc2csv.Main -u "jdbc:oracle:thin:${db_username}/\"${db_secret}\"@${db_conn_string}" -f Oracle "SELECT owner, name, last_refresh FROM ALL_MVIEW_REFRESH_TIMES where owner like'%OUTPUT%'" -f Oracle | column -t -s ',' >> ${read_daily_report_file}
  done
}

function get_batch_info() {
    curl -k https://localhost:8448/schedulers/list | ${scripts_home}/jq-linux64 '.[] | {name: .processor.name, description: .processor.description, nextRun: .nextExcutionTime, state: .processor.processStateTracker.processState, disabled: .disabled, cronExpression: .cronExpression}' >> ${read_daily_report_file}
}

function create_daily_report_file() {
  echo "READ-NG ${read_sc_ci} DAILY HEALTH CHECK REPORT" > ${read_daily_report_file}
  echo "---------------------------------------------------------" >> ${read_daily_report_file}
  summarize_apps_logs
  summarize_rvs_logs
  echo "Summary of Anbu files to be processed based on a ticket after the 20th of the month:" >> ${read_daily_report_file}
  print_new_line
  get_anbu_files
  echo "---------------------------------------------------------" >> ${read_daily_report_file}
  echo "Summary of READ-NG jobs status:" >> ${read_daily_report_file}
  print_new_line
  get_batch_info 
  echo "---------------------------------------------------------" >> ${read_daily_report_file}
  echo "Summary of Linux backend statistics:" >> ${read_daily_report_file}
  print_new_line
  get_system_stats
  echo "---------------------------------------------------------" >> ${read_daily_report_file}
  get_tomcat_ssl_status 
  echo "---------------------------------------------------------" >> ${read_daily_report_file}
#  echo ${read_loader_status} >> ${read_daily_report_file}
  echo "Summary of Oracle backend statistics:" >> ${read_daily_report_file}
  print_new_line
  get_oracle_status
}

create_daily_report_file
send_email
clear_read_daily_check_dir
