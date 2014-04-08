NAME=tomcat7
export CATALINA_HOME=/usr/share/$NAME
export CATALINA_BASE=/var/lib/$NAME
export CATALINA_TMPDIR=/tmp/tomcat7-$NAME-tmp
export JAVA_HOME=/usr/lib/jvm/default-java
export JAVA_OPTS="$JAVA_OPTS -Djava.net.preferIPv4Stack=true"

rm -rf $CATALINA_TMPDIR
mkdir -p $CATALINA_TMPDIR

service postgresql start
/usr/share/tomcat7/bin/catalina.sh run
