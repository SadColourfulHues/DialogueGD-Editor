class_name DialogueScriptHighlighter
extends SyntaxHighlighter

@export
var m_colour_default: Color
@export
var m_colour_comment: Color
@export
var m_colour_bookmark: Color
@export
var m_colour_command: Color
@export
var m_colour_character: Color
@export
var m_colour_choice: Color
@export
var m_colour_choice_requirement: Color
@export
var m_colour_choice_target: Color
@export
var m_colour_variable: Color

var p_editor: TextEdit = null


#region Highlighter

func _get_line_syntax_highlighting(line_index: int) -> Dictionary[int, Dictionary]:
    if p_editor == null:
        p_editor = get_text_edit()

    var base_colour := m_colour_default
    var line := p_editor.get_line(line_index)
    var type := DialogueParser.identify_line(line)

    if line.is_empty():
        return {}

    if type != DialogueParser.DSType.LINE:
        match type:
            DialogueParser.DSType.CHARACTER:
                base_colour = m_colour_character

            DialogueParser.DSType.COMMENT:
                base_colour = m_colour_comment

            DialogueParser.DSType.BOOKMARK:
                base_colour = m_colour_bookmark

            DialogueParser.DSType.EVENT:
                base_colour = m_colour_command

            DialogueParser.DSType.CHOICE:
                base_colour = m_colour_choice

            DialogueParser.DSType.CHOICE_REQUIREMENT:
                base_colour = m_colour_choice_requirement

            DialogueParser.DSType.CHOICE_TARGET:
                base_colour = m_colour_choice_target

    # Disallow variable highlighting on lines where it's not usable #
    if DialogueAnalyser.DSTYPE_NO_VARIABLES.has(type):
        return { 0: __highlight_def(base_colour) }

    var vlist: Dictionary[int, Dictionary] = { 0: __highlight_def(base_colour) }
    var var_matches := DialogueAnalyser.p_pat_variables.search_all(line)

    for vmatch: RegExMatch in var_matches:
        vlist[vmatch.get_start(0)] = __highlight_def(m_colour_variable)
        vlist[vmatch.get_end(0)] = __highlight_def(base_colour)

    return vlist

#endregion

#region Utils

func __highlight_def(colour: Color) -> Dictionary[StringName, Color]:
    return { &"color": colour }

#endregion
