class_name DialogueAnalyser
extends Resource

const INBUILT_COMMANDS_SUGGESTIONS: Array[StringName] = [
    &"set", &"jump", &"jumpif", &"flag", &"unflag", &"exit"
]

const DSTYPE_NO_VARIABLES: Array[DialogueParser.DSType] = [
        DialogueParser.DSType.BOOKMARK,
        DialogueParser.DSType.CHOICE_TARGET,
        DialogueParser.DSType.CHOICE_REQUIREMENT,
        DialogueParser.DSType.COMMENT
]

signal analysis_started()
signal analysis_updated(fac: float)
signal analysis_aborted()

signal data_available()

static var p_pat_variables = RegEx.create_from_string(&"{([\\d\\w_-]+)}")

var p_mutex: Mutex
var p_thread: Thread
var m_abort: bool

var p_characters: Array[StringName]
var p_bookmarks: Array[StringName]
var p_variables: Array[StringName]
var p_events: Array[StringName]


func _init() -> void:
    p_mutex = Mutex.new()


#region Events

func _notification(what: int) -> void:
    # Thread cleanup #
    if (what != NOTIFICATION_PREDELETE ||
        p_thread == null ||
        !p_thread.is_started()):

        return

    m_abort = true
    p_thread.wait_to_finish()

#endregion

#region Functions

func reset() -> void:
    m_abort = false

    p_characters.clear()
    p_bookmarks.clear()
    p_variables.clear()

    p_events.clear()
    p_events.append_array(INBUILT_COMMANDS_SUGGESTIONS)


func start_analysis(text: String) -> void:
    if p_thread != null && p_thread.is_started():
        m_abort = true
        p_thread.wait_to_finish()
        return

    p_thread = Thread.new()
    p_thread.start(__analyse_main.bind(text), Thread.PRIORITY_HIGH)

    analysis_started.emit()


func start_analysis_on_main(text: String) -> void:
    # Prevent accidental writes from subthread
    if p_thread != null && p_thread.is_started():
        m_abort = true
        p_thread.wait_to_finish()

    __analyse_main(text)


func request_stop_analysis() -> void:
    m_abort = true

#endregion

#region Utils

func __push_unique(value: StringName,
                   target: Array[StringName],
                   callback := Callable()) -> bool:

    if value.is_empty() || target.has(value):
        return false

    target.append(value)

    if callback.is_valid():
        callback.call()

    return true


func __analyse_main(text: String) -> void:
    if !p_mutex.try_lock():
        return

    var lines := text.split(&"\n")

    var errors: Array[DialogueAnalyserError] = []
    var bookmark_indices: Array[int] = []

    reset()

    var line_count := float(lines.size())
    var scene_size_estimate := 0

    var is_choice_start := false
    var num_unclosed_choices := 0
    var last_scene_start_line := 0
    var last_choice_start_line := 0

    for i: int in range(line_count):
        var line := lines[i]
        var line_type := DialogueParser.identify_line(line)

        if m_abort:
            reset()
            p_mutex.unlock()
            analysis_aborted.emit.call_deferred()
            return

        analysis_updated.emit.call_deferred(i / line_count)

        if (line_type == DialogueParser.DSType.COMMENT ||
            line.strip_edges().is_empty()):

            continue

        # Scan for variables/var-in-type compatibility
        var candidates := p_pat_variables.search_all(line)

        if !candidates.is_empty() && DSTYPE_NO_VARIABLES.has(line_type):
            errors.append(
                __warning(i, &"Variables are not allowed in this type.")
            )
            continue

        for candidate: RegExMatch in candidates:
            __push_unique(candidate.get_string(0), p_variables)

        # Scan for basic types
        match line_type:
            DialogueParser.DSType.CHARACTER:

                if num_unclosed_choices > 0:
                    errors.append(
                        __error(last_choice_start_line, &"All choices must have a target bookmark.")
                    )

                if scene_size_estimate > 0:
                    last_scene_start_line = i

                if i > 0 && scene_size_estimate < 1:
                    errors.append(
                        __warning(last_scene_start_line, &"Scene is empty.")
                    )

                __push_unique(line.strip_edges(), p_characters)

                scene_size_estimate = 0

            DialogueParser.DSType.LINE:
                scene_size_estimate += 1

            DialogueParser.DSType.CHOICE:
                if !is_choice_start:
                    last_choice_start_line = i
                    num_unclosed_choices += 1

                scene_size_estimate += 1
                is_choice_start = true

            DialogueParser.DSType.EVENT:
                var command_id := line.substr(0, line.find(&" "))
                var has_multi_の := command_id.count(&"@") > 1
                command_id = command_id.lstrip(&"@")

                # Checks: Command ID #
                if has_multi_の:
                    errors.append(
                        __warning(i, &"Multiple '@' in event IDs are ignored, its name then becomes \"%s\"" % command_id)
                    )

                scene_size_estimate += 1

                if p_pat_variables.search(command_id) != null:
                    errors.append(
                        __error(i, &"Variables are not supported in event IDs.")
                    )
                    continue

                # Special case: variable-setter events
                match command_id:
                    &"flag", &"set":
                        __push_unique(&"{%s}" % __extract_first_param(line), p_variables)

                __push_unique(command_id, p_events)

            DialogueParser.DSType.BOOKMARK:
                var bookmark := DialogueParser.unwrap_tag(line)

                if __push_unique(bookmark,
                                 p_bookmarks,
                                 bookmark_indices.append.bind(i)):

                    continue

                errors.append(
                    __warning(i, &"Unreachable: the first scene with this bookmark will take priority, instead.")
                )

            DialogueParser.DSType.CHOICE_TARGET:
                if is_choice_start:
                    num_unclosed_choices = max(0, num_unclosed_choices - 1)

                is_choice_start = false

    p_mutex.unlock()
    data_available.emit.call_deferred(errors, bookmark_indices)


func __extract_first_param(line: String) -> String:
    var param_start := 1 + line.find(&" ")
    var param_end := line.findn(&" ", param_start)

    if param_end == -1:
        return line.substr(param_start, -1)

    return line.substr(param_start, (param_end - param_start))


func __warning(line: int, message: StringName) -> DialogueAnalyserError:
    return (DialogueAnalyserError.new(line, DialogueAnalyserError.Severity.WARNING)
            .message(message))


func __error(line: int, message: StringName) -> DialogueAnalyserError:
    return (DialogueAnalyserError.new(line, DialogueAnalyserError.Severity.ERROR)
        .message(message))


#endregion
