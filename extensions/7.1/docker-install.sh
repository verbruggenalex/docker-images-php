#!/usr/bin/env bash

set -e
set -ex

if [ -n "$DEV_DEPENDENCIES" ] || [ -n "$DEPENDENCIES" ]; then
    apt-get install -y --no-install-recommends $DEV_DEPENDENCIES $DEPENDENCIES
fi

if [ -n "$CONFIGURE_OPTIONS" ]; then
    docker-php-ext-configure $EXTENSION $CONFIGURE_OPTIONS
fi

if [ -n "$EXTENSION" ]; then
    docker-php-ext-install $EXTENSION
fi

if [ -n "$PECL_EXTENSION" ]; then
    pecl install $PECL_EXTENSION
fi

if [ -n "$DEV_DEPENDENCIES" ]; then
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $DEV_DEPENDENCIES
fi

if [ -n "$EXTENSION" ]; then
    # Let's perform a test
    php -m | grep $EXTENSION
    # Check that there is no output on STDERR when starting php:
    OUTPUT=`php -r "echo '';" 2>&1`
    [[ "$OUTPUT" == "" ]]
    # And now, let's disable it!
    rm -f /usr/local/etc/php/conf.d/docker-php-ext-$EXTENSION.ini
fi

if [ -n "$PECL_EXTENSION" ]; then
    # Let's perform a test
    PHP_EXTENSIONS="${PHP_EXT_NAME:-$PECL_EXTENSION}" php /usr/local/bin/generate_conf.php > /usr/local/etc/php/conf.d/testextension.ini
    php -m | grep "${PHP_EXT_PHP_NAME:-${PHP_EXT_NAME:-$PECL_EXTENSION}}"
    # Check that there is no output on STDERR when starting php:
    OUTPUT=`php -r "echo '';" 2>&1`
    [[ "$OUTPUT" == "" ]]
    rm /usr/local/etc/php/conf.d/testextension.ini
fi
