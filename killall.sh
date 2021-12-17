tag="$1"

if [ "$tag" == "all" ]; then
	../tools/redis/redis-cli --no-auth-warning -u "redis://Ch1904@redis.poker.game:5000/0" DEL ONLINE
	kill `ps x | grep "Server" | grep -v "grep" |  awk '{print $1}' | sort -r`
elif [ "$tag" == "game" ]; then
	kill `ps x | grep "LuaServer" | grep -v "grep" | awk '{print $1}' | sort -r`
	kill `ps x | grep "RobotServer" | grep -v "grep" | awk '{print $1}' | sort -r`
elif [ "$tag" == "update" ]; then
	kill -10 `ps x | grep "LuaServer" | grep -v "grep" | awk '{print $1}' | sort -r`
	kill -10 `ps x | grep "RobotServer" | grep -v "grep" | awk '{print $1}' | sort -r`
	kill -10 `ps x | grep "TListServer" | grep -v "grep" | awk '{print $1}' | sort -r`
fi
