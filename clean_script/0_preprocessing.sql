-- Step1: Preprocessing for Street
--- 1.1 Tranform streets data from SDOT
/* 
Tranform the street type from multilinestring to linestring

Pre: 
(table:street)
{	compkey int, 
	artclass int(0-5)"interstate_road", 
	geom multiplinestring:srid = 2926
	...
}

Post: 
(view:yun_processed_streets)
{	id int, 
	artclass int(0-5)"interstate_road",
	geom linestring
}
*/
CREATE OR REPLACE VIEW yun_processed_streets AS 
	SELECT 
		compkey as id, 
		ST_LineMerge(geom) as geom, 
		artclass
	FROM 
		street;

--- 1.2 Find intersection point from street
/*
Find intersections by using street segement's start/end points.

Pre:
(table:yun_processed_streets)

Post:
(table:yun_intersections)
{
	id int,
	geom POINT,
	s_id int[] "the id of streets of the intersection",
	s_otherpoints POINT[] "the geom of next point streets"
	degree double precision[] "the Azimuth degree of the nth streets and intersection point"
	num_sw int "number of streets"
}

Note: 
1. For each intersection, the street id, points and degree is sorted in clock-wise order.
*/
DROP TABLE IF EXISTS yun_intersections;
CREATE TABLE yun_intersections AS 
	SELECT  
		row_number() over() as id, 
		geom, 
		array_agg(s_id) as s_id,
		array_agg(other) as s_others, 
		array_agg(degree) as degree, 
		count(id) as num_s 
	FROM 
	(
		SELECT *, 
			row_number() over() as id 
		FROM 
		(
			SELECT 
				ST_PointN(p.geom,1) as geom, 
				id as s_id, 
				ST_PointN(p.geom,2) as other, 
				ST_Azimuth(ST_PointN(p.geom,1),ST_PointN(p.geom,2))  as degree 
			FROM 
				yun_processed_streets as p
			UNION 
			SELECT 
				ST_PointN(p.geom,ST_NPoints(p.geom))  as geom, 
				id as s_id , 
				ST_PointN(p.geom,ST_NPoints(p.geom) - 1)  as other, 
				ST_Azimuth(ST_PointN(p.geom,ST_NPoints(p.geom)),ST_PointN(p.geom,ST_NPoints(p.geom) - 1))  as degree 
			FROM 
				yun_processed_streets as p
		) as q
		ORDER by geom, st_azimuth(q.geom, q.other)
	)as q2
	GROUP BY geom;
/************  15444 rows **************/

/* Create spatial index*/
CREATE INDEX index_yun_intersections ON yun_intersections USING gist(geom);

-- Step2: Preprocessing for Sidewalks
--- 2.1 Transform sidewalks data from SDOT
/* 
Tranform the sidewalks type from multilinestring to linestring

Pre: 
(table:raw_sidewalks)
{	id int,  
	geom multiplinestring,
	segkey int "responding street key"
	...
}

Post: 
(table:yun_processed_streets)
{	id int, 
	geom linestring,
	segkey int "responding street key"
}

*/
DROP TABLE IF EXISTS yun_processed_sidewalks;
CREATE TABLE yun_processed_sidewalks AS 
	SELECT 
		id,
		ST_LineMerge(ST_Transform(geom,2926)) AS geom,
		segkey 
	FROM raw_sidewalks;

-- create spatial index
CREATE INDEX index_yun_processed_sidewalks ON yun_processed_sidewalks USING gist(geom);

ALTER TABLE yun_processed_sidewalks ADD PRIMARY KEY (id);
-- Delete all sidewalks that cause problems when plotting
/*
TODO:
Fix st_linemerge errors and avoid deleting null sidewalks
*/
DELETE FROM yun_processed_sidewalks
WHERE GeometryType(geom) = 'GEOMETRYCOLLECTION';

DELETE FROM yun_processed_sidewalks
WHERE geom in 
	(
		SELECT geom 
		FROM yun_processed_sidewalks
		group by geom having count(id) > 2
	);

-- Add new column to record the state of starting point and ending post of the sidewalk
ALTER TABLE yun_processed_sidewalks
  ADD COLUMN "s_changed" BOOLEAN DEFAULT FALSE,
  ADD COLUMN "e_changed" BOOLEAN DEFAULT FALSE;
  