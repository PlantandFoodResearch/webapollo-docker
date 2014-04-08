FROM ubuntu:13.10
MAINTAINER Robert Syme <robsyme@gmail.com>

RUN sed 's/main$/main universe/' -i /etc/apt/sources.list
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -qq
RUN apt-get upgrade -qqy


# Install the basics
RUN apt-get install -qqy libpng12-dev wget unzip build-essential zlib1g-dev libpng12-dev zlib1g libpng12-0


# Install cpanm
ADD scripts/install_cpanm.pl /tmp/
RUN perl /tmp/install_cpanm.pl --sudo App::cpanminus && rm /tmp/install_cpanm.pl


# Install perl WebApollo dependencies
RUN apt-get install -qqy tomcat7 bioperl postgresql-9.1 vim tree
RUN cpanm YAML JSON JSON::XS PerlIO::gzip Heap::Simple Heap::Simple::XS Hash::Merge Bio::GFF3::LowLevel::Parser Digest::Crc32 Cache::Ref::FIFO Devel::Size File::Next


# Install blat
ADD scripts/install_blat.sh /tmp/
RUN bash /tmp/install_blat.sh && rm /tmp/install_blat.sh


# WebApollo Setup
RUN mkdir -p /usr/share/tomcat7/common/classes /usr/share/tomcat7/server/classes /usr/share/tomcat7/shared/classes
RUN echo "export CATALINA_OPTS='-Xms512m -Xmx1g -XX:+CMSClassUnloadingEnabled -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC -XX:MaxPermSize=256m'" >> /usr/share/tomcat7/bin/setenv.sh

ENV WEB_APOLLO_DIR /opt/webapollo
ENV WEB_APOLLO_DATA_DIR /data/webapollo/annotations
ENV JBROWSE_DATA_DIR /data/webapollo/jbrowse/data
ENV TOMCAT_LIB_DIR /usr/share/tomcat7/lib
ENV TOMCAT_CONF_DIR /etc/tomcat7
ENV TOMCAT_WEBAPPS_DIR /var/lib/tomcat7/webapps
ENV BLAT_DIR /usr/local/bin
ENV BLAT_TMP_DIR /data/webapollo/blat/tmp
ENV BLAT_DATABASE_DIR /data/webapollo/blat/db

ENV WEB_APOLLO_DB web_apollo_users
ENV WEB_APOLLO_DB_USER web_apollo_users_admin
ENV WEB_APOLLO_DB_PASS AdminDatabasePassword

RUN wget http://genomearchitect.org/webapollo/releases/WebApollo-2014-04-03.tgz && \
   tar -xzf WebApollo*.tgz -C /opt && \
   mv /opt/WebApollo-2014-04-03 $WEB_APOLLO_DIR && \
   rm ./*.tgz

ADD data/refseqs.fasta.gz /tmp/refseqs.fasta.gz
RUN cd /tmp && \
    gunzip refseqs.fasta.gz && \
    $WEB_APOLLO_DIR/tools/user/extract_seqids_from_fasta.pl -p Annotations- -i /tmp/refseqs.fasta -o /tmp/seqids.txt

ADD configuration/pg_hba.conf /etc/postgresql/9.1/main/pg_hba.conf

ENV PGPASSWORD ChangeThisPassword

RUN /etc/init.d/postgresql start && \
   su - postgres -c "psql -U postgres -d postgres -c \"alter user postgres with password '$PGPASSWORD';\"" && \
   psql --username postgres --host localhost --command "CREATE USER $WEB_APOLLO_DB_USER WITH PASSWORD '$WEB_APOLLO_DB_PASS' CREATEDB;" && \
   psql --username postgres --host localhost --command "CREATE DATABASE $WEB_APOLLO_DB OWNER $WEB_APOLLO_DB_USER;" && \
   psql --username $WEB_APOLLO_DB_USER --dbname $WEB_APOLLO_DB < $WEB_APOLLO_DIR/tools/user/user_database_postgresql.sql && \
   psql --username postgres --host localhost --dbname $WEB_APOLLO_DB --command "INSERT INTO users(username, password) VALUES('web_apollo_admin', 'web_apollo_admin');" && \
   psql --username postgres --host localhost --dbname $WEB_APOLLO_DB --command "INSERT INTO users(username, password) VALUES('rob', 'rob');" && \
   psql --username postgres --host localhost --dbname $WEB_APOLLO_DB --command "INSERT INTO users(username, password) VALUES('richard', 'richard');" && \
   psql --username postgres --host localhost --dbname $WEB_APOLLO_DB --command "INSERT INTO users(username, password) VALUES('james', 'james');" && \
   $WEB_APOLLO_DIR/tools/user/add_tracks.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -t /tmp/seqids.txt && \
   $WEB_APOLLO_DIR/tools/user/set_track_permissions.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -u web_apollo_admin -t /tmp/seqids.txt -a && \
   $WEB_APOLLO_DIR/tools/user/set_track_permissions.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -u rob -t /tmp/seqids.txt -a && \
   $WEB_APOLLO_DIR/tools/user/set_track_permissions.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -u james -t /tmp/seqids.txt -a && \
   $WEB_APOLLO_DIR/tools/user/set_track_permissions.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -u richard -t /tmp/seqids.txt -a

RUN cp $WEB_APOLLO_DIR/tomcat/custom-valves.jar $TOMCAT_LIB_DIR

RUN mkdir -p $TOMCAT_CONF_DIR
ADD configuration/server.xml $TOMCAT_CONF_DIR/server.xml
RUN cd $TOMCAT_WEBAPPS_DIR && \
   mkdir WebApollo && \
   cd WebApollo && \
   unzip $WEB_APOLLO_DIR/war/WebApollo.war

ADD configuration/config.xml $TOMCAT_WEBAPPS_DIR/WebApollo/config/
ADD configuration/blat_config.xml $TOMCAT_WEBAPPS_DIR/WebApollo/config/
ADD configuration/gff3_config.xml $TOMCAT_WEBAPPS_DIR/WebApollo/config/
ADD configuration/chado_config.xml $TOMCAT_WEBAPPS_DIR/WebApollo/config/

RUN mkdir -p $JBROWSE_DATA_DIR && \
   cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   chmod 755 bin/* && \
   ln -sf $JBROWSE_DATA_DIR data && \
   bin/prepare-refseqs.pl --fasta /tmp/refseqs.fasta && \
   bin/add-webapollo-plugin.pl -i data/trackList.json

# Static data generation
RUN mkdir -p $BLAT_TMP_DIR $BLAT_DATABASE_DIR && \
   cd $BLAT_DATABASE_DIR && \
   faToTwoBit /tmp/refseqs.fasta refseqs.2bit

EXPOSE 8080
ADD scripts/run.sh /usr/local/bin/run
VOLUME ["/data/webapollo"]
CMD ["/bin/sh", "-e", "/usr/local/bin/run"]
