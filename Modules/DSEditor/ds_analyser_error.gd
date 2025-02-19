class_name DialogueAnalyserError
extends RefCounted

enum Severity
{
    WARNING,
    ERROR
}

var m_severity: Severity
var m_message: StringName
var m_line: int


func _init(line: int, severity: Severity) -> void:
    m_line = line
    m_severity = severity


func message(text: StringName) -> DialogueAnalyserError:
    m_message = text
    return self
