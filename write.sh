trap 'onCtrlC' INT

function onCtrlC () {
        exit 0
}

while true
do
        { echo -ne "HTTP/1.0 200 OK\r\n\r\n"; } | nc -vl 39002 > .pushnclogs
        git pull origin main
        git commit . -m "update at `date +%m-%d-%H%M%S`"
        git push origin main
done