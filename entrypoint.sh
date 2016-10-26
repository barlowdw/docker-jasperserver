#!/bin/bash
set -e

# wait upto 30 seconds for the database to start before connecting
/wait-for-it.sh $DB_HOST:$DB_PORT -t 30

# check if we need to bootstrap the JasperServer
if [ ! -d "$CATALINA_HOME/webapps/jasperserver" ]; then
    pushd /usr/src/jasperreports-server/buildomatic

    # only works for Postgres or MySQL
    cp sample_conf/${DB_TYPE}_master.properties default_master.properties
    sed -i -e "s|^appServerDir.*$|appServerDir = $CATALINA_HOME|g; s|^dbHost.*$|dbHost=$DB_HOST|g; s|^\# dbPort.*$|dbPort=$DB_PORT|g; s|^dbUsername.*$|dbUsername=$DB_USER|g; s|^dbPassword.*$|dbPassword=$DB_PASSWORD|g; s|^\# js\.dbName.*$|js\.dbName=$DB_NAME|g" default_master.properties

    # ENable SSL for postgres
    if [ "$DB_TYPE" == "postgresql" ]; then
        sed -i -e '/\# webAppNamePro = jasperserver-pro/a \\njs\.jdbcUrl\=jdbc\:postgresql\:\/\/\$\{dbHost\}\:\$\{dbPort\}\/\$\{js\.dbName\}\?ssl\=true\&sslfactory\=org\.postgresql\.ssl\.NonValidatingFactory' default_master.properties
    fi

    # run the minimum bootstrap script to initial the JasperServer
    ./js-ant create-js-db || true
    ./js-ant init-js-db-ce
    ./js-ant import-minimal-ce
    ./js-ant deploy-webapp-ce

    # escape & in XML with &amp;
    if [ "$DB_TYPE" == "postgresql" ]; then
        sed -i -e 's/ssl\=true\&sslfactory\=org\.postgresql\.ssl\.NonValidatingFactory/ssl\=true\&amp\;sslfactory\=org\.postgresql\.ssl\.NonValidatingFactory/g' $CATALINA_HOME/webapps/jasperserver/META-INF/context.xml
    fi

    # import any export zip files from another JasperServer

    shopt -s nullglob # handle case if no zip files found

    IMPORT_FILES=/jasperserver-import/*.zip
    for f in $IMPORT_FILES
    do
      echo "Importing $f..."
      ./js-import.sh --input-zip $f
    done


    popd
fi

# run Tomcat to start JasperServer webapp
catalina.sh run

