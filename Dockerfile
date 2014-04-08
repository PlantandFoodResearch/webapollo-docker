FROM ubuntu:13.10
MAINTAINER Robert Syme <robsyme@gmail.com>

RUN sed 's/main$/main universe/' -i /etc/apt/sources.list
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -qq
RUN apt-get upgrade -qqy


# Install the basics
RUN apt-get install -qqy libpng12-dev wget unzip build-essential zlib1g-dev libpng12-dev zlib1g libpng12-0


# Install cpanm
ADD install_cpanm.pl /tmp/
RUN perl /tmp/install_cpanm.pl --sudo App::cpanminus && rm /tmp/install_cpanm.pl


# Install perl WebApollo dependencies
RUN apt-get install -qqy tomcat7 bioperl postgresql-9.1 vim tree tomcat7-admin
RUN sed -i "s#</tomcat-users>##g" /etc/tomcat7/tomcat-users.xml; \
    echo '  <role rolename="manager-gui"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '  <role rolename="manager-script"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '  <role rolename="manager-jmx"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '  <role rolename="manager-status"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '  <role rolename="admin-gui"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '  <role rolename="admin-script"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '  <user username="admin" password="admin" roles="manager-gui, manager-script, manager-jmx, manager-status, admin-gui, admin-script"/>' >>  /etc/tomcat7/tomcat-users.xml; \
    echo '</tomcat-users>' >> /etc/tomcat7/tomcat-users.xml
RUN cpanm YAML JSON JSON::XS PerlIO::gzip Heap::Simple Heap::Simple::XS Hash::Merge Bio::GFF3::LowLevel::Parser Digest::Crc32 Cache::Ref::FIFO Devel::Size


# Install blat
ADD install_blat.sh /tmp/
RUN bash /tmp/install_blat.sh && rm /tmp/install_blat.sh


# WebApollo Setup
RUN mkdir -p /usr/share/tomcat7/common/classes /usr/share/tomcat7/server/classes /usr/share/tomcat7/shared/classes
RUN echo "export CATALINA_OPTS='-Xms512m -Xmx1g -XX:+CMSClassUnloadingEnabled -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC -XX:MaxPermSize=256m'" >> /usr/share/tomcat7/bin/setenv.sh

ENV WEB_APOLLO_DIR /opt/webapollo
ENV WEB_APOLLO_SAMPLE_DIR /opt/webapollo/sample_data
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

RUN echo "localhost:*:*:$WEB_APOLLO_DB_USER:$WEB_APOLLO_DB_PASS" > ~/.pgpass && chmod 600 ~/.pgpass
RUN wget http://icebox.lbl.gov/webapollo/releases/previous_releases/WebApollo-2013-11-22.tgz && \
   tar -xzf WebApollo*.tgz -C /opt && \
   mv /opt/WebApollo-2013-11-22 $WEB_APOLLO_DIR && \
   rm ./*.tgz

RUN mkdir $WEB_APOLLO_SAMPLE_DIR
WORKDIR /opt/webapollo/sample_data
RUN wget http://icebox.lbl.gov/webapollo/data/pyu_data.tgz && \
   tar -xzf pyu_data.tgz && \
   $WEB_APOLLO_DIR/tools/user/extract_seqids_from_fasta.pl -p Annotations- -i $WEB_APOLLO_SAMPLE_DIR/pyu_data/scf1117875582023.fa -o /tmp/seqids.txt

ADD configuration/pg_hba.conf /etc/postgresql/9.1/main/pg_hba.conf

ENV PGPASSWORD ChangeThisPassword

RUN /etc/init.d/postgresql start && \
   su - postgres -c "psql -U postgres -d postgres -c \"alter user postgres with password '$PGPASSWORD';\"" && \
   psql --username postgres --host localhost --command "CREATE USER $WEB_APOLLO_DB_USER WITH PASSWORD '$WEB_APOLLO_DB_PASS' CREATEDB;" && \
   psql --username postgres --host localhost --command "CREATE DATABASE $WEB_APOLLO_DB OWNER $WEB_APOLLO_DB_USER;" && \
   psql --username $WEB_APOLLO_DB_USER --dbname $WEB_APOLLO_DB < $WEB_APOLLO_DIR/tools/user/user_database_postgresql.sql && \
   psql --username postgres --host localhost --dbname $WEB_APOLLO_DB --command "INSERT INTO users(username, password) VALUES('web_apollo_admin', 'web_apollo_admin');" && \
   $WEB_APOLLO_DIR/tools/user/add_tracks.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -t /tmp/seqids.txt && \
   $WEB_APOLLO_DIR/tools/user/set_track_permissions.pl -D $WEB_APOLLO_DB -U $WEB_APOLLO_DB_USER -P $WEB_APOLLO_DB_PASS -u web_apollo_admin -t /tmp/seqids.txt -a

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
   bin/prepare-refseqs.pl --fasta $WEB_APOLLO_SAMPLE_DIR/pyu_data/scf1117875582023.fa && \
   bin/add-webapollo-plugin.pl -i data/trackList.json

# Static data generation
RUN mkdir -p $BLAT_TMP_DIR $BLAT_DATABASE_DIR && \
   cd $BLAT_DATABASE_DIR && \
   faToTwoBit $WEB_APOLLO_SAMPLE_DIR/pyu_data/scf1117875582023.fa pyu.2bit

RUN mkdir -p $WEB_APOLLO_SAMPLE_DIR/pyu_data/split_gff && \
   $WEB_APOLLO_DIR/tools/data/split_gff_by_source.pl -i $WEB_APOLLO_SAMPLE_DIR/pyu_data/scf1117875582023.gff -d $WEB_APOLLO_SAMPLE_DIR/pyu_data/split_gff


# Load gene/transcript/exon/CDS/polypeptide features
RUN cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   bin/flatfile-to-json.pl \
   --gff $WEB_APOLLO_SAMPLE_DIR/pyu_data/split_gff/maker.gff \
   --arrowheadClass trellis-arrowhead \
   --getSubfeatures \
   --subfeatureClasses '{"wholeCDS": null, "CDS":"brightgreen-80pct", "UTR": "darkgreen-60pct", "exon":"container-100pct"}' \
   --cssClass container-16px --type mRNA --trackLabel maker


# Load match/match_part features
RUN cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   bin/flatfile-to-json.pl \
   --gff $WEB_APOLLO_SAMPLE_DIR/pyu_data/split_gff/blastn.gff \
   --arrowheadClass webapollo-arrowhead --getSubfeatures \
   --subfeatureClasses '{"match_part": "darkblue-80pct"}' \
   --cssClass container-10px --trackLabel blastn

RUN cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   for i in $(ls $WEB_APOLLO_SAMPLE_DIR/pyu_data/split_gff/*.gff | grep -v maker); do \
      echo $i \
      j=$(basename $i .gff) \
      echo "Processing $j" \
      bin/flatfile-to-json.pl --gff $i --arrowheadClass webapollo-arrowhead --getSubfeatures --subfeatureClasses "{\"match_part\": \"darkblue-80pct\"}" --cssClass container-10px --trackLabel $j; \
   done

RUN cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   bin/generate-names.pl

RUN cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   mkdir data/bam && \
   cp $WEB_APOLLO_SAMPLE_DIR/pyu_data/*.bam* data/bam && \
   bin/add-bam-track.pl --bam_url bam/simulated-sorted.bam --label simulated_bam --key "simulated BAM"

RUN cd $TOMCAT_WEBAPPS_DIR/WebApollo/jbrowse && \
   mkdir data/bigwig && \
   cp $WEB_APOLLO_SAMPLE_DIR/pyu_data/*.bw data/bigwig && \
   bin/add-bw-track.pl --bw_url bigwig/simulated-sorted.coverage.bw --label simulated_bw --key "simulated BigWig"


EXPOSE 8080
ADD ./run.sh /usr/local/bin/run
VOLUME ["/data/webapollo"]
CMD ["/bin/sh", "-e", "/usr/local/bin/run"]
