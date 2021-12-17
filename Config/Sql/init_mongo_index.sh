#!/bin/bash

# ########################
# MongoDB 索引
# ########################

MONGO=$1
HOST=$2
USER=$3
PASS=$4
AUTHDB=$5
ACCOUNTSDB=$6
WALLETDB=$7

${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${ACCOUNTSDB} accounts.js 
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${WALLETDB} wallet.js
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${ACCOUNTSDB} --eval "db.adminCommand({enablesharding:'"${ACCOUNTSDB}"'})"
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${ACCOUNTSDB} --eval "db.adminCommand({shardCollection:'"${ACCOUNTSDB}".account', key: {accountid:'hashed'}})"
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${ACCOUNTSDB} --eval "db.adminCommand({shardCollection:'"${ACCOUNTSDB}".money', key: {uid:'hashed'}})"
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${ACCOUNTSDB} --eval "db.adminCommand({shardCollection:'"${ACCOUNTSDB}".user', key: {uid:'hashed'}})"
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${WALLETDB} --eval "db.adminCommand({enablesharding:'"${WALLETDB}"'})"
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${WALLETDB} --eval "db.adminCommand({shardCollection:'"${WALLETDB}".order', key: {uid:'hashed'}})"
${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/${WALLETDB} --eval "db.adminCommand({shardCollection:'"${WALLETDB}".result', key: {serverid:'hashed'}})"
#${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/payments payments.js
#${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/activities activities.js
#${MONGO} -u ${USER} -p ${PASS} --authenticationDatabase ${AUTHDB} ${HOST}/statistic statistic.js
