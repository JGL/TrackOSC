# TrackOSC 3D Costumes – models

Three ways to dress the 3D body pose (`/poses3d/arr`, so turn on **3D
Body** on the sender):

1. **Mannequin** – built in. Capsules on every bone; works the moment 3D
   poses arrive. **Blocks** is the same idea with boxes.
2. **A rigged model** (`.usdz`, `.usd`, `.usda`, `.usdc`, `.reality`)
   whose skeleton follows Apple's motion-capture rig: the 91 joints named
   `root`, `hips_joint`, `spine_1_joint` … `left_forearm_joint`,
   `right_upLeg_joint` and so on, in Apple's hierarchy, rigged in a T-pose
   with +Y up, facing +Z, the character's left hand along +X and each
   joint's +X pointing down its bone. That is the rig ARKit's body
   tracking drives, so any model made for it (or Apple's own Biped Robot,
   from developer.apple.com/sample-code/ar/Biped-Robot.zip) works here.
   Rig in Maya, Blender or Cinema 4D, or rename a Mixamo rig; Reality
   Converter turns GLTF, USD and FBX into USDZ. TrackOSC drives the hips,
   spine, neck, head, shoulders, arms, hands, legs and feet; the rest can
   stay unskinned. The **Rig** tab lists any joints that are missing.
   `Blocky.usda` here is a hand-made example on the exact rig: open it in
   a text editor to see the joint list and bind transforms.
3. **A folder of parts** – no rigging at all. Put one model per bone in a
   folder, named `torso`, `neck`, `head`, `upperArm-left`, `forearm-left`,
   `hand-left`, `thigh-left`, `shin-left`, `foot-left` (and `-right`),
   `shoulders`, `hips`. Each part's longest axis is laid along its bone
   (top to bottom for tall parts, so model a forearm standing up with the
   elbow at the top) and scaled to the bone's length.

Choose a folder with **Choose Folder…**: single model files in it are
rigged costumes, sub-folders of part files are parts costumes. The app
reloads when files change.
