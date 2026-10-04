# Original model source

Original editable model source now lives in the standalone
[experience](../experience/project.godot):

- [city.json](../experience/data/city.json) contains site, ward, route, landmark,
  dimension and evidence parameters.
- [layout.gd](../experience/src/layout.gd) creates deterministic plots and terrain.
- [geometry.gd](../experience/src/geometry.gd) and
  [landmarks.gd](../experience/src/landmarks.gd) build original architectural meshes.
- [export_models.gd](../experience/tools/export_models.gd) exports the city and
  individual landmarks as GLB derivatives with neutral materials and provenance.

These are procedural mesh sources, not a surveyed or constraint-based CAD solid
model. This directory remains the place for future measured dimension schedules
and higher-precision CAD assemblies. Follow the workspace
[modeling guide](../../../../../MODELING.md).

Suggested organization as work is produced:

```text
site/          # datum, terrain and shoreline hypotheses
districts/     # master layout and plot/route assemblies
buildings/     # one stable ID per building; plans, sections and parameters
components/    # masonry bays, roof structures, doors and other original parts
materials/     # procedural definitions with evidence notes
```

Do not add empty building models or arbitrary coordinates to imply completed
work. A dimension schedule must distinguish a measured value from a reconstruction
or an authoring estimate. Store render images and generated CAD/mesh exports
outside the repository, for example under `/tmp/roman-war-city-studies/`.
