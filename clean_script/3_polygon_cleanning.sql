-- Step0: Create index on compkey
CREATE UNIQUE INDEX street_compkey ON street (compkey);
--- However, postgresql does not allow me to this because compkey is not unique. Find compkey that is not unique

select compkey,  st_asgeojson(ST_Collect(geom)) from street group by compkey having count(compkey) > 1;
-- 1186 5459 10562 comkey is not unique
/*
   1186 | {"type":"GeometryCollection","geometries":[
   {"type":"MultiLineString","coordinates":[[[1270163.60964943,222794.47695218],[1270157.03659342,222499.175063878],[1270156.79953742,222488.529559866]]]},
   {"type":"MultiLineString","coordinates":[[[1270163.60964943,222794.47695218],[1270157.03659342,222499.175063878],[1270156.79953742,222488.529559866]]]}]}
    5459 | {"type":"GeometryCollection","geometries":[
    {"type":"MultiLineString","coordinates":[[[1259372.97207038,203832.06669277],[1259362.55594237,203500.451460421],[1259352.13776636,203168.812420085]]]},
    {"type":"MultiLineString","coordinates":[[[1259372.97207038,203832.06669277],[1259362.55594237,203500.451460421],[1259352.13776636,203168.812420085]]]},
    {"type":"MultiLineString","coordinates":[[[1259372.97207038,203832.06669277],[1259362.55594237,203500.451460421],[1259352.13776636,203168.812420085]]]}]}
   10562 | {"type":"GeometryCollection","geometries":[
   {"type":"MultiLineString","coordinates":[[[1266653.09598184,239644.483241439],[1266656.93009384,239797.605033591]]]},
   {"type":"MultiLineString","coordinates":[[[1266653.09598184,239644.483241439],[1266656.93009384,239797.605033591]]]}]}
 */
 -- street with compkey includes same geom information. I remove all the repetition. 
DELETE FROM street 
WHERE id IN (
SELECT id
FROM (SELECT id,ROW_NUMBER() OVER (partition BY compkey ORDER BY id) AS rnum FROM street) as t
WHERE t.rnum > 1);
-- Now we can create index
CREATE UNIQUE INDEX street_compkey ON street (compkey);

-- Step1: Select streets
SELECT r.id, s.compkey
FROM street s
LEFT JOIN raw_sidewalks r ON s.compkey = r.segkey
WHERE r.id is null;

SELECT query.artclass, count(query.id)   FROM( 
SELECT r.id, s.compkey, s.artclass
FROM street s
LEFT JOIN raw_sidewalks r ON s.compkey = r.segkey
WHERE r.id is null ) AS query
GROUP by query.artclass;
/*
 artclass | count
----------+-------
          |     0
        4 |    30
        5 |   256
        1 |   124
        2 |    74
        9 |     1
        0 |   730
        3 |    91
(8 rows)
*/

-- See all streets without sidewalk 
SELECT s.id, s.geom
FROM street s
LEFT JOIN raw_sidewalks r ON s.compkey = r.segkey
WHERE (r.id is not null OR s.artclass < 3) 
-- We see it is very accurate that street picked by this sql code does not have sidewalks on the map.
-- Therefore, compkey is useful in two ways.
-- 1. Help us to detect those missing sidewalks. 
-- 2. Optimize polygonizing methods.

-- Step2: Polygonizing
CREATE TABLE boundary_polygons AS
SELECT g.path[1] as gid,geom
FROM(
	SELECT (ST_Dump(ST_Polygonize(picked_sidewalks.geom))).*
	FROM (
		SELECT DISTINCT ON (s.id) s.id, s.geom
		FROM street s
		LEFT JOIN raw_sidewalks r ON s.compkey = r.segkey
		WHERE r.id is not null OR s.artclass < 3) as picked_sidewalks
	) as g;

-- Step3: Remove overlap polygons
DELETE FROM boundary_polygons
WHERE gid in (
SELECT b1.gid FROM boundary_polygons b1, boundary_polygons b2
WHERE ST_Overlaps(b1.geom, b2.geom)
GROUP BY b1.gid HAVING count(b1.gid) > 1);

-- Go to group_sidewalks.sql



---Method1: 6387

--- Step1: Find all sidewalks what are within a polygons
CREATE TABLE grouped_sidewalks AS
SELECT b.gid as b_id, s.id as s_id, s.geom as s_geom
FROM processed_sidewalks as s
LEFT JOIN boundary_polygons  as b ON ST_Within(s.geom,b.geom);
-- 39609 sidewalks are classified in this step.

---  Step2: Find all polygons that is not assigned to any polygons because of offshoots.
UPDATE grouped_sidewalks
SET b_id = query.b_id 
FROM(
SELECT b.gid as b_id, s.s_id, s.s_geom as s_geom FROM 
(SELECT * FROM grouped_sidewalks
WHERE b_id is null) as s
INNER JOIN boundary_polygons as b ON ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5),b.geom) = True) AS query
WHERE grouped_sidewalks.s_id = query.s_id;
-- 3222 sidewalks are classified in this step. 1 sidewalks are assiged to 2 groups. 
-- (polygons - 24403 4638, 4698)
-- SELECT ST_Within(ST_Line_Interpolate_Point(c.geom, 0.5),a.geom)  from (select * from boundary_polygons where gid = 4638) as a, (select * from boundary_polygons where gid = 4698) as b, (select * from processed_sidewalks where id = 24403) as c
/*
SELECT * FROM (
(SELECT * FROM grouped_sidewalks
WHERE b_id is null) as s
INNER JOIN boundary_polygons as b ON (ST_Intersects(s.s_geom, b.geom) AND ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5),b.geom) = True))
WHERE  ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5),b.geom) = False;

SELECT *, ST_Within(ST_Line_Interpolate_Point(a.s_geom, 0.5),a.geom) FROM (
SELECT b.gid as b_id, s.s_id, s.s_geom as s_geom, b.geom FROM 
(SELECT * FROM grouped_sidewalks
WHERE b_id is null) as s
INNER JOIN boundary_polygons as b ON ST_Intersects(s.s_geom, b.geom) AND ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5),b.geom) = True) as a
WHERE a.s_id = true

*/


-- highway

--- Not important: For qgis visualization
CREATE VIEW correct_sidewalks AS
SELECT b.id as b_id, s.s_id,ST_MakeLine(ST_Line_Interpolate_Point(s.sidewalk_geom, 0.5),ST_Centroid(b.geom)) as geom FROM 
(SELECT * FROM polygon_sidewalks
WHERE b_id is null) as s
INNER JOIN boundaryPolygons as b ON ST_Intersects(s.sidewalk_geom, b.geom)
WHERE ST_Within(ST_Line_Interpolate_Point(s.sidewalk_geom, 0.5),b.geom) = True;

--- Find a bad polygon(id:666) which looks like a highway.
-- There are 57 Polygons that has centroid outside the polygon. Most of them works well with our algorithm.
CREATE VIEW bad_polygons AS
SELECT * from boundarypolygons as b
WHERE  ST_Within(ST_Centroid(b.geom), b.geom) = False;

SELECT b.id as b_id, s.s_id, FROM 
(SELECT * FROM polygon_sidewalks
WHERE b_id is null) as s
INNER JOIN boundaryPolygons as b ON ST_Intersects(s.sidewalk_geom, b.geom)
WHERE ST_Within(ST_Line_Interpolate_Point(s.sidewalk_geom, 0.5),b.geom) = True



GROUP by b.id, s_id having count(s_id) > 2


-- Step 3: Boundaries
-- There are 2779 sidewalks has not been assigned to any polygons 

SELECT s.* 
FROM (SELECT * FROM grouped_sidewalks WHERE b_id is null) as s, union_polygons as u 
WHERE ST_Intersects(s.s_geom,u.geom)


--CREATE table UNION_poly AS select st_union(geom) from boundary_polygons;
--ALTER TABLE  UNION_poly ADD id int;
--UPDATE UNION_poly
-- SET id = 1;
CREATE VIEW union_polygons AS
SELECT q.path[1] as id,geom
FROM (select (st_dump(st_union(geom))).* from boundary_polygons) AS q

-- For each unAssigned it to the closest polygons
UPDATE grouped_sidewalks
SET b_id = query.b_id
FROM (
SELECT DISTINCT ON (s.s_id) s.s_id as s_id, u.id as b_id
FROM (SELECT * FROM grouped_sidewalks
WHERE b_id is null) as s
INNER JOIN union_polygons  as u
ORDER BY s.s_id, ST_Distance(s.s_geom, u.geom)  ) AS query
WHERE grouped_sidewalks.s_id = query.s_id



