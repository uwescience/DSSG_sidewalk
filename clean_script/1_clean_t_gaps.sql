-- Step1: Find T intersections
--- 1.1 Find the maximum degree diff for each intersection
/*
Function: Find_Maximum_Degree_Diff: Find the pair of streets that have the maximum azimuth degree difference
Params: 
	a_degree: doublt[] "the azimuth degree of all streets that intersects at the same intersection" (yun_intersection column:degree)
	count: bigint "number of streets that intersects at the same intersections"(yun_intersection column:num_sw)
Returns:
	result double[]:{
	result[1], result[2]: the pair of degree with the maximum degree difference
	result[3]: maximum difference
	}
Note: 
2. The difference of the max_degree and min_degree is calculated after mod 2 * pi.
*/
CREATE OR REPLACE FUNCTION Find_Maximum_Degree_Diff(a_degree double precision[], count bigint) RETURNS double precision[] AS
$$
DECLARE max_degree double precision;
DECLARE cur_degree double precision;
DECLARE len int;
DECLARE result double precision[4];
BEGIN
	len := count;
	--IF len <= 2 THEN RETURN NULL; END IF;
	max_degree := 0;
	FOR i in 1..len-1 LOOP
		cur_degree := a_degree[i + 1] - a_degree[i];
		IF cur_degree > max_degree THEN max_degree := cur_degree;result[1] := a_degree[i];result[2] := a_degree[i + 1];result[4] := i + 1;
		END IF;
	END LOOP;
		cur_degree := a_degree[1] - a_degree[len] + 2 * pi();
		IF cur_degree > max_degree THEN max_degree := cur_degree;result[1] := a_degree[len];result[2] := a_degree[1];result[4] := 1;
		END IF;
	result[3] := max_degree;
	RETURN result;
END
$$
LANGUAGE plpgsql;

/*
Create column max_degree_diff and call function Find_Maximum_Degree_Diff
Pre: (table:yun_intersections){degrees:double precision[], num_sw:int}
Post:(table:yun_intersections){NEW COLUMN:degree_diff double precision[]}
*/
--ALTER TABLE yun_intersections DROP COLUMN ;
ALTER TABLE yun_intersections 
	ADD COLUMN degree_diff double precision[];

UPDATE yun_intersections
SET 
	degree_diff = Find_Maximum_Degree_Diff(degree,num_s);

/* TEST Visulization in QGIS
-- test maximum degree diff
CREATE VIEW yun_test_range AS
SELECT row_number() over() as id, * FROM (
SELECT  ST_MakeLine(geom, ST_Transform(ST_Project(ST_Transform(geom,4326)::geography, 40, degree_diff[1])::geometry,2926)) FROM (SELECT * FROM yun_intersections where is_t = True) as t
UNION 
SELECT  ST_MakeLine(geom, ST_Transform(ST_Project(ST_Transform(geom,4326)::geography, 40, degree_diff[2])::geometry,2926)) FROM (SELECT * FROM yun_intersections where is_t = True) as t) as q
*/

-- 1.2 Decide whethere an intersection is T intersection
/*
Create column is_t (whether a intersection is a T - intersection) and set its value based on degree_diff column

TODO:
1. Test L & Y intersection
*/ 
ALTER TABLE yun_intersections 
	ADD COLUMN is_t boolean;

UPDATE yun_intersections
SET 
	is_t = TRUE
WHERE
	num_s >= 3 
	AND degrees(degree_diff[3]) > 170 
	AND degrees(degree_diff[3]) < 190;
/************  5855 rows **************/


-- Step3: sidewalk corners & intersection groups
--- 3.1 Get sidewalks corners table
/*
Find intersections by using street segement's start/end points.

Pre:
(table:yun_processed_streets)

Post:
(table:yun_ends_sidewalks)
{
	id int,
	geom POINT,
	sw_id int "the id of streets of the ends",
	sw_other POINT "the geom of next point streets"
	sw_type char "S:starting point, E:ending Point"
}
 TODO: check why some sidewalks with starting point return false
*/
DROP TABLE IF EXISTS yun_ends_sidewalks;
CREATE TABLE yun_ends_sidewalks AS
	SELECT  
		row_number() over() as id, 
		geom, 
		query.id as sw_id,
		type as sw_type,
		other as sw_other 
	FROM
	(
		SELECT 
			ST_Startpoint(geom) as geom, 
			id, 
			'S' as type, 
			 ST_PointN(geom,2) as other 
		FROM 
			yun_processed_sidewalks
		WHERE 
			ST_Startpoint(geom) is not null
		UNION 
		SELECT 
			ST_Endpoint(geom) as geom, 
			id, 
			'E' as type,
			ST_PointN(geom,ST_NPoints(geom) - 1)  as other 
		FROM 
			yun_processed_sidewalks
		WHERE
			ST_Endpoint(geom) is not null
	) as query;
/********* 89776 rows **************/
/* Create spatial index*/
CREATE INDEX index_yun_ends_sidewalks ON yun_ends_sidewalks USING gist(geom);
/************  49160 rows **************/


-- 3.2 Assign sidewalk ends to intersection groups
/*
For each sidewalk ends, Assign to the closest intersection within distance tolrance. 
Pre: 
(view:yun_ends_sidewalks){
	id:int, 
	geom:POINT}
(view:yun_intersection){
	id:int, 
	geom:POINT}
Post:
(table:yun_intersection_group) {c_id:int"corner id", i_id:int "assigned intersection group id", c_geom:POINT, i_geom:POINT}
Note: 
1. Only intersections have assigned corners exist in this table.
2. Only ends assigned to any intersections table exist in this table.
3. The measurement of the distance tolerance is feet.
TODO:
1. Discuss dead End, t-intersection and L-intersection cases.
2. same line assign to the same group
*/
-- Define intersection groups;
DROP TABLE IF EXISTS yun_end_intersection_group;
CREATE TABLE yun_end_intersection_group AS
	SELECT * 
	FROM
	(
		SELECT 
			DISTINCT ON (e.id) 
			e.id as e_id, -- end id
			i.id as i_id, -- intersection id
			e.geom as e_geom, -- end geom POINT
			i.geom as i_geom  -- intersection geom POINT
		FROM 
			yun_ends_sidewalks as e
			INNER JOIN yun_intersections AS i 
				ON ST_DWithin(e.geom, i.geom, 100)
		ORDER BY e.id, ST_Distance(e.geom, i.geom) 
	)AS q
	ORDER BY q.i_id, ST_Azimuth(q.i_geom, q.e_geom);
/************  48873 rows **************/

/* TEST Visulization in QGIS
--Test all intersection group assignment 
DROP VIEW yun_test_connect;
CREATE VIEW yun_test_connect AS
SELECT row_number() over() as id, ST_MakeLine(c_geom, i_geom) FROM yun_intersection_group;
*/

-- Step4: Clean T-intersections
--- 4.1 Connect gaps in T-intersections
/* Function: is_point_in_range
Params: 
dg_range double precision[], "degree range" dg_range[1] > dg_range[0]
dg_point double precision: "the testing point"
*/
CREATE OR REPLACE FUNCTION is_point_in_range(dg_range double precision[], dg_point double precision) RETURNS boolean AS
$$
BEGIN
	IF dg_range[2] > dg_range[1] THEN
		IF dg_point < dg_range[2] AND dg_point > dg_range[1] THEN
			RETURN True;
		ELSE
			RETURN False;
		END IF;
	ELSE
		IF dg_point < dg_range[2] OR dg_point > dg_range[1] THEN
			RETURN True;
		ELSE 
			RETURN False;
		END IF;
	END IF;
  END
$$
LANGUAGE plpgsql;

/* Find all gaps in T intersections 
Pre: yun_intersections, yun_intersection_group, yun_corner
Post: yun_t_inter_groups
Note:
I only consider the case where(#corners = 2 & #sum_sw = 2). However, other cases are also solvable. Details see Test in QGIS below.
TODO:
consider other cases.
*/

CREATE TABLE yun_t_inter_groups AS 
	SELECT 
		t_ig.i_id,
		array_agg(e.sw_id) as s_id, 
		array_agg(e.sw_type) as s_type, 
		array_agg(e.geom) as c_geom
	FROM 
	(
		SELECT 
			ig.*,degree_diff
		FROM 
		(
			SELECT 
				id, 
				degree_diff
			FROM yun_intersections
			WHERE is_t = True
		) as ti -- All t intersections
		INNER JOIN yun_end_intersection_group as ig
			ON ig.i_id = ti.id
		WHERE is_point_in_range(degree_diff,ST_Azimuth(ig.i_geom, ig.e_geom)) = True
	) AS t_ig
	INNER JOIN yun_ends_sidewalks as e ON t_ig.e_id = e.id
	WHERE is_point_in_range(t_ig.degree_diff,ST_Azimuth(t_ig.i_geom, ST_Centroid(e.geom)))
	GROUP BY t_ig.i_id HAVING count(t_ig.e_id) = 2;

DROP TABLE IF EXISTS yun_flags_t_gap;
CREATE TABLE yun_flags_t_gap AS
	SELECT 
		t_ig.i_id,
		array_agg(e.sw_id) as s_id, 
		array_agg(e.sw_type) as s_type, 
		array_agg(e.geom) as c_geom
	FROM 
	(
		SELECT 
			ig.*,degree_diff
		FROM 
		(
			SELECT 
				id, 
				degree_diff
			FROM yun_intersections
			WHERE is_t = True
		) as ti -- All t intersections
		INNER JOIN yun_end_intersection_group as ig
			ON ig.i_id = ti.id
		WHERE is_point_in_range(degree_diff,ST_Azimuth(ig.i_geom, ig.e_geom)) = True
	) AS t_ig
	INNER JOIN yun_ends_sidewalks as e ON t_ig.e_id = e.id
	WHERE is_point_in_range(t_ig.degree_diff,ST_Azimuth(t_ig.i_geom, ST_Centroid(e.geom)))
	GROUP BY t_ig.i_id HAVING count(t_ig.e_id) != 2;


/* TEST Visulization in QGIS
-- Using code below, we can see the distribution of number of corners and number of sidewalks when cleanning the dataset.
(#corners, #sum_sw): case number, "desc"
(1,1):428, sidewalks is divided by intersection groups
(2,1):2462, Already solved
(2,2):1531, Already solved
(3,1):31 Can be solved after remove overshooting
(3,2):328, Can be solved after remove overshooting
(3,3):137, can be solved by picking two corners that is pendicular to the street
(42)8(43)23(44)8(52)2(54)1
	SELECT t_ig.i_id, array_agg(c.s_id[1]), i_geom,sum(num_sw) *10+count(t_ig.c_id) 
	FROM 
	(
		SELECT 
			ig.*
		FROM 
		(
			SELECT 
				id, 
				degree_diff
			FROM yun_intersections 
			WHERE is_t = True
		) as ti -- All t intersections
		INNER JOIN yun_intersection_group as ig
			ON ig.i_id = ti.id
		WHERE is_point_in_range(degree_diff,ST_Azimuth(ig.i_geom, ig.c_geom)) = True
	) AS t_ig
	INNER JOIN yun_corners as c ON t_ig.c_id = c.id
	WHERE num_sw > 0
	GROUP BY t_ig.i_id,t_ig.i_geom


CREATE OR REPLACE VIEW yun_test_find_sidewalks AS
SELECT row_number() over() as id,  ig.c_id, ig.i_id, ST_MakeLine(ig.c_geom, ig.i_geom)
FROM yun_intersection_group AS ig 
INNER JOIN (SELECT * From yun_intersections WHERE is_t = True) AS i ON ig.i_id = i.id
WHERE is_point_in_range(i.degree_diff,ST_Azimuth(ig.i_geom, ig.c_geom)) = True;

*/

/* 
Insert the middle point of corners to the sidewalks
Pre:yun_t_inter_groups, yun_cleaned_sidewalks
Post: yun_cleaned_sidewalks: updated geom, updated geom_changed
*/

/* Update first corner if it is the ending point of a sidewalk */
UPDATE yun_processed_sidewalks as s
SET 
	geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom))),
	e_changed = True
FROM yun_t_inter_groups as tig
WHERE 
	s.id = tig.s_id[1] 
	AND tig.s_type[1] = 'E';
/* Update first corner if it is the Starting point of a sidewalk */
UPDATE yun_processed_sidewalks as s
SET 
	geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom)),0),
	s_changed = True
FROM yun_t_inter_groups as tig
WHERE 
	s.id = tig.s_id[1] 
	AND tig.s_type[1] = 'S';
/* Update second corner if it is the ending point of a sidewalk */
UPDATE yun_processed_sidewalks as s
SET 
	geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom))),
	e_changed = True
FROM yun_t_inter_groups as tig
WHERE 
	s.id = tig.s_id[2]
	AND tig.s_type[2] = 'E';
/* Update first corner if it is the Starting point of a sidewalk */
UPDATE yun_processed_sidewalks as s
SET 
	geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom)),0),
	s_changed = True
FROM yun_t_inter_groups as tig
WHERE 
	s.id = tig.s_id[2] 
	AND tig.s_type[2] = 'S';
