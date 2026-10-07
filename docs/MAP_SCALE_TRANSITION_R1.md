# WORLD / REGION presentation

The existing GlobeController owns both camera choices, selection, hover, mode and
Labels. GlobeRenderer uses the same PoliticalLayer and detached world facts in
both views. RegionView shares every existing surface mesh, data texture and border
mesh with WORLD; it owns only canvas items/materials and a cached viewport.
No simulation component, save field or independent region world exists.

## Coordinates and scale

All coordinates use the existing unit sphere convention and a spherical mean
Earth radius of 6371.0088 km. This is display geometry, not a survey-grade
ellipsoidal distance claim. RegionProjection uses an east/north/anchor orthonormal
frame, including at the poles. For a unit point with frame coordinates (x,y,z),
`c = atan2(length(x,y), z)` and the azimuthal equidistant coordinate is
`R * c / sin(c) * (x,y)`. At the centre it is zero. The inverse at distance d
is `(sin(d/R)*x/d, sin(d/R)*y/d, cos(d/R))`, transformed back by the frame.
The antipode has no unique azimuth; the finite regional view never reaches it.
Longitude wrapping is handled by the unit sphere, not a discontinuous longitude
subtraction. Screen coordinates apply the saved bearing, scale and offset.

AEQD and Lambert azimuthal equal-area were compared using actual admitted display
faces. At 3000 km AEQD transverse scale grows 3.79%; LAEA has -0.92% radial
distance error and radial/transverse scale changes of -2.76%/+2.84%. At 5000 km
AEQD transverse scale grows 11.05%; LAEA distance error is -2.55% and scales
-7.60%/+8.23%. Both centre shapes are natural. AEQD is chosen for the simple,
exact centre-distance metric and inverse. Neither projection makes every distance
or every shape exact. Comparisons and screenshots are in local-artifacts/map-scale-r1.
Reference mathematics: [USGS Snyder, Map Projections—A Working Manual](https://pubs.usgs.gov/pp/1395/report.pdf)
and [PROJ AEQD documentation](https://proj.org/en/stable/operations/projections/aeqd.html).

The threshold metric is the area-equivalent local km/pixel, the geometric mean
of the two local orthogonal scales. On the orthographic sphere it is
`R / (screen_radius * sqrt(view_depth))`; in AEQD it is
`camera_km_per_pixel * sqrt(sin(c)/c)` (centre limit 1).
An off-centre globe is anisotropic; one scalar preserves local area scale, not
both singular values. The anchor pixel and local north bearing are preserved
separately. WORLD restoration solves its radius from the screen offset and metric,
then constructs a right-handed attitude with that anchor and north direction.

## Transition and finite camera

Wheel input uses the geographical point below the pointer, or the viewport centre
if the pointer is outside valid geography. Selection is never used to infer the
camera anchor. WORLD wheel zoom also preserves that point. WORLD enters at
5.5 km/pixel, REGION exits at 7.0; preparation starts at 8.5. The hysteresis is
spatial, not a percentage zoom rule; no extra timer is needed.

RegionView prepares material/canvas bindings in slices with a 2 ms CPU budget.
There is no re-triangulation, new mesh upload or per-camera source copy. Until it
is ready WORLD stays visible. Both views use the same shader programs; a projection
uniform selects the local plane. A 220 ms crossfade uses the cached departure and
arrival textures. Camera input is held during this short fade; selection and all
world facts remain unchanged. The inactive viewport is disabled after the fade.
Hiding the map stops preparation/fade work; returning refreshes its current view.

The finite projected disc radius is the furthest viewport corner from the entry
anchor, evaluated at the exit scale, plus 1500 km of pan allowance; it is capped
at 9000 km, below the projection's hemisphere. Typical 1280×550 entry at (495,240)
gives 7407.95 km. Camera pan constrains the viewport's circumscribed disc inside
this extent. This deliberately conservative constraint avoids undefined edges.
The anchor is fixed for the lifetime of this region. Crossing continents uses
WORLD, then enters a newly anchored region. Scale stops at 0.25 km/pixel because
R1 supplies no extra detailed content; there is no LOCAL renderer.

Political identities, display-only masks, controllers, date-dependent flags and
boundaries are unchanged. REGION uses existing resolved political colours with a
reduced flag texture contribution, not new historical data. Fulfillment/Shortage
use exactly the existing aggregate observations. The existing Military page stays
available; the current product does not have a Military spatial-overlay mode, so
R1 does not invent one. Changing pages retains the chosen camera and map mode.

Picking first inverts the local projection, conservatively filters source face
bounds, then uses exact point-in-polygon on the same projected source triangles.
Cities use the existing place markers and current runtime parent IDs. No colour
sampling or camera-owned political identity is involved.

Geographical label coordinates, names and text measurements are cached once at
entry or on a facts refresh. Visible glyph commands are submitted once and retained
on regional canvas items; an unseen name is submitted only when first revealed.
Pan/zoom changes their transforms and visibility, without spherical projection,
text shaping or rebuilding existing glyph commands. The small visible collision
set runs only on dirty redraw, never on an idle process. Preparation and transition
are the only temporary renderer processes.
At regional entry, cities retain their markers; only selected/hovered city names
are shown. Other existing city names appear below 1.5 km/pixel with overlap checks.
Country labels reserve the visible city-name rectangles, avoiding a new label pile
at the WORLD/REGION boundary. No new place content is generated.

## Verified future LOCAL handoff contract

The actual WORLD/REGION tests verify these handoff values: geographic anchor
(longitude/latitude or unit vector), anchor pixel in the map viewport, measured
local km/pixel, local north bearing, stable selected polity/place IDs, hover where
still visible, mode, Labels and current display date. A future local view should
receive these values from the same controller and detached presentation facts.
It must provide matching forward/inverse point queries, finite camera limits,
bounded preparation, dirty redraw and inactive-view suspension. Camera information
continues to be presentation-only unless a later, explicit save requirement arises.

There is no LOCAL class, empty renderer, registry, new province source, road,
railway, firm, market, military-unit or 50×50 km gameplay production in this task.
