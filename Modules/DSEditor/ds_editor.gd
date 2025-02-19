class_name DialogueScriptEditor
extends CodeEdit

@export
var p_communications: EditorCommunications

@export
var p_analyser: DialogueAnalyser

var p_analyse_debounce: Timer
var p_parser: DialogueParser


#region Events

func _ready() -> void:
	p_parser = DialogueParser.new()

	text_changed.connect(_on_text_edited)

	p_analyse_debounce = Timer.new()
	p_analyse_debounce.one_shot = true
	p_analyse_debounce.wait_time = 0.5
	p_analyse_debounce.timeout.connect(_on_request_start_analysis)
	add_child.call_deferred(p_analyse_debounce)

	get_v_scroll_bar().scale = Vector2.ZERO


func _exit_tree() -> void:
	p_parser.free()


func _on_request_start_analysis() -> void:
	p_analyser.start_analysis(text)


func _on_text_edited() -> void:
	if text.is_empty():
		return

	# Update script analysis data
	if !p_analyse_debounce.is_stopped():
		p_analyse_debounce.stop()

	p_analyse_debounce.start()

	var line := get_line(get_caret_line(0))
	var line_type := DialogueParser.identify_line(line)

	# Don't do anything on non-essential lines
	if (text.is_empty() || line_type == DialogueParser.DSType.COMMENT):
		return

	# Extract the current word the user is typing
	var candidate := ""

	var cursor_start := get_caret_column(0)
	var line_len := line.length()

	for i: int in range(min(line_len - 1, cursor_start + 1), -1, -1):
		if line[i] == ' ':
			break

		candidate += line[i]

	candidate = candidate.reverse().strip_edges()

	if candidate.is_empty():
		return

	# Update suggestions
	__suggest_main(candidate, line_type)

#endregion

#region Utils

func __suggest_main(candidate: String,
					line_type: DialogueParser.DSType) -> void:

	match line_type:
		DialogueParser.DSType.CHOICE:
			__get_choice_param_suggestions(candidate)

		_:
			if candidate.begins_with(&"{"):
				__get_suggestions_from_list(candidate, p_analyser.p_variables)
			elif candidate.begins_with(&"<"):
				__get_suggestions_from_list(candidate, p_analyser.p_characters)
			elif candidate.begins_with(&"@"):
				__get_event_suggestions(candidate)


func __get_suggestions_from_list(candidate: String,
								source: Array[StringName]) -> void:

	for item: StringName in source:
		if !candidate.is_subsequence_of(item):
			continue

		add_code_completion_option(
			CodeEdit.KIND_VARIABLE,
			DialogueParser.unwrap_tag(item),
			item.substr(1)
		)

	update_code_completion_options(false)


func __get_event_suggestions(candidate: String) -> void:
	for item: StringName in p_analyser.p_events:
		var match_item := &"@" + item

		if !candidate.is_subsequence_of(match_item):
			continue

		add_code_completion_option(
			CodeEdit.KIND_VARIABLE,
			match_item,
			item
		)

	update_code_completion_options(false)


func __get_choice_param_suggestions(candidate: String) -> void:
	# TODO: Make these checks less chaotic
	if !candidate.begins_with(&"["):
		return

	var crmode := candidate.begins_with(&"[[")
	candidate = candidate.lstrip(&" \t[")

	# choice requirement mode #
	if crmode:
		for item: StringName in p_analyser.p_variables:
			if !candidate.is_subsequence_of(item):
				continue

			add_code_completion_option(
				CodeEdit.KIND_VARIABLE,
				DialogueParser.unwrap_tag(item),
				DialogueParser.unwrap_tag(item) + &"]]"
			)

	# choice target mode #
	else:
		for item: StringName in p_analyser.p_bookmarks:

			if !candidate.is_subsequence_of(item):
				continue

			add_code_completion_option(
				CodeEdit.KIND_MEMBER,
				item,
				item + &"]"
			)

	update_code_completion_options(false)

#endregion
