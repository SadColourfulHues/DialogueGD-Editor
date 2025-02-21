extends Control

@export
var p_analyser: DialogueAnalyser

@export
var m_colour_log_warning: Color

@export
var m_colour_log_error: Color

@export
var m_colour_highlight_warning: Color

@export
var m_colour_highlight_error: Color

@export
var p_pkg_new_document_popup: PackedScene

@export
var p_pkg_rename_popup: PackedScene

var p_parser: DialogueParser

var m_last_search_coords := Vector2i.ZERO
var m_last_search_line: String

var m_last_saved_path: String
var m_last_exec_line: int

var p_last_error_lines: Array[int]

@onready
var p_script_pad: DialogueScriptEditor = %MainEditor

@onready
var p_preview: ScriptPreview = %ScriptPreview

@onready
var p_frame_info: Control = %InfoFrame

@onready
var p_frame_errors: Control = %WarningFrame

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
var p_list_warnings: ItemList = %Warnings

@onready
var p_field_search := %Search

@onready
var p_analysis_progress: ProgressBar = %AnalysisProgress

@onready
var p_btn_info := %Info

@onready
var p_btn_errors := %Errors

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
    p_parser = DialogueParser.new()
    p_analyser.reset()

    p_preview.scene_changed.connect(_on_preview_scene_changed)
    p_preview.hidden.connect(func(): p_script_pad.gutters_draw_executing_lines = false)

    p_analyser.data_available.connect(_on_analysis_data_available)
    p_analyser.analysis_started.connect(p_analysis_progress.show)
    p_analyser.analysis_aborted.connect(p_analysis_progress.hide)
    p_analyser.analysis_updated.connect(p_analysis_progress.set_value_no_signal)

    p_btn_info.pressed.connect(_on_toggle_info_frame)
    p_btn_errors.pressed.connect(_on_toggle_warnings_frame)
    p_btn_run.pressed.connect(_on_run_pressed)

    p_field_search.text_changed.connect(_on_search_requested)
    p_field_search.focus_exited.connect(p_field_search.clear)

    p_btn_new.pressed.connect(_on_new_document)
    p_btn_open.pressed.connect(_on_open_script)
    p_btn_save.pressed.connect(_on_save_script)
    p_btn_export.pressed.connect(_on_export_script)

    p_list_bookmarks.item_clicked.connect(_on_bookmark_selected)
    p_list_warnings.item_clicked.connect(_on_error_selected)

    __bind_rename_popup(p_list_characters, &"<%s>")
    __bind_rename_popup(p_list_variables, &"{%s}")
    __bind_rename_popup(p_list_events, &"@%s")

    p_analysis_progress.hide()

    # Initial state #
    p_btn_info.button_pressed = false

    p_frame_info.hide()
    p_frame_errors.hide()

    last_saved_path = &""


func _exit_tree() -> void:
    p_parser.free()

    p_analyser.data_available.disconnect(_on_analysis_data_available)
    p_analyser.analysis_started.disconnect(p_analysis_progress.show)
    p_analyser.analysis_aborted.disconnect(p_analysis_progress.hide)
    p_analyser.analysis_updated.disconnect(p_analysis_progress.set_value_no_signal)


func _input(event: InputEvent) -> void:
    SCHUtils.iesetactioncallback(event, get_viewport(), _on_user_input_activated)


func _on_bookmark_selected(index: int, _2: Vector2, mouse_index: int) -> void:
    if mouse_index != MOUSE_BUTTON_LEFT:
        return

    p_script_pad.set_caret_line(
        p_list_bookmarks.get_item_metadata(index)
    )


func _on_error_selected(index: int, _2: Vector2, mouse_index: int) -> void:
    if mouse_index != MOUSE_BUTTON_LEFT:
        return

    p_list_warnings.deselect(index)

    if index < 0 || index >= p_last_error_lines.size():
        return

    p_script_pad.set_caret_line(p_last_error_lines[index])


func _on_run_pressed() -> void:
    if p_preview.visible:
        p_preview.set_graph(null)
        return

    p_script_pad.clear_executing_lines()
    m_last_exec_line = -1

    if p_script_pad.text.strip_edges().is_empty():
        return

    p_script_pad.gutters_draw_executing_lines = true
    p_script_pad.release_focus()

    p_preview.set_graph(p_parser.string_to_graph(p_script_pad.text))


func _on_preview_scene_changed(scene_idx: int) -> void:
    if !p_analyser.p_scene_indices.has(scene_idx):
        return

    var current_exec_line := p_analyser.p_scene_indices[scene_idx]

    if m_last_exec_line != -1:
        p_script_pad.set_line_as_executing(m_last_exec_line, false)

    p_script_pad.set_line_as_executing(current_exec_line, true)
    p_script_pad.set_caret_line(current_exec_line)

    m_last_exec_line = current_exec_line


func _on_new_document() -> void:
    var popup := __start_popup(p_pkg_new_document_popup, p_btn_new)
    popup.get_node(^"%Abort").pressed.connect(popup.hide)
    popup.get_node(^"%Confirm").pressed.connect(_on_new_popup_submit.bind(popup))


func _on_new_popup_submit(popup: Popup) -> void:
    last_saved_path = &""

    p_script_pad.clear()

    p_analyser.request_stop_analysis()
    p_analyser.reset()

    _on_analysis_data_available([], [])
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


func _on_export_script() -> void:
    var dialog := __start_file_dialog(&"*.dfg", &"Dialogue Graph Files", false)
    dialog.title = "Export Graph"

    dialog.file_selected.connect(_on_export_file_selected.bind(dialog))


func _on_export_file_selected(file_path: String, caller: FileDialog) -> void:
    if !file_path.ends_with(&".dgf"):
        file_path += &".dgf"

    var graph := p_parser.string_to_graph(p_script_pad.text)

    if !is_instance_valid(caller):
        caller.queue_free()

    if graph == null:
        return

    DialogueParser.graph_to_file(graph, file_path)


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


func _on_toggle_warnings_frame() -> void:
    p_frame_errors.visible = p_btn_errors.button_pressed


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
    p_field_search.grab_focus()


func _on_analysis_data_available(errors: Array[DialogueAnalyserError],
                                 bookmark_indices: Array[int]) -> void:

    var max_lines := p_script_pad.get_line_count()

    # Warnings and Errors #

    # TODO: Find a better way of doing this
    p_list_warnings.clear()

    var error_count := errors.size()

    for i: int in range(max_lines):
        p_script_pad.set_line_background_color(i, Color(0, 0, 0, 0))

    if error_count > 0 && p_last_error_lines.size() != error_count:
        p_last_error_lines.resize(error_count)

    p_frame_errors.visible = error_count > 0
    p_btn_errors.button_pressed = p_frame_errors.visible

    for i: int in error_count:
        var error := errors[i]
        p_last_error_lines[i] = error.m_line

        p_list_warnings.add_item(
            &"Line %d: %s" % [1 + error.m_line, error.m_message]
        )

        match error.m_severity:
            DialogueAnalyserError.Severity.WARNING:
                p_list_warnings.set_item_custom_fg_color(i, m_colour_log_warning)
                p_script_pad.set_line_background_color(error.m_line, m_colour_highlight_warning)

            DialogueAnalyserError.Severity.ERROR:
                p_list_warnings.set_item_custom_fg_color(i, m_colour_log_error)
                p_script_pad.set_line_background_color(error.m_line, m_colour_highlight_error)

    p_analysis_progress.hide()

    p_list_bookmarks.clear()
    p_list_events.clear()

    # Variables + Characters #
    __fill_list_from_source(p_list_variables, p_analyser.p_variables)
    __fill_list_from_source(p_list_characters, p_analyser.p_characters)

    # Bookmarks #
    for i: int in range(p_analyser.p_bookmarks.size()):
        p_list_bookmarks.add_item(p_analyser.p_bookmarks[i], null, false)
        p_list_bookmarks.set_item_metadata(i, bookmark_indices[i])

    # Events #
    var true_ev_index := 0

    for i: int in range(p_analyser.p_events.size()):
        var event_id := p_analyser.p_events[i]

        if DialogueAnalyser.INBUILT_COMMANDS_SUGGESTIONS.has(event_id):
            continue

        p_list_events.add_item(event_id, null, false)
        p_list_events.set_item_metadata(true_ev_index, event_id)
        true_ev_index += 1

#endregion

#region Utils

func __fill_list_from_source(list: ItemList, source: Array[StringName]) -> void:
    list.clear()

    for i: int in range(source.size()):
        var item: String = DialogueParser.unwrap_tag(source[i])

        list.add_item(item, null, false)
        list.set_item_metadata(i, item)


func __bind_rename_popup(list: ItemList, template_string: StringName) -> void:
    list.item_clicked.connect((func(index: int, _2: Vector2, mouse_index: int):
        if mouse_index != MOUSE_BUTTON_LEFT:
            return

        __start_rename_popup(
            list,
            template_string,
            list.get_item_metadata(index)
        )
    ))


func __start_popup(template: PackedScene,
                   parent_ref: Control,
                   from_top := true) -> PopupPanel:

    var popup: PopupPanel = template.instantiate()

    var rect: Rect2 = parent_ref.get_global_rect()

    if from_top:
        rect.position.y += rect.size.y
    else:
        rect.position.x += rect.size.x

    popup.popup_exclusive_on_parent(
        parent_ref,
        rect
    )

    popup.popup_hide.connect(popup.queue_free)
    return popup


func __start_rename_popup(parent_ref: Control,
                          template_string: StringName,
                          original_text: String) -> void:

    var popup: RenamePopup = __start_popup(p_pkg_rename_popup, parent_ref, false)

    popup.start(original_text, (func(original: String, updated: String):

        var caret_line := p_script_pad.get_caret_line()
        var caret_col := p_script_pad.get_caret_column()

        p_script_pad.text = p_script_pad.text.replace(template_string % original,
                                                      template_string % updated)

        p_analyser.start_analysis_on_main(p_script_pad.text)

        # Attempt to restore caret position
        p_script_pad.set_caret_line(caret_line)
        p_script_pad.set_caret_column(caret_col)
    ))


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
