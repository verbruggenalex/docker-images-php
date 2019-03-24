#!/usr/bin/env bash

set -xe

# Let's replace the "." by a "-" with some bash magic
export BRANCH_VARIANT=`echo "$VARIANT" | sed 's/\./-/g'`

# Let's build the "slim" image.
docker build -t verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} -f Dockerfile.${PHP_VERSION}.slim.${VARIANT} .

# Post build unit tests

# Let's check that the extensions can be built using the "ONBUILD" statement
docker build -t test/slim_onbuild --build-arg PHP_VERSION="${PHP_VERSION}" --build-arg BRANCH="$BRANCH" --build-arg BRANCH_VARIANT="$BRANCH_VARIANT" tests/slim_onbuild
# This should run ok (the sudo disable environment variables but call to composer proxy does not trigger PHP ini file regeneration)
docker run --rm test/slim_onbuild php -m | grep sockets
docker run --rm test/slim_onbuild php -m | grep xdebug
docker rmi test/slim_onbuild

# Post build unit tests
if [[ $VARIANT == cli* ]]; then CONTAINER_CWD=/usr/src/app; else CONTAINER_CWD=/var/www/html; fi
# Default user is 1000
RESULT=`docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} id -ur`
[[ "$RESULT" = "1000" ]]

# If mounted, default user has the id of the mount directory
mkdir user1999 && sudo chown 1999:1999 user1999
ls -al user1999
RESULT=`docker run --rm -v $(pwd)/user1999:$CONTAINER_CWD verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} id -ur`
[[ "$RESULT" = "1999" ]]
sudo rm -rf user1999

# and it also works for users with existing IDs in the container
sudo mkdir -p user33
sudo cp tests/apache/composer.json user33/
sudo chown -R 33:33 user33
ls -al user33
RESULT=`docker run --rm -v $(pwd)/user33:$CONTAINER_CWD verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} id -ur`
[[ "$RESULT" = "33" ]]
RESULT=`docker run --rm -v $(pwd)/user33:$CONTAINER_CWD verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} composer update -vvv`
sudo rm -rf user33

# Let's check that mbstring, mysqlnd and ftp are enabled by default (they are compiled in PHP)
docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -m | grep mbstring
docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -m | grep mysqlnd
docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -m | grep ftp
docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -m | grep PDO
docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -m | grep pdo_sqlite

if [[ $VARIANT == apache* ]]; then
    # Test if environment variables are passed to PHP
    DOCKER_CID=`docker run --rm -e MYVAR=foo -p "81:80" -d -v $(pwd):/var/www/html verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT}`

    # Let's wait for Apache to start
    sleep 5

    RESULT=`curl http://localhost:81/tests/test.php`
    [[ "$RESULT" = "foo" ]]
    docker stop $DOCKER_CID
fi

# Let's check that the access to cron will fail with a message
set +e
RESULT=`docker run --rm -e CRON_SCHEDULE_1="* * * * * * *" -e CRON_COMMAND_1="(>&1 echo "foobar")" verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} sleep 1 2>&1 | grep -o 'Cron is not available in this image'`
set -e
[[ "$RESULT" = "Cron is not available in this image" ]]

# Let's check that the configuration is loaded from the correct php.ini (development, production or imported in the image)
RESULT=`docker run --rm verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -i | grep error_reporting`
[[ "$RESULT" = "error_reporting => 32767 => 32767" ]]

RESULT=`docker run --rm -e TEMPLATE_PHP_INI=production verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -i | grep error_reporting`
[[ "$RESULT" = "error_reporting => 22527 => 22527" ]]

RESULT=`docker run --rm -v $(pwd)/tests/php.ini:/usr/local/etc/php/php.ini verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -i | grep error_reporting`
[[ "$RESULT" = "error_reporting => 24575 => 24575" ]]

RESULT=`docker run --rm -e PHP_INI_ERROR_REPORTING="E_ERROR | E_WARNING" verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -i | grep error_reporting`
[[ "$RESULT" = "error_reporting => 3 => 3" ]]

# Tests that environment variables with an equal sign are correctly handled
RESULT=`docker run --rm -e PHP_INI_SESSION__SAVE_PATH="tcp://localhost?auth=yourverycomplex\"passwordhere" verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -i | grep "session.save_path"`
[[ "$RESULT" = "session.save_path => tcp://localhost?auth=yourverycomplex\"passwordhere => tcp://localhost?auth=yourverycomplex\"passwordhere" ]]

# Tests that environment variables are passed to startup scripts when UID is set
RESULT=`docker run --rm -e FOO="bar" -e STARTUP_COMMAND_1="env" -e UID=0 verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} sleep 1 | grep "FOO"`
[[ "$RESULT" = "FOO=bar" ]]

# Tests that multi-commands are correctly executed  when UID is set
RESULT=`docker run --rm -e STARTUP_COMMAND_1="cd / && whoami" -e UID=0 verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} sleep 1`
[[ "$RESULT" = "root" ]]

# Tests that startup.sh is correctly executed
docker run --rm -v $PWD/tests/startup.sh:/etc/container/startup.sh verbral/php:${PHP_VERSION}-${BRANCH}-slim-${BRANCH_VARIANT} php -m | grep "startup.sh executed"

#################################
# Let's build the "fat" image
#################################
docker build -t verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} -f Dockerfile.${PHP_VERSION}.${VARIANT} .

# Let's check that the crons are actually sending logs in the right place
RESULT=`docker run --rm -e CRON_SCHEDULE_1="* * * * * * *" -e CRON_COMMAND_1="(>&1 echo "foobar")" verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} sleep 1 2>&1 | grep -oP 'msg=foobar' | head -n1`
[[ "$RESULT" = "msg=foobar" ]]

RESULT=`docker run --rm -e CRON_SCHEDULE_1="* * * * * * *" -e CRON_COMMAND_1="(>&2 echo "error")" verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} sleep 1 2>&1 | grep -oP 'msg=error' | head -n1`
[[ "$RESULT" = "msg=error" ]]

# Let's check that the cron with a user different from root is actually run.
RESULT=`docker run --rm -e CRON_SCHEDULE_1="* * * * * * *" -e CRON_COMMAND_1="whoami" -e CRON_USER_1="docker" verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} sleep 1 2>&1 | grep -oP 'msg=docker' | head -n1`
[[ "$RESULT" = "msg=docker" ]]

# Let's check that 2 commands split with a ; are run by the same user.
RESULT=`docker run --rm -e CRON_SCHEDULE_1="* * * * * * *" -e CRON_COMMAND_1="whoami;whoami" -e CRON_USER_1="docker" verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} sleep 1 2>&1 | grep -oP 'msg=docker' | wc -l`
[[ "$RESULT" -gt "1" ]]


# Let's check that mbstring cannot extension cannot be disabled
set +e
docker run --rm -e PHP_EXTENSION_MBSTRING=0 verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} php -i
[[ "$?" = "1" ]]
set -e

# Let's check that the "xdebug.remote_host" contains a value different from "no value"
docker run --rm -e PHP_EXTENSION_XDEBUG=1 verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} php -i | grep xdebug.remote_host| grep -v "no value"

# Tests that blackfire + xdebug will output an error
RESULT=`docker run --rm -e PHP_EXTENSION_XDEBUG=1 -e PHP_EXTENSION_BLACKFIRE=1 verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} php -v 2>&1 | grep 'WARNING: Both Blackfire and Xdebug are enabled. This is not recommended as the PHP engine may not behave as expected. You should strongly consider disabling Xdebug or Blackfire.'`
[[ "$RESULT" = "WARNING: Both Blackfire and Xdebug are enabled. This is not recommended as the PHP engine may not behave as expected. You should strongly consider disabling Xdebug or Blackfire." ]]

# Check that blackfire can be enabled
docker run --rm -e PHP_EXTENSION_BLACKFIRE=1 verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT} php -m | grep blackfire

# Let's check that the extensions are enabled when composer is run
docker build -t test/composer_with_gd --build-arg PHP_VERSION="${PHP_VERSION}" --build-arg BRANCH="$BRANCH" --build-arg BRANCH_VARIANT="$BRANCH_VARIANT" tests/composer

# This should run ok (the sudo disables environment variables but call to composer proxy does not trigger PHP ini file regeneration)
docker run --rm test/composer_with_gd sudo composer update
docker rmi test/composer_with_gd

#################################
# Let's build the "node" images
#################################
docker build -t verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT}-node8 -f Dockerfile.${PHP_VERSION}.${VARIANT}.node8 .
docker build -t verbral/php:${PHP_VERSION}-${BRANCH}-${BRANCH_VARIANT}-node10 -f Dockerfile.${PHP_VERSION}.${VARIANT}.node10 .

echo "Tests passed with success"
