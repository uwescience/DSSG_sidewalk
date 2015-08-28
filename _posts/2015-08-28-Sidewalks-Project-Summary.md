---
layout: post
title:  "Sidewalks Project Summary"
date:   2015-08-28
---

# Sidewalk Maps for Low Mobility Citizens

- Project Leads: Nick Bolten, Anat Caspi 
- DSSG Fellows: Amir Amini, Yun Hao, Vaishnavi Ravichandran, Andre Stephens
- ALVA Students: Nick Krasnoselsky, Doris Layman
- eScience Data Scientist Mentors: Anthony Arendt, Jake Vanderplas

This project is an extension of the "Hackcessible" project that was awarded top prize in this year's "HackTheCommute" event in Seattle. Hackcessible has built an application that helps people with mobility challenges to navigate the streets of Seattle based on sidewalk characteristics and the presence of curb ramps. Building on these ideas, the DSSG team worked to utilize city sidewalk and street data to provide stakeholders with routing information, similar to what is currently provided by google-maps, but that considers issues of accessibility. The work was carried out in partnership with Dr. Anat Caspi of the Taskar Center for Accessible Technology at the University of Washington, and with various stakeholders with the City of Seattle and the Washington State Department of Transportation.

The team began the project by developing algorithms to format and rectify the raw datasets of sidewalk locations. We found numerous instances of overlapping and disconnected sidewalks which needed to be fixed in order to build a connected graph for our routing analysis. Next, we devised algorithms to connect nodes, representing sidewalk endpoints, to adjacent nodes spanning street crosswalks. Finally, with a fully connected graph in place, we used relational database routining software to generate optimal paths across our sidewalk network, taking into account weighting factors related to relative accessibility. Our ALVA student partners played an important role in providing map-based analytics and visualizations, and in "field testing" some of our findings on sidewalks near the university, using GPS and other mapping technologies. 

Slides of the final presentation can be found [here](), and a video of the presentation is [here]().


![Sidewalks Graphic](images/Sidewalks.png "Cleaned Sidewalk Data in Downtown Seattle")