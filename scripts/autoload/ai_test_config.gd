extends Node

## Draft state handed from ai_test_screen.gd to ai_test.gd — the same
## shape CharacterProfile plays for character_screen.gd -> kick_to_kick.
## Kept as its own autoload rather than folded into GameState, which
## deliberately stays "mode and phase only" (see game_state.gd's header).

const MIN_TEAM_SIZE := 1
const MAX_TEAM_SIZE := 18

var team_size := Tuning.TEAM_SIZE:
	set(value):
		team_size = clampi(value, MIN_TEAM_SIZE, MAX_TEAM_SIZE)
		controlled_index = clampi(controlled_index, 0, team_size - 1)

## Which team (if any) has a human-controlled player. NONE means both
## sides run on AIBrain — an AI-vs-AI spectator run, useful on its own as
## a way to watch tuning changes without a human in the way.
var controlled_team := Tuning.Team.HOME

## Slot index within controlled_team that starts under human control.
## switch_player still cycles within that team same as full_game.gd.
var controlled_index := 0

## Spawn at TeamFormation positions instead of full_game.gd's even
## kickoff spread.
var use_formation_start := false

## AI players on a frozen team get PlayerBrain.new() (a no-op brain)
## instead of AIBrain — stand still, useful for isolating the other
## team's behaviour without it being pressured or chased.
var freeze_home := false
var freeze_away := false
