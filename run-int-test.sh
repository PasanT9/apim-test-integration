#!/bin/bash
#----------------------------------------------------------------------------
#  Copyright (c) 2020 WSO2, Inc. http://www.wso2.org
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#----------------------------------------------------------------------------
set -o xtrace; set -e

TESTGRID_DIR=/opt/testgrid/workspace
INFRA_JSON='infra.json'

PRODUCT_REPOSITORY=$1
PRODUCT_REPOSITORY_BRANCH=$2
PRODUCT_NAME=$3
PRODUCT_VERSION=$4
GIT_USER=$5
GIT_PASS=$6
TEST_MODE=$7
TEST_GROUP=$8
PRODUCT_REPOSITORY_NAME=$(echo $PRODUCT_REPOSITORY | rev | cut -d'/' -f1 | rev | cut -d'.' -f1)
PRODUCT_REPOSITORY_PACK_DIR="$TESTGRID_DIR/$PRODUCT_REPOSITORY_NAME/modules/distribution/product/target"
INT_TEST_MODULE_DIR="$TESTGRID_DIR/$PRODUCT_REPOSITORY_NAME/modules/integration"

# CloudFormation properties
CFN_PROP_FILE="${TESTGRID_DIR}/cfn-props.properties"

JDK_TYPE=$(grep -w "JDK_TYPE" ${CFN_PROP_FILE} | cut -d"=" -f2)
DB_TYPE=$(grep -w "DB_TYPE" ${CFN_PROP_FILE} | cut -d"=" -f2)
if [ "$DB_TYPE" = "oracle-se2-cdb" ]; then
    export DB_TYPE="oracle-se2"
fi
PRODUCT_PACK_NAME=$(grep -w "REMOTE_PACK_NAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_VERSION=$(grep -w "CF_DB_VERSION" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_PASSWORD=$(grep -w "CF_DB_PASSWORD" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_USERNAME=$(grep -w "CF_DB_USERNAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_HOST=$(grep -w "CF_DB_HOST" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_PORT=$(grep -w "CF_DB_PORT" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_NAME=$(grep -w "SID" ${CFN_PROP_FILE} | cut -d"=" -f2)

function log_info(){
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
}

function log_error(){
    echo "[ERROR][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
    exit 1
}

function install_jdk(){
    jdk_name=$1

    mkdir -p /opt/${jdk_name}
    jdk_file=$(jq -r '.jdk[] | select ( .name == '\"${jdk_name}\"') | .file_name' ${INFRA_JSON})
    wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdk/$jdk_file.tar.gz
    tar -xzf "$jdk_file.tar.gz" -C /opt/${jdk_name} --strip-component=1

    export JAVA_HOME=/opt/${jdk_name}
    echo $JAVA_HOME
}

function export_db_params(){
    db_name=$1

    export SHARED_DATABASE_DRIVER=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .driver' ${INFRA_JSON})
    export SHARED_DATABASE_URL=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2AM_COMMON_DB") | .url' ${INFRA_JSON})
    export SHARED_DATABASE_USERNAME=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2AM_COMMON_DB") | .username' ${INFRA_JSON})
    export SHARED_DATABASE_PASSWORD=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2AM_COMMON_DB") | .password' ${INFRA_JSON})
    export SHARED_DATABASE_VALIDATION_QUERY=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .validation_query' ${INFRA_JSON})
    
    export API_MANAGER_DATABASE_DRIVER=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .driver' ${INFRA_JSON})
    export API_MANAGER_DATABASE_URL=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2AM_APIMGT_DB") | .url' ${INFRA_JSON})
    export API_MANAGER_DATABASE_USERNAME=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2AM_APIMGT_DB") | .username' ${INFRA_JSON})
    export API_MANAGER_DATABASE_PASSWORD=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2AM_APIMGT_DB") | .password' ${INFRA_JSON})
    export API_MANAGER_DATABASE_VALIDATION_QUERY=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .validation_query' ${INFRA_JSON})
}

source /etc/environment

log_info "Clone Product repository"

log_info "Exporting JDK"
install_jdk ${JDK_TYPE}
if [ -n "$TEST_GROUP" ];
then
    log_info "Executing product test for ${TEST_GROUP}"
    export PRODUCT_APIM_TEST_GROUPS=${TEST_GROUP}
fi

# Build product apim
git clone https://github.com/wso2/product-apim --branch master --single-branch
cd product-apim
#mvn versions:set -DnewVersion=4.3.0
mvn clean install -Dmaven.test.skip=true -U

cd modules/distribution/product/target/
unzip wso2am-4.3.0-SNAPSHOT.zip
rm -rf wso2am-4.3.0-SNAPSHOT.zip


wget https://raw.githubusercontent.com/wso2/testgrid/5c8de3cedc932e1753bb2c5e47e7d3af2ff19535/jobs/intg-test-resources/infra.json

db_file=$(jq -r '.jdbc[] | select ( .name == '\"${DB_TYPE}\"') | .file_name' ${INFRA_JSON})
wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdbc/${db_file}.jar  -P /opt/testgrid/workspace/product-apim/modules/distribution/product/target/wso2am-4.3.0-SNAPSHOT/repository/components/lib/

sed -i "s|DB_HOST|${CF_DB_HOST}|g" ${INFRA_JSON}
sed -i "s|DB_USERNAME|${CF_DB_USERNAME}|g" ${INFRA_JSON}
sed -i "s|DB_PASSWORD|${CF_DB_PASSWORD}|g" ${INFRA_JSON}
sed -i "s|DB_NAME|${DB_NAME}|g" ${INFRA_JSON}

export_db_params ${DB_TYPE}


DB_ENGIN="${CF_DB_NAME}"
DB_ENGINE_VERSION="{$CF_DB_VERSION}"

WSO2_PRODUCT_VERSION="{$PRODUCT_VERSION}"

TESTGRID_DIR=/opt/testgrid/workspace
# CloudFormation properties


DB_SCRIPT_PATH=/opt/testgrid/workspace/product-apim/modules/distribution/product/target/wso2am-4.3.0-SNAPSHOT/dbscripts

function log_info(){
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
}
echo "This is DB_TYPE"
echo "${DB_TYPE}"

if [[ $DB_TYPE = "mysql" ]]; then
    log_info "Mysql DB is selected! Running mysql scripts for apim $WSO2_PRODUCT_VERSION"
    # create databases
    log_info "[Mysql] Droping Databases if exist"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -e "DROP DATABASE IF EXISTS WSO2AM_COMMON_DB"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -e "DROP DATABASE IF EXISTS WSO2AM_APIMGT_DB"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -e "DROP DATABASE IF EXISTS WSO2AM_STAT_DB"

    log_info "[Mysql] Creating Databases"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -e "CREATE DATABASE WSO2AM_COMMON_DB"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -e "CREATE DATABASE WSO2AM_APIMGT_DB"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -e "CREATE DATABASE WSO2AM_STAT_DB"

    log_info "[Mysql] Povisioning WSO2AM_APIMGT_DB"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -D WSO2AM_APIMGT_DB <  $DB_SCRIPT_PATH/apimgt/mysql.sql
    log_info "[Mysql] Povisioning WSO2AM_COMMON_DB"
    mysql -u &CF_DB_USERNAME -p&CF_DB_PASSWORD -h &CF_DB_HOST -P &CF_DB_PORT -D WSO2AM_COMMON_DB <  $DB_SCRIPT_PATH/mysql.sql

elif [[ $DB_TYPE = "postgres" ]]; then  

    log_info "Postgresql DB is selected! Running Postgresql scripts for apim $WSO2_PRODUCT_VERSION"
    export PGPASSWORD="&CF_DB_PASSWORD"
    
    log_info "[Postgres] Droping Databases if exist"
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d postgres -c "DROP DATABASE IF EXISTS \"WSO2AM_COMMON_DB\""
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d postgres -c "DROP DATABASE IF EXISTS \"WSO2AM_APIMGT_DB\""
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d postgres -c "DROP DATABASE IF EXISTS \"WSO2AM_STAT_DB\""

    log_info "[Postgres] Creating databases"
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d postgres -c "CREATE DATABASE \"WSO2AM_COMMON_DB\""
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d postgres -c "CREATE DATABASE \"WSO2AM_APIMGT_DB\""
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d postgres -c "CREATE DATABASE \"WSO2AM_STAT_DB\""

    log_info "[Postgres] Provisioning database WSO2AM_APIMGT_DB"
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d WSO2AM_APIMGT_DB -f $DB_SCRIPT_PATH/apimgt/postgresql.sql
    log_info "[Postgres] Provisioning database WSO2AM_COMMON_DB"
    psql -U &CF_DB_USERNAME -h &CF_DB_HOST -p &CF_DB_PORT -d WSO2AM_COMMON_DB -f $DB_SCRIPT_PATH/postgresql.sql

elif [[ $DB_TYPE =~ "oracle-se" ]]; then

    echo "printing shared_db"
    cat /opt/testgrid/workspace/dbscripts/oracle.sql

    echo "printing apimgt_db"
    cat /opt/testgrid/workspace/dbscripts/apimgt/oracle.sql

    # export ORACLE_HOME=/usr/lib/oracle/12.2/client64/
    # export PATH=$PATH:/usr/lib/oracle/12.2/client64/bin/
    # export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ORACLE_HOME/lib:$ORACLE_HOME

    # log_info "Oracle DB is selected! Running Oracle scripts for apim $WSO2_PRODUCT_VERSION"
    # Create users to the required DB
    # echo "DECLARE USER_EXIST INTEGER;"$'\n'"BEGIN SELECT COUNT(*) INTO USER_EXIST FROM dba_users WHERE username='WSO2AM_APIMGT_DB';"$'\n'"IF (USER_EXIST > 0) THEN EXECUTE IMMEDIATE 'DROP USER WSO2AM_APIMGT_DB CASCADE';"$'\n'"END IF;"$'\n'"END;"$'\n'"/" > apim_oracle_user.sql
    #echo "DECLARE USER_EXIST INTEGER;"$'\n'"BEGIN SELECT COUNT(*) INTO USER_EXIST FROM dba_users WHERE username='WSO2AM_COMMON_DB';"$'\n'"IF (USER_EXIST > 0) THEN EXECUTE IMMEDIATE 'DROP USER WSO2AM_COMMON_DB CASCADE';"$'\n'"END IF;"$'\n'"END;"$'\n'"/" >> apim_oracle_user.sql
    # echo "DECLARE USER_EXIST INTEGER;"$'\n'"BEGIN SELECT COUNT(*) INTO USER_EXIST FROM dba_users WHERE username='WSO2AM_STAT_DB';"$'\n'"IF (USER_EXIST > 0) THEN EXECUTE IMMEDIATE 'DROP USER WSO2AM_STAT_DB CASCADE';"$'\n'"END IF;"$'\n'"END;"$'\n'"/" >> apim_oracle_user.sql
    # echo "CREATE USER WSO2AM_COMMON_DB IDENTIFIED BY &CF_DB_PASSWORD;"$'\n'"GRANT CONNECT, RESOURCE, DBA TO WSO2AM_COMMON_DB;"$'\n'"GRANT UNLIMITED TABLESPACE TO WSO2AM_COMMON_DB;" >> apim_oracle_user.sql
    # echo "CREATE USER WSO2AM_APIMGT_DB IDENTIFIED BY &CF_DB_PASSWORD;"$'\n'"GRANT CONNECT, RESOURCE, DBA TO WSO2AM_APIMGT_DB;"$'\n'"GRANT UNLIMITED TABLESPACE TO WSO2AM_APIMGT_DB;" >> apim_oracle_user.sql
    # echo "CREATE USER WSO2AM_STAT_DB IDENTIFIED BY &CF_DB_PASSWORD;"$'\n'"GRANT CONNECT, RESOURCE, DBA TO WSO2AM_STAT_DB;"$'\n'"GRANT UNLIMITED TABLESPACE TO WSO2AM_STAT_DB;" >> apim_oracle_user.sql
    # echo "ALTER SYSTEM SET open_cursors = 3000 SCOPE=BOTH;">> apim_oracle_user.sql
    # # Create the tables
    # log_info "[Oracle] Creating Users"
    # echo exit | sqlplus64 '&CF_DB_USERNAME/&CF_DB_PASSWORD@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(Host=&CF_DB_HOST)(Port=&CF_DB_PORT))(CONNECT_DATA=(SID=WSO2AMDB)))' @apim_oracle_user.sql
    # log_info "[Oracle] Creating Tables"
    # echo exit | sqlplus64 'WSO2AM_COMMON_DB/&CF_DB_PASSWORD@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(Host=&CF_DB_HOST)(Port=&CF_DB_PORT))(CONNECT_DATA=(SID=WSO2AMDB)))' @$DB_SCRIPT_PATH/oracle.sql
    # echo exit | sqlplus64 'WSO2AM_APIMGT_DB/&CF_DB_PASSWORD@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(Host=&CF_DB_HOST)(Port=&CF_DB_PORT))(CONNECT_DATA=(SID=WSO2AMDB)))' @$DB_SCRIPT_PATH/apimgt/oracle.sql

elif [[ $DB_TYPE =~ "sqlserver-se" ]]; then
    log_info "SQL Server DB Engine is selected! Running MSSql scripts for apim $WSO2_PRODUCT_VERSION"

    log_info "[SQLServer] Droping Databases if exist"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "DROP DATABASE IF EXISTS WSO2AM_COMMON_DB"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "DROP DATABASE IF EXISTS WSO2AM_APIMGT_DB"

    log_info "[SQLServer] Creating Databases"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "CREATE DATABASE WSO2AM_COMMON_DB"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "CREATE DATABASE WSO2AM_APIMGT_DB"

    log_info "[SQLServer] Provisioning database WSO2AM_APIMGT_DB"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -d WSO2AM_APIMGT_DB -i $DB_SCRIPT_PATH/apimgt/mssql.sql
    log_info "[SQLServer] Provisioning database WSO2AM_COMMON_DB"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -d WSO2AM_COMMON_DB -i $DB_SCRIPT_PATH/mssql.sql
    log_info "[SQLServer] Tuning databases"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "ALTER DATABASE WSO2AM_APIMGT_DB  SET ALLOW_SNAPSHOT_ISOLATION ON"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "ALTER DATABASE WSO2AM_APIMGT_DB SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "ALTER DATABASE WSO2AM_COMMON_DB  SET ALLOW_SNAPSHOT_ISOLATION ON"
    sqlcmd -S &CF_DB_HOST -U &CF_DB_USERNAME -P &CF_DB_PASSWORD -Q "ALTER DATABASE WSO2AM_COMMON_DB SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE"

fi

zip -r wso2am-4.3.0-SNAPSHOT.zip wso2am-4.3.0-SNAPSHOT
rm -rf wso2am-4.3.0-SNAPSHOT
cd ../../../../
pwd


# Testing..............................................
log_info "install pack into local maven Repository"
mvn install:install-file -Dfile=/opt/testgrid/workspace/product-apim/modules/distribution/product/target/wso2am-4.3.0-SNAPSHOT.zip -DgroupId=org.wso2.am -DartifactId=wso2am -Dversion=4.3.0-SNAPSHOT -Dpackaging=zip
cd $INT_TEST_MODULE_DIR
rm -rf tests-integration/tests-backend/src/test/resources/testng.xml
curl -o tests-integration/tests-backend/src/test/resources/testng.xml https://raw.githubusercontent.com/PasanT9/apim-test-integration/4.3.0-copy/testng.xml
mvn clean install -fae -B -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn -Ptestgrid -DskipBenchMarkTest=true -Dhttp.keepAlive=false -DskipRestartTests=true -Dmaven.wagon.http.pool=false -U