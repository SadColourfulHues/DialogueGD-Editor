extends Control

@export
var p_communications: EditorCommunications

@export
var p_analyser: DialogueAnalyser

@export
var m_colour_search: Color

@export
var p_pkg_new_document_popup: PackedScene

var m_last_search_coords := Vector2i.ZERO
var m_last_search_line: String

var m_last_saved_path: String

@onready
var p_script_pad: TextEdit = %MainEditor

@onready
var p_frame_info: Control = %InfoFrame

@onready
var p_label_last_saved_path: Label = %LastSavedFileName

@onready
var p_list_characters: ItemList = %Characters

@onready
var p_list_variables: ItemList = %Variables

@onready
var p_list_bookmarks: ItemList = %Bookmarks

@onready
var p_list_events: ItemList = %Events

@onready
var p_field_search := %Search

@onready
var p_analysis_progress: ProgressBar = %AnalysisProgress

@onready
var p_btn_info := %Info

@onready
var p_btn_run := %Run

@onready
var p_btn_new := %New

@onready
var p_btn_open = %Open

@onready
var p_btn_save := %Save

@onready
var p_btn_export := %Export


#region Events

func _ready() -> void:
    p_analyser.reset()

    p_analyser.data_available.connect(_on_analysis_data_available)
    p_analyser.analysis_started.connect(p_analysis_progress.show)
    p_analyser.analysis_aborted.connect(p_analysis_progress.hide)
    p_analyser.analysis_updated.connect(p_analysis_progress.set_value_no_signal)

    p_btn_info.pressed.connect(_on_toggle_info_frame)
    p_field_search.text_changed.connect(_on_search_requested)
    p_field_search.focus_exited.connect(p_field_search.clear)

    p_btn_new.pressed.connect(_on_new_document)
    p_btn_open.pressed.connect(_on_open_script)
    p_btn_save.pressed.connect(_on_save_script)

    p_analysis_progress.hide()

    # Initial state #
    p_btn_info.button_pressed = false
    p_frame_info.hide()

    last_saved_path = &""


func _exit_tree() -> void:
    p_analyser.data_available.disconnect(_on_analysis_data_available)
    p_analyser.analysis_started.disconnect(p_analysis_progress.show)
    p_analyser.analysis_aborted.disconnect(p_analysis_progress.hide)
    p_analyser.analysis_updated.disconnect(p_analysis_progress.set_value_no_signal)


func _input(event: InputEvent) -> void:
    SCHUtils.iesetactioncallback(event, get_viewport(), _on_user_input_activated)


func _on_new_document() -> void:
    var popup := __start_popup(p_pkg_new_document_popup, p_btn_new)
    popup.get_node(^"%Abort").pressed.connect(popup.hide)
    popup.get_node(^"%Confirm").pressed.connect(_on_new_popup_submit.bind(popup))


func _on_new_popup_submit(popup: Popup) -> void:
    last_saved_path = &""

    p_script_pad.clear()

    p_analyser.request_stop_analysis()
    p_analyser.reset()

    _on_analysis_data_available([])
    popup.queue_free()


func _on_open_script() -> void:
    var dialog := __start_file_dialog(&"*.txt", &"Text Files", true)
    dialog.file_selected.connect(_on_open_script_file_selected.bind(dialog))


func _on_open_script_file_selected(file_path: String, caller: FileDialog) -> void:
    last_saved_path = file_path
    p_script_pad.text = FileAccess.get_file_as_string(file_path)

    p_analyser.start_analysis_on_main(p_script_pad.text)

    if !is_instance_valid(caller):
        return

    caller.queue_free()


func _on_save_script() -> void:
    if !m_last_saved_path.is_empty():
        _on_save_script_file_selected(m_last_saved_path, null)
        return

    var dialog := __start_file_dialog(&"*.txt", &"Text Files", false)
    dialog.file_selected.connect(_on_save_script_file_selected.bind(dialog))


func _on_save_script_file_selected(file_path: String, caller: FileDialog) -> void:
    var file := FileAccess.open(file_path, FileAccess.WRITE)

    if !file.is_open():
        return

    file.store_string(p_script_pad.text)
    file.close()

    if m_last_saved_path.is_empty():
        last_saved_path = file_path

    if !is_instance_valid(caller):
        return

    caller.queue_free()


func _on_user_input_activated(event: InputEvent) -> void:
    var viewport := get_viewport()

    if event.is_action_pressed(&"search"):
        p_field_search.grab_focus()
        viewport.set_input_as_handled()

    elif p_field_search.has_focus() && event.is_action_pressed(&"perform_search"):
        _on_search_requested(p_field_search.text)

    elif event.is_action_pressed(&"reset_state"):
        p_field_search.clear()
        p_field_search.release_focus()
        p_script_pad.grab_focus()


func _on_toggle_info_frame() -> void:
    p_frame_info.visible = p_btn_info.button_pressed


func _on_search_requested(search_text: String) -> void:
    if p_script_pad.text.is_empty() || search_text.is_empty():
        p_script_pad.set_search_text("")
        return

    if m_last_search_line != search_text:
        m_last_search_coords = Vector2i.ZERO

    var search_flags := 0
    var reverse := Input.is_action_pressed(&"search_reverse_flag")

    p_script_pad.set_search_text(search_text)

    if reverse:
        search_flags = TextEdit.SEARCH_BACKWARDS

    var next_coords := p_script_pad.search(
        search_text,
        search_flags,
        m_last_search_coords.y,
        m_last_search_coords.x
    )

    if next_coords.x == -1 && next_coords.y == -1:
        m_last_search_coords = Vector2i.ZERO
    else:
        m_last_search_coords = next_coords
        m_last_search_coords.x += -1 if reverse else 1

    m_last_search_line = search_text

    p_script_pad.set_caret_line(next_coords.y)
    p_script_pad.set_caret_column(next_coords.x)


func _on_analysis_data_available(errors: Array[DialogueAnalyserError]) -> void:

    var max_lines := p_script_pad.get_line_count()

    # TODO: Find a better way of doing this
    for i: int in range(max_lines):
        p_script_pad.set_line_background_color(i, Color(0, 0, 0, 0))

    for error: DialogueAnalyserError in errors:
        match error.m_severity:
            DialogueAnalyserError.Severity.WARNING:
                p_script_pad.set_line_background_color(error.m_line, Color.ORANGE)

            DialogueAnalyserError.Severity.ERROR:
                p_script_pad.set_line_background_color(error.m_line, Color.RED)


    p_analysis_progress.hide()

    p_list_characters.clear()
    p_list_variables.clear()
    p_list_bookmarks.clear()
    p_list_events.clear()

    for variable: StringName in p_analyser.p_variables:
        p_list_variables.add_item(DialogueParser.unwrap_tag(variable), null, false)

    for character_id: StringName in p_analyser.p_characters:
        p_list_characters.add_item(DialogueParser.unwrap_tag(character_id), null, false)

    for bookmark: StringName in p_analyser.p_bookmarks:
        p_list_bookmarks.add_item(bookmark, null, false)

    for event_id: StringName in p_analyser.p_events:
        if DialogueAnalyser.INBUILT_COMMANDS_SUGGESTIONS.has(event_id):
            continue

        p_list_events.add_item(event_id, null, false)

#endregion

#region Utils

func __start_popup(template: PackedScene, parent_ref: Control) -> PopupPanel:
    var popup: PopupPanel = template.instantiate()

    var rect: Rect2 = parent_ref.get_global_rect()
    rect.position.y += rect.size.y

    popup.popup_exclusive_on_parent(
        parent_ref,
        rect
    )

    popup.popup_hide.connect(popup.queue_free)
    return popup


func __start_file_dialog(filter: StringName,
                         description: StringName,
                         read: bool) -> FileDialog:

    var dialog := FileDialog.new()

    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.use_native_dialog = true

    dialog.file_mode = (
        FileDialog.FILE_MODE_OPEN_FILE
        if read else
        FileDialog.FILE_MODE_SAVE_FILE
    )

    dialog.add_filter(filter, description)
    dialog.canceled.connect(dialog.queue_free)

    if read:
        dialog.add_filter(&"*", &"All Files")

    dialog.popup_exclusive_centered(
        get_tree().root,
        Vector2i(320, 480)
    )

    return dialog

#endregion

#region Properties

var last_saved_path: String:
    get():
        return m_last_saved_path

    set(value):
        m_last_saved_path = value

        if m_last_saved_path.is_empty():
            p_label_last_saved_path.text = &""
            return

        p_label_last_saved_path.text = (
            &"Saving to \"%s\"" % m_last_saved_path.split(&"/")[-1]
        )

#endregion
