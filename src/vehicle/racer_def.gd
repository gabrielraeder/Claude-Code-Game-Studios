class_name RacerDef
extends Resource
## One knight-dog racer (story 006): name, breed, model and its own default accent colour.
## Data only; the roster is a RacerSet (assets/data/racers/racer_set.tres). In a race the
## kart's identity colour and pennant come from its SLOT, not from this resource; the accent
## colour is for menus (story 007) and for the line-up showcase.
## Implements design/game-brief.md, Features item 6.

## Name shown to players.
@export var display_name: String = "Racer"
## Breed, for the pick screen and tooltips.
@export var breed: String = ""
## Short file-name part of the model (char_dog_<slug>.glb).
@export var slug: StringName = &"mascot"
## glb of the dog (root "Dog", origin at the hip, "Head" node, optional "Ear_L"/"Ear_R").
@export var model_path: String = ""
## Default accent colour (art bible section 4: the dog's own look, not the race slot colour).
@export var default_accent: Color = Color(0.91, 0.27, 0.17)
