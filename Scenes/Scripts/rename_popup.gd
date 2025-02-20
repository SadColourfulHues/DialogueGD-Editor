class_name RenamePopup
extends PopupPanel

var m_original: String
var p_callback: Callable

@onready
var p_textfield_name: LineEdit = %Name


#region Events

func _ready() -> void:
    p_textfield_name.text_submitted.connect(func(_t): _on_rename_finished())
    %Done.pressed.connect(_on_rename_finished)


func _on_rename_finished() -> void:
    var new_name := p_textfield_name.text

    if new_name.is_empty() || m_original == new_name:
        hide()
        return

    p_callback.call(m_original, new_name)
    hide()

#endregion

#region Functions

func start(original: String, callback: Callable) -> void:
    %Title.text = &"Renaming \"%s\"" % original

    p_textfield_name.placeholder_text = original
    p_textfield_name.grab_focus.call_deferred()

    m_original = original
    p_callback = callback

#endregion
