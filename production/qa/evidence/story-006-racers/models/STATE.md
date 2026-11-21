# Story 006 models: state (technical-artist)

All deliverables done: tools/blender scripts, 2 vehicle .glb, 8 dog .glb, preview PNGs in this folder
(3/4 per model, rear 3/4 per vehicle, chase_*_all_dogs sheets, dog_lineup, silhouettes_64px and _x4).
Regenerate: blender --background --python tools/blender/make_vehicles.py | make_dogs.py | render_previews.py
Sheet order (left to right, top to bottom): mascot, sunny, bolt, fern, violet, frost, cinder, skye.
silhouettes_64px rows: 1 vehicle views + mascot on each; 2 dogs on cart (chase); 3 dogs on bike; 4 dogs alone, front.
Dog line-up image is viewed from the front, so slot 1 (mascot) appears on the RIGHT.
