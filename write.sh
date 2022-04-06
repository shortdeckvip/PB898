trap 'onCtrlC' INT

function onCtrlC () {
        exit 0
}

requrl=https://web.wgnice.com/api/dc/bot.php
keyword="/"
while true
do
        used=`df -h | grep -w $keyword | awk '{print $5}' | sed 's/%//g'`
        if [ ${used} -gt 80 ]; then
                msg="PB disk has used ${used} and is grater than 80%"
                curl -G --data-urlencode "cli=0" --data-urlencode "sign=56d70103d4e6100d33cee37b7175ad98" --data-urlencode "msg=$msg" $requrl
                echo ${msg}
                sleep 300
        else
                echo "used ${used}"
        fi
        sleep 5
done