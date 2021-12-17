//use global;
db.rank_history_mostwin_round.createIndex({ "gameid" : -1, "profit" : -1});
db.rank_history_mostwin_today.createIndex({ "gameid" : -1, "profit" : -1});
db.rank_most_win_round.createIndex({ "gameid" : -1, "zero_uptime" : -1, "profit" : -1 });
db.rank_most_win_today.createIndex({ "gameid" : -1, "zero_uptime" : -1, "profit" : -1 });
