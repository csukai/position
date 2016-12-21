###############################################################################
# Import only data required for trajectory generation from the MDC dataset
###############################################################################

DROP DATABASE IF EXISTS mdc;
CREATE DATABASE mdc;

USE mdc;

CREATE table gps(db_key INTEGER, time INTEGER, longitude decimal(16,12), latitude decimal(16,12), altitude decimal(16,5), speed decimal(16,5), speed_accuracy decimal(16,5), horizontal_dop decimal(16,5), horizontal_accuracy decimal(16,5), vertical_dop decimal(16,5), vertical_accuracy decimal(16,5), time_since_gps_boot NUMERIC);
CREATE table records(db_key INTEGER, userid INTEGER, time INTEGER, tz INTEGER, type VARCHAR(16));
CREATE table users(userid INTEGER, phonenumber VARCHAR(75), test_user CHAR);

ALTER TABLE gps ADD PRIMARY KEY (db_key);
ALTER TABLE records ADD PRIMARY KEY (db_key);

CREATE INDEX gpstime_idx ON gps(time);
CREATE INDEX recordstime_idx ON records(time);
CREATE INDEX recordstype_idx ON records(type);
CREATE INDEX recordsuserid_idx ON records(userid);

LOAD DATA INFILE '~/Data/Datasets/MDC/gps.csv' INTO TABLE gps;
LOAD DATA INFILE '~/Data/Datasets/MDC/unique_records.csv' INTO TABLE records;
LOAD DATA INFILE '~/Data/Datasets/MDC/users.csv' INTO TABLE users;

###############################################################################
# Export the 10 users we are interested in
###############################################################################

select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5927 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5927.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5948 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5948.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 6051 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_6051.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 6104 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_6104.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5938 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5938.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5947 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5947.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5966 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5966.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5976 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5976.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 5990 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_5990.csv' FIELDS TERMINATED BY ',';
select FROM_UNIXTIME(gps.time) as time, latitude, longitude, horizontal_accuracy as accuracy from gps left join records on gps.db_key = records.db_key where records.userid = 6109 order by gps.time asc into outfile '~/Data/Datasets/MDC/exported/RAW_6109.csv' FIELDS TERMINATED BY ',';

###############################################################################
# To convert the CSVs to YAML files, use one of these:
#
#   bin/thesis/datasets/trajectory_to_yaml --input_dir ~/Data/Datasets/MDC/exported/ --output_dir ~/Data/Datasets/MDC/yaml/ --output_prefix RawMDC
#   bin/thesis/datasets/trajectory_to_yaml --input_dir ~/Data/Datasets/MDC/exported/ --output_dir ~/Data/Datasets/MDC/yaml/ --output_prefix NoDupMDC --omit_duplicates
#   bin/thesis/datasets/trajectory_to_yaml --input_dir ~/Data/Datasets/MDC/exported/ --output_dir ~/Data/Datasets/MDC/yaml/ --output_prefix NoTruncMDC --omit_truncated
#   bin/thesis/datasets/trajectory_to_yaml --input_dir ~/Data/Datasets/MDC/exported/ --output_dir ~/Data/Datasets/MDC/yaml/ --output_prefix MDC --omit_duplicates --omit_truncated
###############################################################################

###############################################################################
# Import the Warwick dataset (datalog-and-cell-towers-2014-03-06.sql)
# NOTE: If you're using the same database, importing will overwrite the MDC's users table
###############################################################################

select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "1c" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_1c.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "1d" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_1d.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "6b" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_6b.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "6c" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_6c.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "08" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_08.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "24" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_24.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "61" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_61.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "85" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_85.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "87" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_87.csv' FIELDS TERMINATED BY ',';
select timestamp, latitude, longitude, horizontalAccuracy from points left join users on points.user_id = users.id where left(`key`, 2) = "95" order by timestamp asc into outfile '~/Data/Datasets/Warwick/exported/RAW_95.csv' FIELDS TERMINATED BY ',';

###############################################################################
# To convert the CSVs to YAML files:
#
#   bin/thesis/datasets/trajectory_to_yaml --input_dir ~/Data/Datasets/Warwick/exported/ --output_dir ~/Data/Datasets/Warwick/yaml/ --output_prefix War --omit_duplicates --omit_truncated
###############################################################################