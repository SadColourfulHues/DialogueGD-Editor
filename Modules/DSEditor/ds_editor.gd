class_name DialogueScriptEditor
extends CodeEdit

# TODO: ImPrOvE sUgGeStIoN lOgIc At SoMe PoInT
# (Check back a couple commits later, if this message is still lhere
# then rip.)

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

	get_v_scroll_bar().scale.x = 0.0


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
	__suggest_main(candidate, line_type, line)

#endregion

#region Utils

func __suggest_main(candidate: String,
					line_type: DialogueParser.DSType,
					line: String) -> void:

	match line_type:
		DialogueParser.DSType.EVENT:
			if __suggest_event_parameters(line, candidate):
				return

			__get_event_suggestions(candidate)

		DialogueParser.DSType.CHOICE:
			__get_choice_param_suggestions(candidate)

		_:
			if candidate.begins_with(&"{"):
				__get_suggestions_from_list(candidate, p_analyser.p_variables)
			elif candidate.begins_with(&"<"):
				__get_suggestions_from_list(candidate, p_analyser.p_characters)


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


func __get_suggestions_from_list_no_strip(candidate: String,
								source: Array[StringName]) -> void:

	for item: StringName in source:
		if !candidate.is_subsequence_of(item):
			continue

		add_code_completion_option(CodeEdit.KIND_VARIABLE, item, item)
	update_code_completion_options(false)


func __get_event_suggestions(candidate: String) -> void:
	for item: StringName in p_analyser.p_events:
		var match_item := &"@" + item

		if !candidate.is_subsequence_of(match_item):
			continue

		add_code_completion_option(
			CodeEdit.KIND_VARIABLE,
			match_item,
			item + &" "
		)

	update_code_completion_options(false)


func __get_unwrapped_variable_suggestions_as_event_parameter(candidate: String) -> void:
	for item: StringName in p_analyser.p_variables:
		var match_item := DialogueParser.unwrap_tag(item)

		if !candidate.is_subsequence_of(match_item):
			continue

		add_code_completion_option(
			CodeEdit.KIND_VARIABLE,
			match_item,
			match_item + &" "
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


func __suggest_event_parameters(line: String, candidate: String) -> bool:
	# For the sake of simplifying things, only do suggestions
	# when the user is currently typing at the end of the line

	# Return true if parameter suggestions is to be prioritised
	# over event names

	if candidate.is_empty() || !line.ends_with(candidate):
		return false

	var command_id := line.substr(1, line.find(&" ") - 1)
	var parameter_index := line.count(&" ")

	match command_id:
		# Event: @jump <bookmark_id>
		&"jump":
			if parameter_index != 1:
				return true

			__get_suggestions_from_list_no_strip(candidate, p_analyser.p_bookmarks)
			return true

		# Event: @jumpif <variable> <bookmark>
		&"jumpif":
			match parameter_index:
				1:
					__get_unwrapped_variable_suggestions_as_event_parameter(candidate)

				2:
					__get_suggestions_from_list_no_strip(candidate, p_analyser.p_bookmarks)

			return true

		# Event: @set <variable> <values ...>
		#		 @(un)flag <variable>
		&"set", &"flag", &"unflag":
			if parameter_index != 1:
				return true

			__get_unwrapped_variable_suggestions_as_event_parameter(candidate)
			return true

	return false

#endregion
