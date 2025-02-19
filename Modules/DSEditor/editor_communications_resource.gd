class_name EditorCommunications
extends Resource

signal editor_resetted()
signal editor_save_requested()
signal editor_load_requested()


#region Functions

func notify_new() -> void:
    editor_resetted.emit()


func notify_save() -> void:
    editor_save_requested.emit()


func notify_load() -> void:
    editor_load_requested.emit()

#endregion
