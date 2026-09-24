# TrackOSC Costumes – making a costume

A costume is one SVG file with named layers. TrackOSC Costumes places each
named layer on the tracked body, face or hands; everything else is drawn
where it sits in the drawing, fitted to the stage (scenery).

## The layer names

| Name | Follows | Notes |
|---|---|---|
| `bone:torso` | shoulder midpoint → hip midpoint | top of the art = shoulders |
| `bone:shoulders`, `bone:hips` | left → right joint | horizontal art |
| `bone:neck` | head centre → shoulder midpoint | |
| `bone:upperArm:left` / `:right` | shoulder → elbow | |
| `bone:forearm:left` / `:right` | elbow → wrist | |
| `bone:hand:left` / `:right` | wrist → a little beyond | |
| `bone:thigh:left` / `:right` | hip → knee | |
| `bone:shin:left` / `:right` | knee → ankle | |
| `bone:foot:left` / `:right` | ankle → a little beyond | usually `.fixed` |
| `head` | left ear → right ear | horizontal art; eyes or the nose when ears are hidden |
| `face:leftEye`, `face:rightEye`, `face:leftBrow`, `face:rightBrow`, `face:nose`, `face:mouth`, `face:jaw`, `face:face` | the Face Landmarks cluster | without landmarks they ride on the head; the mouth opens with the lips |
| `hand:palm`, `hand:thumb`, `hand:index`, `hand:middle`, `hand:ring`, `hand:pinky` | the Hands detector's joints | add `:1`, `:2` or `:3` for one phalanx and `:left`/`:right` for a side; without hand data they sit at the body's wrist |
| `guide:torso`, `guide:shoulders` | measured, never drawn | a two-point line: how big the figure is in your drawing |
| `pivot` | inside any layer | a two-point line: the layer's own axis (start → end) |

Flags after a dot: `.stretch` (lengthen along the bone, keep the width),
`.fixed` (never scale with the bone, only with the figure), `.noflip`
(do not mirror when the person faces away), `.front` / `.back` (only
when facing the camera / away). Names are case-insensitive; spaces,
hyphens and underscores are ignored, so `Bone: Upper Arm: Left` works.

The person's **left** is on the picture's **right**: draw the figure as
if it were facing you. When the tracked person turns their back, every
layer without `.noflip` is mirrored.

## Exporting

- **Illustrator**: name layers or groups as above (`bone:torso`). File →
  Export → Export As → SVG, Styling *Internal CSS* or *Presentation
  Attributes*, Object IDs *Layer Names*, Decimal 2, untick Responsive.
  Illustrator writes `:` as `_x3A_` and `.` as `_x2E_` – that is fine.
- **Inkscape**: name layers (Layer → Layers and Objects, double-click a
  name). Save as *Inkscape SVG* or *Plain SVG*; the label is kept either way.
- **Figma**: name the frames or groups and export the top frame as SVG
  with *Include "id" attribute* ticked.
- **Affinity Designer**: name the layers; File → Export → SVG, tick
  *Export text as curves* and *Add line breaks*; the names come through as
  `serif:id`.

Things the app does not draw: gradients and patterns (flatten them),
`<use>` clones (expand them), clip paths, masks, filters, text (convert to
outlines) and embedded images. The inspector lists what was skipped.

Put your files in a folder and choose it with **Choose Folder…**; the app
reloads a costume when you save it, so keep the drawing app open and
watch the stage.
