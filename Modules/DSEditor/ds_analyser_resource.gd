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

func __push_unique(value: StringName, target: Array[StringName]) -> bool:
    if value.is_empty() || target.has(value):
        return false

    target.append(value)
    return true


func __analyse_main(text: String) -> void:
    if !p_mutex.try_lock():
        return

    var lines := text.split(&"\n")
    var errors: Array[DialogueAnalyserError] = []
    reset()

    var line_count := float(lines.size())
    var scene_size_estimate := 0

    for i: int in range(line_count):
        var line := lines[i]
        var line_type := DialogueParser.identify_line(line)

        if m_abort:
            reset()
            p_mutex.unlock()
            analysis_aborted.emit.call_deferred()
            return

        analysis_updated.emit.call_deferred(i / line_count)

        if line.strip_edges().is_empty():
            continue

        # Scan for basic types
        match line_type:
            DialogueParser.DSType.COMMENT:
                continue

            DialogueParser.DSType.CHARACTER:
                if i > 0 && scene_size_estimate < 1:
                    errors.append(
                        __warning(i, &"Previous scene is empty.")
                    )

                __push_unique(line.strip_edges(), p_characters)
                scene_size_estimate = 0

            DialogueParser.DSType.LINE, \
            DialogueParser.DSType.CHOICE:
                scene_size_estimate += 1

            # Bookmarks and events should not have variables in them
            DialogueParser.DSType.EVENT:
                var command_id := line.lstrip(&"@").split(" ")[0]
                scene_size_estimate += 1

                if p_pat_variables.search(command_id) != null:
                    errors.append(
                        __error(i, &"Variables are not supported as event IDs.")
                    )
                    continue

                __push_unique(command_id, p_events)
                continue

            DialogueParser.DSType.BOOKMARK:
                if __push_unique(DialogueParser.unwrap_tag(line), p_bookmarks):
                    continue

                errors.append(
                    __warning(i, &"Unreachable: the first scene with this bookmark will take priority, instead.")
                )

                continue

            DialogueParser.DSType.CHOICE_TARGET:
                continue

        # Scan for variables
        var candidates := p_pat_variables.search_all(line)

        if !candidates.is_empty() && DSTYPE_NO_VARIABLES.has(line_type):
            errors.append(
                __warning(i, &"Variables are not allowed in this type.")
            )
            continue

        for candidate: RegExMatch in candidates:
            __push_unique(candidate.get_string(0), p_variables)

    p_mutex.unlock()
    data_available.emit.call_deferred(errors)


func __warning(line: int, message: StringName) -> DialogueAnalyserError:
    return (DialogueAnalyserError.new(line, DialogueAnalyserError.Severity.WARNING)
            .message(message))


func __error(line: int, message: StringName) -> DialogueAnalyserError:
    return (DialogueAnalyserError.new(line, DialogueAnalyserError.Severity.ERROR)
        .message(message))


#endregion
