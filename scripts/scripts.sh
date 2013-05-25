#!/bin/bash

# Environment: (WARNING: override this in scripts-env.local.sh, NOT BELOW) -----------------
export GOORDER_DB_DRIVER='org.apache.derby.jdbc.ClientDriver'
export GOORDER_DB_URL='jdbc:derby://localhost:1527/goorder'
export GOORDER_DB_NAME='goorder'
export GOORDER_DB_USER='goorder'
export GOORDER_DB_PASS='goorder'
export GOORDER_DB_SCHEMA='goorder'
export GOORDER_DB_HOME="$HOME/goorder-database"

export GF_HOME=''
export GF_PORTBASE='8000'
export GF_ADMIN_PORT='8048'
export GF_DOMAIN_NAME='goorder'
export GF_ADMIN_USER='admin'
export GF_ADMIN_HOST='localhost'

export GOORDER_APP_ROOT_URL='http://localhost:8080/sgn/'

scripts="$(dirname "$0")"
if [ -f "$scripts/scripts-env.local.sh" ] ; then
  . "$scripts/scripts-env.local.sh"
else
  echo '#!/bin/bash' > "$scripts/scripts-env.local.sh"
fi

# Common Utilities --------------------------
utils="$scripts/utils"
db_lib="$GF_HOME/javadb/lib/derbyclient.jar"
asadmin="$GF_HOME/bin/asadmin"
asadmin_remote="$asadmin --user=$GF_ADMIN_USER --port=$GF_ADMIN_PORT --host=$GF_ADMIN_HOST "

function filter() {
  local template="$1"
  javac "$utils/FileEnvFilter.java"
  java -cp "$utils" FileEnvFilter "$template"
  local exit=$?
  rm "$utils/FileEnvFilter.class"
  exit $exit
}

function sql() {
  local url="$1"
  local user="$2"
  local pass="$3"
  javac "$utils/DbScriptRunner.java"
  java -cp "$utils":"$db_lib" DbScriptRunner "$url" "$user" "$pass"
  local exit=$?
  rm "$utils/DbScriptRunner.class"
  exit $exit
}

# Scripts --------------------------
function configure() {
  echo '# DO NOT EDIT THIS FILE, IT IS AUTO-GENERATED' > "$scripts/../goorder.properties"
  echo '# YOUR CHANGES WILL BE OVERWRITTEN' >> "$scripts/../goorder.properties"
  filter "$scripts/goorder-template.properties" >> "$scripts/../goorder.properties"
}
###

function db_create() {
  $asadmin start-database --dbhome "$GOORDER_DB_HOME" |grep start && \
    echo '' | sql "$GOORDER_DB_URL;create=true" "$GOORDER_DB_USER" "$GOORDER_DB_PASS"
}
function db_drop() {
  $asadmin stop-database && rm -rf "$GOORDER_DB_HOME/$GOORDER_DB_NAME"
}
function db_start() {
  $asadmin start-database --dbhome "$GOORDER_DB_HOME" |grep start
}
function db_stop() {
  $asadmin stop-database
}
###

function gf_create_domain() {
  $asadmin create-domain --user $GF_ADMIN_USER --nopassword true --portbase $GF_PORTBASE $GF_DOMAIN_NAME
}

function gf_delete_domain() {
  gf_stop_domain && \
    $asadmin delete-domain $GF_DOMAIN_NAME
}

function gf_start_domain() {
  $asadmin start-domain $GF_DOMAIN_NAME
}

function gf_stop_domain() {
  $asadmin stop-domain $GF_DOMAIN_NAME
}

function gf_configure_domain() {
  local pool_name='goorder-pool'
  local resource_name='jdbc/goorder'
  local realm_name='goorder-realm'

  $asadmin_remote create-jdbc-connection-pool \
    --datasourceclassname org.apache.derby.jdbc.ClientDataSource \
    --restype javax.sql.DataSource \
    --property User=$GOORDER_DB_USER:Password=$GOORDER_DB_PASS:DatabaseName=$GOORDER_DB_NAME \
    --ping true \
    $pool_name

  $asadmin_remote create-jdbc-connection-pool \
    --datasourceclassname org.apache.derby.jdbc.ClientDataSource \
    --restype javax.sql.DataSource \
    --property User=$GOORDER_DB_USER:Password=$GOORDER_DB_PASS:DatabaseName=$GOORDER_DB_NAME \
    --nontransactionalconnections \
    --pooling false \
    --wrapjdbcobjects false \
    ${pool_name}_raw

  $asadmin_remote create-jdbc-resource --connectionpoolid $pool_name $resource_name
  $asadmin_remote create-jdbc-resource --connectionpoolid ${pool_name}_raw ${resource_name}_raw

  $asadmin_remote create-auth-realm \
    --classname com.sun.enterprise.security.auth.realm.jdbc.JDBCRealm \
    --property datasource-jndi=$resource_name:user-table=APPUSER:user-name-column=USERNAME:password-column=PASSWORD:group-table=APPUSER_GROUP:group-name-column=GROUPNAME:digest-algorithm=SHA-256:encoding=Hex:jaas-context=jdbcRealm \
    $realm_name
}
###

function build() {
  cd "$scripts/.." && mvn clean install
}

# Run function:
eval $1