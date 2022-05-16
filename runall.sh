#!/bin/bash

tag="$1"

if [ "$tag" == "all" ]; then
        XGame_997/AccessServer/AccessServer -l 4 -r 208699 &
        XGame_997/AccessServer/AccessServer -l 4 -r 208700 &
        XGame_997/AccessServer/AccessServer -l 4 -r 208701 &
        XGame_997/AccessServer/AccessServer -l 4 -r 208702 &
        XGame_997/AccessServer/AccessServer -l 4 -r 208703 &
        XGame_997/LoginServer/LoginServer -l 4 -r 65537 &
        XGame_997/LoginServer/LoginServer -l 4 -r 65538 &
        XGame_997/MoneyServer/MoneyServer -l 3 -r 262145 &
        XGame_997/MoneyServer/MoneyServer -l 3 -r 262146 &
        XGame_997/MutexServer/MutexServer -l 4 -r 131073 &
        XGame_997/UserInfoServer/UserInfoServer -l 4 -r 1048577 &
        XGame_997/NotifyServer/NotifyServer -l 4 -r 1114113 &
        XGame_997/PHPServer/PHPServer -l 4 -r 1769473 &
        XGame_997/TListServer/TListServer -l 4 -r 1900545 &
        XGame_997/StatisticServer/StatisticServer -l 4 -r 458753 &
        XGame_997/StatisticServer/StatisticServer -l 4 -r 458754 &
fi

XGame_997/LuaServer/LuaServer -l 4 -r 1703937  -g texas,beanlow &
XGame_997/LuaServer/LuaServer -l 4 -r 1703938  -g texas,beanmiddle &
XGame_997/LuaServer/LuaServer -l 4 -r 1703939  -g texas,beanhigh &

XGame_997/LuaServer/LuaServer -l 4 -r 1835009  -g 6+,beanlow &
XGame_997/LuaServer/LuaServer -l 4 -r 1835010  -g 6+,beanmiddle &
XGame_997/LuaServer/LuaServer -l 4 -r 1835011  -g 6+,beanhigh &

XGame_997/LuaServer/LuaServer -l 4 -r 2031617  -g Cowboy &
XGame_997/LuaServer/LuaServer -l 4 -r 2097153  -g DT &
XGame_997/LuaServer/LuaServer -l 4 -r 2293761 -g andarbahar &

XGame_997/LuaServer/LuaServer -l 4 -r 2228225 -g 34Rummy,low &
XGame_997/LuaServer/LuaServer -l 4 -r 2228226 -g 34Rummy,mid &
XGame_997/LuaServer/LuaServer -l 4 -r 2228227 -g 34Rummy,hig &

XGame_997/LuaServer/LuaServer -l 4 -r 2162689 -g 33TeenPatti,low &
XGame_997/LuaServer/LuaServer -l 4 -r 2162690 -g 33TeenPatti,mid &
XGame_997/LuaServer/LuaServer -l 4 -r 2162691 -g 33TeenPatti,hig &

XGame_997/RobotServer/RobotServer -l 4 -r 327681 &
