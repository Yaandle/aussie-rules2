class_name TutorialDummyBrain
extends PlayerBrain

## Drives the kick-to-kick rival during the tackling tutorial (TackleTutorial)
## instead of its usual AIBrain. The tutorial needs a body that jogs *straight
## at the player* and then just stands there holding the ball to be tackled or
## bumped — the exact opposite of AIBrain, which runs toward its own goal and
## disposes the ball the moment it's pressured.
##
## Deliberately minimal: extends PlayerBrain directly (not AIBrain) and
## overrides only wish_direction()/gait(). Every wants_* stays the base false,
## so the dummy never kicks, handballs, marks, tackles or bumps — it can only
## move. Same "override just what you need" shape as CommandBrain, but with
## nothing underneath to think first.

## Where to run — the player's controller. Set per rep by TackleTutorial.
var target: PlayerController = null

## Metres from the target at which the dummy stops and holds position. 0 means
## "run all the way into contact" (the standing-tackle / lunge / bump steps);
## a small positive value (~TACKLE_TUTORIAL_DIVE_HOLD_DISTANCE) holds the dummy
## just outside arm's reach so the only way to connect is the slide dive-in.
var stop_distance := 0.0

## 0..1 run pace while closing. Held at a jog rather than a full sprint so the
## player has time to read the approach and apply the taught control.
var run_gait := 0.85


func wish_direction(controller: PlayerController) -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var to_target := target.global_position - controller.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist <= stop_distance or dist < 0.001:
		return Vector3.ZERO
	return to_target / dist


## Flat run pace. When the dummy is inside stop_distance, wish_direction()
## returns zero and PlayerController's own "wish.length_squared() > 0"
## locomotion gate parks it — no need to also zero the gait here.
func gait() -> float:
	return run_gait
