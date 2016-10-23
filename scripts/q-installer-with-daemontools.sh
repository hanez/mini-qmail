#!/usr/bin/env sh

set -e

QMAIL_HOME="/var/qmail"
QMAIL_LOG_DIR="/var/log/qmail"
QMAIL_DL_URL="http://www.qmail.org/netqmail-1.06.tar.gz"
UCSPI_DL_URL="http://cr.yp.to/ucspi-tcp/ucspi-tcp-0.88.tar.gz"
DAEMONTOOLS_DL_URL="http://cr.yp.to/daemontools/daemontools-0.76.tar.gz"


## QMAIL INSTALL BASED ON LWQ ##
mkdir /usr/src ${QMAIL_HOME} && cd /usr/src
curl ${QMAIL_DL_URL} -o netqmail-1.06.tar.gz
tar zxf netqmail-1.06.tar.gz
cd netqmail-1.06

adduser qmaild -g nofiles -h ${QMAIL_HOME} -s /sbin/nologin -D
adduser alias -g nofiles -h ${QMAIL_HOME}/alias -s /sbin/nologin -D
adduser qmaill -g nofiles -h ${QMAIL_HOME} -s /sbin/nologin -D
adduser qmailp -g nofiles -h ${QMAIL_HOME} -s /sbin/nologin -D
addgroup qmail
adduser qmailq -g qmail -h ${QMAIL_HOME} -s /sbin/nologin -D
adduser qmailr -g qmail -h ${QMAIL_HOME} -s /sbin/nologin -D
adduser qmails -g qmail -h ${QMAIL_HOME} -s /sbin/nologin -D

make setup check

cd /usr/src/
curl ${UCSPI_DL_URL} -o ucspi-tcp-0.88.tar.gz
tar zxf ucspi-tcp-0.88.tar.gz
cd ucspi-tcp-0.88/
patch < /usr/src/netqmail-1.06/other-patches/ucspi-tcp-0.88.errno.patch
make && make setup check

cd /usr/src
curl ${DAEMONTOOLS_DL_URL} -o daemontools-0.76.tar.gz
mkdir /package
mv daemontools-0.76.tar.gz /package/
cd /package/
tar xvfz daemontools-0.76.tar.gz
rm -f daemontools-0.76.tar.gz
cd admin/daemontools-0.76/src
patch < /usr/src/netqmail-1.06/other-patches/daemontools-0.76.errno.patch
cd /package/admin/daemontools-0.76/
package/install

cat > ${QMAIL_HOME}/rc <<EOF
#!/bin/sh

# Using stdout for logging
# Using control/defaultdelivery from qmail-local to deliver messages by default

exec env - PATH="${QMAIL_HOME}/bin:\$PATH" \
qmail-start "\`cat ${QMAIL_HOME}/control/defaultdelivery\`"
EOF

chmod 755 ${QMAIL_HOME}/rc
mkdir ${QMAIL_LOG_DIR}
echo "./Maildir" > ${QMAIL_HOME}/control/defaultdelivery
echo "mx01.domain.local" > ${QMAIL_HOME}/control/me
echo "mx01.domain.local" > ${QMAIL_HOME}/control/locals
echo "mx01.domain.local" > ${QMAIL_HOME}/control/rcpthosts
echo "100" > ${QMAIL_HOME}/control/concurrencyincoming
chmod 644 ${QMAIL_HOME}/control/concurrencyincoming


cat > /var/qmail/bin/qmailctl <<EOF
#!/bin/sh

# description: the qmail MTA

PATH=/var/qmail/bin:/bin:/usr/bin:/usr/local/bin:/usr/local/sbin
export PATH

QMAILDUID=\`id -u qmaild\`
NOFILESGID=\`id -g qmaild\`

case \$1 in
  start)
    echo "Starting qmail"
    if svok /service/qmail-send ; then
      svc -u /service/qmail-send /service/qmail-send/log
    else
      echo "qmail-send supervise not running"
    fi
    if svok /service/qmail-smtpd ; then
      svc -u /service/qmail-smtpd /service/qmail-smtpd/log
    else
      echo "qmail-smtpd supervise not running"
    fi
    if [ -d /var/lock/subsys ]; then
      touch /var/lock/subsys/qmail
    fi
    ;;
  stop)
    echo "Stopping qmail..."
    echo "  qmail-smtpd"
    svc -d /service/qmail-smtpd /service/qmail-smtpd/log
    echo "  qmail-send"
    svc -d /service/qmail-send /service/qmail-send/log
    if [ -f /var/lock/subsys/qmail ]; then
      rm /var/lock/subsys/qmail
    fi
    ;;
  stat)
    svstat /service/qmail-send
    svstat /service/qmail-send/log
    svstat /service/qmail-smtpd
    svstat /service/qmail-smtpd/log
    qmail-qstat
    ;;
  doqueue|alrm|flush)
    echo "Flushing timeout table and sending ALRM signal to qmail-send."
    /var/qmail/bin/qmail-tcpok
    svc -a /service/qmail-send
    ;;
  queue)
    qmail-qstat
    qmail-qread
    ;;
  reload|hup)
    echo "Sending HUP signal to qmail-send."
    svc -h /service/qmail-send
    ;;
  pause)
    echo "Pausing qmail-send"
    svc -p /service/qmail-send
    echo "Pausing qmail-smtpd"
    svc -p /service/qmail-smtpd
    ;;
  cont)
    echo "Continuing qmail-send"
    svc -c /service/qmail-send
    echo "Continuing qmail-smtpd"
    svc -c /service/qmail-smtpd
    ;;
  restart)
    echo "Restarting qmail:"
    echo "* Stopping qmail-smtpd."
    svc -d /service/qmail-smtpd /service/qmail-smtpd/log
    echo "* Sending qmail-send SIGTERM and restarting."
    svc -t /service/qmail-send /service/qmail-send/log
    echo "* Restarting qmail-smtpd."
    svc -u /service/qmail-smtpd /service/qmail-smtpd/log
    ;;
  cdb)
    tcprules /etc/tcp.smtp.cdb /etc/tcp.smtp.tmp < /etc/tcp.smtp
    chmod 644 /etc/tcp.smtp.cdb
    echo "Reloaded /etc/tcp.smtp."
    ;;
  help)
    cat <<HELP
   stop -- stops mail service (smtp connections refused, nothing goes out)
  start -- starts mail service (smtp connection accepted, mail can go out)
  pause -- temporarily stops mail service (connections accepted, nothing leaves)
   cont -- continues paused mail service
   stat -- displays status of mail service
    cdb -- rebuild the tcpserver cdb file for smtp
restart -- stops and restarts smtp, sends qmail-send a TERM & restarts it
doqueue -- schedules queued messages for immediate delivery
 reload -- sends qmail-send HUP, rereading locals and virtualdomains
  queue -- shows status of queue
   alrm -- same as doqueue
  flush -- same as doqueue
    hup -- same as reload
HELP
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart|doqueue|flush|reload|stat|pause|cont|cdb|queue|help}"
    exit 1
    ;;
esac

exit 0
EOF

chmod 755 ${QMAIL_HOME}/bin/qmailctl
ln -s ${QMAIL_HOME}/bin/qmailctl /usr/bin

mkdir -p ${QMAIL_HOME}/supervise/qmail-send
mkdir -p ${QMAIL_HOME}/supervise/qmail-smtpd
mkdir -p ${QMAIL_HOME}/supervise/qmail-send/log
mkdir -p ${QMAIL_HOME}/supervise/qmail-smtpd/log

cat > ${QMAIL_HOME}/supervise/qmail-send/run <<EOF
#!/bin/sh
exec ${QMAIL_HOME}/rc
EOF

cat > ${QMAIL_HOME}/supervise/qmail-send/log/run <<EOF
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog t ${QMAIL_LOG_DIR}
EOF

cat > ${QMAIL_HOME}/supervise/qmail-smtpd/run <<EOF
#!/bin/sh

QMAILDUID=\`id -u qmaild\`
NOFILESGID=\`id -g qmaild\`
MAXSMTPD=\`cat ${QMAIL_HOME}/control/concurrencyincoming\`
LOCAL=\`head -1 ${QMAIL_HOME}/control/me\`

if [ -z "\$QMAILDUID" -o -z "\$NOFILESGID" -o -z "\$MAXSMTPD" -o -z "\$LOCAL" ]; then
    echo QMAILDUID, NOFILESGID, MAXSMTPD, or LOCAL is unset in
    echo ${QMAIL_HOME}/supervise/qmail-smtpd/run
    exit 1
fi

if [ ! -f ${QMAIL_HOME}/control/rcpthosts ]; then
    echo "No ${QMAIL_HOME}/control/rcpthosts!"
    echo "Refusing to start SMTP listener because it'll create an open relay"
    exit 1
fi
exec /usr/local/bin/tcpserver -v -R -l "\$LOCAL" -x /etc/tcp.smtp.cdb -c "\$MAXSMTPD" \
-u "\$QMAILDUID" -g "\$NOFILESGID" 0 smtp ${QMAIL_HOME}/bin/qmail-smtpd 2>&1
EOF


cat > ${QMAIL_HOME}/supervise/qmail-smtpd/log/run <<EOF
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog t ${QMAIL_LOG_DIR}/smtpd
EOF

chmod 755 ${QMAIL_HOME}/supervise/qmail-send/run
chmod 755 ${QMAIL_HOME}/supervise/qmail-send/log/run
chmod 755 ${QMAIL_HOME}/supervise/qmail-smtpd/run
chmod 755 ${QMAIL_HOME}/supervise/qmail-smtpd/log/run

mkdir -p /var/log/qmail/smtpd
chown qmaill /var/log/qmail /var/log/qmail/smtpd

ln -s /var/qmail/supervise/qmail-send /var/qmail/supervise/qmail-smtpd /service

cat > /etc/tcp.smtp <<EOF
127.:allow,RELAYCLIENT=""
172.17.:allow,RELAYCLIENT=""
EOF
tcprules /etc/tcp.smtp.cdb /etc/tcp.smtp.tmp < /etc/tcp.smtp
chmod 644 /etc/tcp.smtp.cdb