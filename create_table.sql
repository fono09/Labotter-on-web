create table users (
	id		INTEGER PRIMARY KEY AUTOINCREMENT,
	twitter_id	INTEGER,
	screen_name	TEXT,
	access_token	TEXT,
	access_token_secret TEXT,
	inlabo		BOOLEAN
);
create table labostats (
	id		INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id		INTEGER,
	laboin		INTEGER,
	laborida	INTEGER
);

