case "$1" in
  start)
	echo -n "Starting $DAEMON: "
	touch $PIDFILE
	chown redis:redis $PIDFILE
	chmod 755 $RUNDIR

	if [ -n "$ULIMIT" ]
	then
		ulimit -n $ULIMIT
	fi

	if start-stop-daemon --start --quiet --umask 007 --pidfile $PIDFILE --chuid $REDIS_USER:$REDIS_USER --exec $DAEMON -- $DAEMON_ARGS
	then
		echo "$NAME."
	else
		echo "failed"
	fi
	;;
  stop)
	echo -n "Stopping $DESC: "
	if start-stop-daemon --stop --retry forever/TERM/1 --quiet --oknodo --pidfile $PIDFILE --exec $DAEMON
	then
		echo "$NAME."
	else
		echo "failed"
	fi
	rm -f $PIDFILE
	sleep 1
	;;

  restart|force-reload)
	${0} stop
	${0} start
	;;

  status)
	echo -n "$DESC is "
	if start-stop-daemon --stop --quiet --signal 0 --name ${NAME} --pidfile ${PIDFILE}
	then
		echo "running"
	else
		echo "not running"
		exit 1
	fi
	;;

  *)
	echo "Usage: /etc/init.d/$NAME {start|stop|restart|force-reload|status}" >&2
	exit 1
	;;
esac

exit 0
