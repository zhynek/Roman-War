# Original model source

No geometry has been authored yet. This directory will hold original parametric
model source and reviewed dimension schedules for this city. Follow the workspace
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
