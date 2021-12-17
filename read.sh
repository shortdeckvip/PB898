trap 'onCtrlC' INT

function onCtrlC () {
        exit 0
}

requrl=https://web.wgnice.com/api/dc/bot.php
export PYTHONIOENCODING=utf8
while true
do
        { echo -ne "HTTP/1.0 200 OK\r\n\r\n"; } | nc -vl 39004 >> .pullnclogs
        msg=`cat .pullnclogs | grep "shortdeckvip" | python -c "import sys, json; print json.load(sys.stdin)['head_commit']['message']"`
        curl -G --data-urlencode "cli=0" --data-urlencode "sign=56d70103d4e6100d33cee37b7175ad98" --data-urlencode "msg=$msg" $requrl 
        : > .pullnclogs
        git checkout .
        git pull origin main
        sh killall.sh update
done
