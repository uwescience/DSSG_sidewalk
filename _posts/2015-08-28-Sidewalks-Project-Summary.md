---
layout: post
title:  "Sidewalks Project Summary"
date:   2015-08-28
---
![eScience logo]({{site.url}}/images/dssg_logo_no_bkgrnd.png)

# Sidewalk Maps for Low Mobility Citizens

- Project Leads: Nick Bolten, Anat Caspi
- DSSG Fellows: Amir Amini, Yun Hao, Vaishnavi Ravichandran, Andre Stephens
- ALVA Students: Nick Krasnoselsky, Doris Layman
- eScience Data Scientist Mentors: Anthony Arendt, Jake Vanderplas

This project is an extension of the ["Hackcessible" project](http://www.accessmapseattle.com/) that was awarded [top prize](http://www.geekwire.com/2015/app-that-helps-people-in-wheelchairs-plan-travel-routes-wins-first-place-at-civic-hackathon/) in this year's "HackTheCommute" event in Seattle. Hackcessible has built an application that helps people with mobility challenges to navigate the streets of Seattle based on sidewalk characteristics and the presence of curb ramps. Expanding on these ideas, the DSSG team worked to utilize city sidewalk and street data to provide stakeholders with routing information, similar to what is currently provided by Google Maps, but that considers issues of accessibility. The goal of the effort is to provide rapid and convenient routing that avoids steep hills, uncrossable intersections, stairs or construction. The work was carried out in partnership with Dr. [Anat Caspi](http://tcat.cs.washington.edu/node/12) of the Taskar Center for Accessible Technology at the University of Washington, and with various stakeholders with the City of Seattle and the Washington State Department of Transportation.

The team began the project by developing algorithms to format and rectify the raw datasets of sidewalk locations. We found numerous instances of overlapping and disconnected sidewalks which needed to be fixed in order to build a connected graph for our routing analysis. Next, we devised algorithms to connect nodes, representing sidewalk endpoints, to adjacent nodes spanning street crosswalks. Finally, with a fully connected graph in place, we used [pgRouting](http://pgrouting.org), an extension to the PostgreSQL relational database software, to generate optimal paths across our sidewalk network, taking into account weighting factors related to relative accessibility. Our ALVA students played an important role in providing map-based analytics and visualizations. They also worked to "field test" some of our findings on sidewalks near the university, using GPS and other mapping technologies. 

A video of the presentation is [here](https://uw.hosted.panopto.com/Panopto/Pages/Viewer.aspx?id=126a8bf4-95cd-4b5e-3431-2af848a0326a).


![Sidewalks Graphic]({{ site.url }}/images/Sidewalks.png "Sidewalk Data in Downtown Seattle")
Graphic of sidewalk data in downtown Seattle. The team worked to clean these datasets and build a connected graph that will now be used for calculating optimal routing paths with a consideration of accsesibility issues. 
