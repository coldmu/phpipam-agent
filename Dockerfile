FROM php:7.2-apache
MAINTAINER COLDMU YANG

ENV PHPIPAM_AGENT_SOURCE https://github.com/phpipam/phpipam-agent

# Install required deb packages
RUN sed -i /etc/apt/sources.list -e 's/$/ non-free'/ && \
    apt-get update && apt-get -y upgrade && \
    rm /etc/apt/preferences.d/no-debian-php && \
    apt-get install -y libcurl4-gnutls-dev libgmp-dev libmcrypt-dev libfreetype6-dev libjpeg-dev libpng-dev libldap2-dev libsnmp-dev snmp-mibs-downloader iputils-ping && \
    apt-get install -y git cron libgmp-dev iputils-ping fping && \
    rm -rf /var/lib/apt/lists/*

# Configure apache and required PHP modules
RUN docker-php-ext-configure mysqli --with-mysqli=mysqlnd && \
    docker-php-ext-install mysqli && \
    docker-php-ext-configure gd --with-freetype-dir=/usr/include/freetype2 --with-png-dir=/usr/include --with-jpeg-dir=/usr/include && \
    docker-php-ext-install gd && \
    docker-php-ext-install curl && \
    docker-php-ext-install json && \
    docker-php-ext-install snmp && \
    docker-php-ext-install sockets && \
    docker-php-ext-install pdo_mysql && \
    docker-php-ext-install gettext && \
    ln -s /usr/include/$(uname -m)-linux-gnu/gmp.h /usr/include/gmp.h && \
    docker-php-ext-configure gmp --with-gmp=/usr/include/$(uname -m)-linux-gnu && \
    docker-php-ext-install gmp && \
    docker-php-ext-install pcntl && \
    docker-php-ext-configure ldap --with-libdir=lib/$(uname -m)-linux-gnu && \
    docker-php-ext-install ldap && \
    pecl install mcrypt-1.0.1 && \
    docker-php-ext-enable mcrypt && \
    echo ". /etc/environment" >> /etc/apache2/envvars && \
    a2enmod rewrite

COPY php.ini /usr/local/etc/php/

# Clone phpipam-agent sources
WORKDIR /opt/
RUN git clone ${PHPIPAM_AGENT_SOURCE}.git

WORKDIR /opt/phpipam-agent
# Use system environment variables into config.php
RUN cp config.dist.php config.php && \
    sed -i -e "s/\['key'\] = .*;/\['key'\] = getenv(\"PHPIPAM_AGENT_KEY\");/" \
    -e "s/\['pingpath'\] = .*;/\['pingpath'\] = \"\/usr\/bin\/fping\";/" \
    -e "s/\['db'\]\['host'\] = \"localhost\"/\['db'\]\['host'\] = getenv(\"MYSQL_ENV_MYSQL_HOST\") ?: \"mysql\"/" \
    -e "s/\['db'\]\['user'\] = \"phpipam\"/\['db'\]\['user'\] = getenv(\"MYSQL_ENV_MYSQL_USER\") ?: \"root\"/" \
    -e "s/\['db'\]\['pass'\] = \"phpipamadmin\"/\['db'\]\['pass'\] = getenv(\"MYSQL_ENV_MYSQL_PASSWORD\")/" \
    -e "s/\['db'\]\['name'\] = \"phpipam\"/\['db'\]\['name'\] = getenv(\"MYSQL_ENV_MYSQL_NAME\")/" \
    -e "s/\['db'\]\['port'\] = 3306;/\['db'\]\['port'\] = getenv(\"MYSQL_ENV_MYSQL_PORT\");\n\n\$password_file = getenv(\"MYSQL_ENV_MYSQL_PASSWORD_FILE\");\nif(file_exists(\$password_file))\n\$db\['db'\]\['pass'\] = preg_replace(\"\/\\\\s+\/\", \"\", file_get_contents(\$password_file));/" \
    config.php

COPY set_timezone /

# Setup crontab
ENV CRONTAB_FILE=/etc/cron.d/phpipam
RUN echo "*/15 * * * * /usr/local/bin/php /opt/phpipam-agent/index.php update > /proc/1/fd/1 2>/proc/1/fd/2" > ${CRONTAB_FILE} && \
    echo "*/15 * * * * /usr/local/bin/php /opt/phpipam-agent/index.php discover > /proc/1/fd/1 2>/proc/1/fd/2" >> ${CRONTAB_FILE} && \
    chmod 0644 ${CRONTAB_FILE} && \
    crontab ${CRONTAB_FILE}

CMD [ "sh", "-c", "printenv > /etc/environment && /set_timezone && cron -f " ]
