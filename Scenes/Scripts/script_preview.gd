class_name ScriptPreview
extends Control

signal scene_changed(scene_idx: int)

var p_playback: DialoguePlayback

@onready
var p_frame_dialogue: Control = %DialogueItems

@onready
var p_frame_flow: Control = %FlowButtons

@onready
var p_frame_choices: Control = %ChoiceButtons

@onready
var p_choice_button_template: Button = %ChoiceTemplate

@onready
var p_label_empty: Label = %EmptyLabel

@onready
var p_label_character: Label = %CharacterID

@onready
var p_label_dialogue: Label = %Dialogue

@onready
var p_btn_advance: Button = %Advance

@onready
var p_btn_restart: Button = %Restart


#region Functions

func set_graph(graph: DialogueGraph) -> void:
    p_playback.set_graph(graph)

    var graph_valid := graph != null

    p_frame_dialogue.visible = graph_valid
    visible = graph_valid

    p_label_empty.visible = !graph_valid

    if !graph_valid:
        return

    p_playback.seek_to_start()
    __notify_scene_change()

#endregion

#region Events

func _ready() -> void:
    p_playback = DialoguePlayback.new()
    p_frame_choices.remove_child(p_choice_button_template)

    p_playback.closed.connect(hide)
    p_playback.character_available.connect(_on_character_id_updated)
    p_playback.dialogue_available.connect(_on_dialogue_updated)
    p_playback.choices_available.connect(_on_choices_updated)

    p_btn_advance.pressed.connect(_on_advance_request)
    p_btn_restart.pressed.connect(_on_reset_request)

    set_graph(null)
    _on_choices_updated([])


func _exit_tree() -> void:
    p_playback.free()
    p_choice_button_template.queue_free()


func _on_advance_request() -> void:
    if p_playback.p_graph == null:
        return

    p_playback.advance()
    __notify_scene_change()


func _on_choice_selected(choice: DialogueChoice) -> void:
    p_playback.accept_choice(choice)
    __notify_scene_change()


func _on_reset_request() -> void:
    if p_playback.p_graph == null:
        return

    p_playback.p_variables.clear()

    p_playback.seek_to_start()
    __notify_scene_change()

#endregion

#region Playback

func _on_character_id_updated(text: StringName) -> void:
    p_label_character.text = text


func _on_dialogue_updated(text: String) -> void:
    p_label_dialogue.text = text


func _on_choices_updated(choices: Array[DialogueChoice]) -> void:
    for node: Control in p_frame_choices.get_children():
        if node is not Button:
            continue

        node.queue_free()

    if choices.is_empty():
        p_frame_choices.visible = false
        p_frame_flow.visible = true
        return

    p_frame_choices.visible = true
    p_frame_flow.visible = false

    for i: int in range(choices.size()):
        var choice := choices[i]
        var choice_button: Button = p_choice_button_template.duplicate()

        p_frame_choices.add_child(choice_button)

        choice_button.text = choice.m_display_text
        choice_button.pressed.connect(_on_choice_selected.bind(choice))

        if i > 0:
            continue

        choice_button.grab_focus.call_deferred()

#endregion

#region Utils

func __notify_scene_change() -> void:
    scene_changed.emit(p_playback.m_index)

#endregion
