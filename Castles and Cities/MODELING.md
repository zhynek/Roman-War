# City modeling and visual development

This workspace develops independent city studies: researched places, dated
layouts, editable architectural components and visual growth stages. It follows
[CLAUDE.md](../CLAUDE.md), including original procedural art and the prohibition
on image files in the repository. It does not change the campaign, create a new
playable faction, or connect a city to construction, combat or saves.

**No finished model or renderer is supplied yet.** The conventions below define
how to author and review future work. They do not claim that CAD conversion,
mesh export, rendering or gameplay integration has been implemented.

## What historical realism means

Choose a place and a target date before designing its architecture. A believable
surface cannot compensate for an incorrect street plan, a monument from another
century, or a restored modern roof presented as medieval evidence. Distinguish
the date a source describes from the date it was made and the dates of later
alterations to the building.

Record each important decision as one of these:

- **Documented:** supported for the target period by an identified source.
- **Reconstructed:** inferred from evidence, with the inference and alternatives
  explained.
- **Interpretive:** an authored choice where evidence is insufficient.
- **Creative:** an intentional departure from the historical study.

These labels describe evidence, not visual quality. An approximate blockout may
have well-supported dimensions; a detailed render may contain speculative
interiors. Keep those distinctions visible in the project record. Unknowns are
useful findings, not defects to hide behind extra detail.

## Coordinates, units and precision

Use meters for lengths and degrees for explicitly named angles. The authoring
coordinate system is right-handed: **+X east, +Y north, +Z up**. Define footprints
in the horizontal XY plane and elevations along Z. Name dimensions by meaning,
such as `wall_thickness_m` or `springing_height_m`, rather than ambiguous scale
factors.

A future Godot adapter maps an authoring point `[x, y, z]` to `[x, z, -y]`:
Godot +X remains east, +Y becomes up and -Z becomes north. Apply the same basis
change consistently to geometry, normals, orientations and any inspection or
picking geometry. Do not manually swap coordinates in individual assets. Keep
the authoring source independent of this adapter.

For every city, record the following before claiming geographic alignment:

- Local origin and its physical reference point.
- Horizontal reference system, orientation and transformation, if known.
- Vertical datum and how elevations relate to it.
- Source scale, measurement method, accuracy and any estimated uncertainty.

Leave survey origin, datum and precision **unset until sourced**. A provisional
modeling origin is acceptable when labeled as an arbitrary local convenience;
it is not a surveyed coordinate. Do not substitute zero for an unknown elevation
or claim centimeter accuracy because a CAD program can display centimeters.
Preserve source precision and distinguish measurement uncertainty from modeling
tolerances. Set assembly tolerances deliberately when a component needs them.

Keep object transforms explicit. A component should have a meaningful local
origin, such as its base center or a construction corner, so it can be positioned
and revised without moving unrelated geometry. Document that choice.

## Object structure and dimensional evidence

Use persistent, lowercase `snake_case` IDs for authored objects. Organize a city
as a hierarchy of site, district, parcel or precinct, building, assembly and
component. A gate, wall curtain, tower, roof truss or doorway should remain
addressable without requiring every masonry block to become a separate object.

Each significant object should carry:

- Its ID, parent, human-readable name, type and intended function.
- Target period and stage membership, including known construction or removal
  dates and uncertainty where needed.
- Local transform, dimensions and the parameters that generate its geometry.
- Material families and construction relationships.
- Evidence references and status for the plan, height, elevation, construction
  system, surface treatment and interior separately.
- A record of unresolved questions and intentional simplifications.

A dimension record should identify the source and locator, original value and
unit, conversion if necessary, measurement or inference method, and confidence
or uncertainty. A plan-derived footprint and an estimated roof height must not
share a single blanket claim of surveyed accuracy. Keep derived values linked
to their inputs; do not copy them into unrelated parameters that later drift.

Use a representative wall bay as an early geometry test: curtain, foundation,
walkway, openings, parapet and its connection to an adjacent element. First
select the period and supporting evidence. An invented test bay is useful for
checking assemblies but must remain labeled interpretive, with no claim that
its dimensions describe a particular historical wall.

## CAD sources and render geometry

The editable source and the viewing mesh serve different purposes.

**Parametric CAD** records geometric intent: profiles, constraints, dimensions,
solids, voids and relationships between assemblies. Preserve native editable
source and the procedural generation recipe. A solid exchange file can support
interchange when appropriate, but it does not necessarily preserve the original
constraint or feature history.

**DCC and render meshes** describe the surfaces needed for viewing: tessellation,
normals, material assignments and levels of detail. Curved vaults, carved
surfaces and irregular masonry may need a different representation from their
structural CAD source. Record the conversion and simplifications, and regenerate
derivatives when their source changes.

**glTF is a possible scene and mesh interchange format, not the archival CAD
source.** A triangulated export cannot stand in for editable dimensions, solid
construction or historical evidence. Do not promise lossless round trips between
CAD, a DCC tool and Godot.

Check scale, orientation, face winding, normals, openings and material grouping
after every new conversion route. Check watertightness where a model is intended
to represent a solid; a deliberately open visual surface has a different
contract. Preserve meaningful assemblies before deciding how to batch meshes
for a particular renderer.

## Build the city from the ground upward

Work through these levels in order, revisiting earlier decisions when evidence
changes:

1. **Terrain and site:** establish the dated shoreline or watercourses, relief,
   slopes, major routes and relevant ground levels. Record uncertainty caused
   by later earthworks or changes in water and ground level.
2. **District:** establish precinct boundaries, streets, plazas, access routes,
   building relationships and open space. Resolve the spaces between buildings
   before adding facade ornament.
3. **Buildings:** establish footprints, elevations, masses, roofs, load-bearing
   systems and openings. Check that adjacent structures meet plausibly and that
   entrances connect to the authored ground.
4. **Assemblies and interiors:** develop wall sections, stairs, roof structure,
   floors, thresholds and supported interior arrangements. Keep inaccessible or
   unevidenced rooms explicit rather than filling them with invented certainty.
5. **Materials and everyday detail:** develop original procedural stone,
   mortar, brick, plaster, timber, metal and roofing treatments. Explain why
   weathering, repairs, soot, moisture and wear occur where they do.

A proposed first detailed district is the **Hagia Sophia–Hippodrome area of
Constantinople**. Begin with a dated relationship study of the two landmarks,
their approaches, surrounding open spaces and selected neighboring structures.
Choose a bounded precinct for the first detailed pass after checking source
coverage. This is a proposed research focus, not a claim that an accurate plan
or complete district model already exists. Do not combine features from
different historical phases simply because they appear together in modern
photographs or plans.

The wall bay test can proceed as a separate, small assembly study while the
district plan is being researched. Its success establishes a modeling method;
it does not establish the accuracy of the city as a whole.

## Stages and creative variants

Historical stages are dated states of a place. They are not automatically the
campaign's settlement levels or a universal sequence of town-hall upgrades.
For each new stage, identify:

- **Existing:** retained objects with the same identity and supported form.
- **Changed:** additions, repairs, extensions or conversions, linked to the
  previous object and the reason for the change.
- **New:** newly introduced objects, with their evidence and date range.
- **Removed:** demolished, abandoned or replaced objects, with retained history
  rather than silently deleted provenance.

Preserve street alignments, parcels and assemblies where continuity is supported.
Do not regenerate an unrelated city at every stage. Model intermediate
construction only when it is useful to the study and label the proposed sequence
if it is not documented. Switching stage views is an inspection action.

For creative design, fork a named historical baseline and record explicit
overrides. A larger harbor, a relocated palace or a new wall circuit belongs to
that variant. It must not overwrite the evidence-backed baseline or acquire
historical status through reuse. Physical features can suggest future city
capabilities, but this workspace does not assign campaign bonuses or costs.

## Original procedural art and sources

Keep procedural geometry and material recipes original. Do not add photographs,
scans, texture maps, image renders or other image files to the repository.
Use external references through source links and record what fact or inference
each supports. Store QA images outside the repository, for example under
`/tmp/roman-war-city-qa/`.

A publicly accessible plan or photograph is evidence to assess; accessibility
does not grant a license to copy its artwork, scan, mesh or texture into the
project. Facts and dimensions do not themselves authorize importing an asset.
Check any proposed asset use against its actual rights and the repository's
original procedural art policy. Cite observations in original prose and retain
the reasoning behind independently authored geometry.

Use stable object IDs and explicit seeds or hashes for procedural variation.
Changing a camera, selecting an object or revisiting a stage must not reshuffle
the scene. Detail should follow material and construction logic rather than
uniform random noise.

## Visual review and completion criteria

Review an actual render or interactive view when a rendering route exists.
Code inspection alone cannot establish the appearance of a city. Keep camera,
stage and lighting metadata with external QA captures so comparisons can be
reproduced. At minimum, inspect:

- Plan and elevation views for footprint, height and alignment checks.
- An oblique district view for terrain, roofscape, routes and scale relationships.
- A street-level view for openings, thresholds, paving and believable human scale.
- Close architectural views for connections, curved surfaces, material response
  and procedural repetition.
- The same views across stages for retained identity and supported changes.
- Sections or interior views where internal construction is part of the study.

Use neutral inspection lighting as well as any atmospheric presentation. Check
for floating structures, buried doors, intersecting roofs, impossible drainage,
unintended gaps, incorrect normals, excessive repetition and detail that masks
an unresolved plan. Label interpretive elements in the review record. Review
both historical support and visual quality; passing one does not imply the
other.

Record geometry counts, render settings, observed responsiveness and hardware
when evaluating a prototype. Set practical budgets from those measurements;
there is no promised frame rate, detail count or finished-fidelity threshold in
this document. Prefer a defensible completed precinct over unsupported detail
spread across a whole city.

All modeling and animation here are presentation. No generator, camera, render
callback, timer or stage preview may move campaign forces, spend resources,
advance simulation or draw from campaign RNG. Any future game integration needs
its own reviewed adapter and the existing validation gates. Until then, the
city study remains independent of campaign data and gameplay.
