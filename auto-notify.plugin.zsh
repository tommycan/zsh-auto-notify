export AUTO_NOTIFY_VERSION="0.8.0"

# Time it takes for a notification to expire
[[ -z "$AUTO_NOTIFY_EXPIRE_TIME" ]] &&
    export AUTO_NOTIFY_EXPIRE_TIME=8000
# Threshold in seconds for when to automatically show a notification
[[ -z "$AUTO_NOTIFY_THRESHOLD" ]] &&
    export AUTO_NOTIFY_THRESHOLD=10
# List of commands/programs to ignore sending notifications for
[[ -z "$AUTO_NOTIFY_IGNORE" ]] &&
    export AUTO_NOTIFY_IGNORE=(
        'vim'
        'nvim'
        'less'
        'more'
        'man'
        'tig'
        'watch'
        'git commit'
        'top'
        'htop'
        'ssh'
        'nano'
    )

function _auto_notify_format() {
    local MESSAGE="$1"
    local command="$2"
    local elapsed="$3"
    local exit_code="$4"
    local dir="$5"
    MESSAGE="${MESSAGE//\%command/$command}"
    MESSAGE="${MESSAGE//\%elapsed/$elapsed}"
    MESSAGE="${MESSAGE//\%exit_code/$exit_code}"
    MESSAGE="${MESSAGE//\%dir/$dir}"
    printf "%s" "$MESSAGE"
}

function _auto_notify_message() {
    local command="$1"
    local elapsed="$2"
    local exit_code="$3"
    local dir="$4"
    local platform="$(uname)"
    # Run using echo -e in order to make sure notify-send picks up new line
    local DEFAULT_TITLE="%command"
    # local DEFAULT_BODY="$(echo -e "Total time: %elapsed seconds\nExit code: %exit_code")"
    # local DEFAULT_TITLE="\"%command\" Completed. Dir %dir"
    local DEFAULT_BODY="$(echo -e "Total time: %elapsed seconds\nExit code: %exit_code\nDir: %dir")"

    local title="${AUTO_NOTIFY_TITLE:-$DEFAULT_TITLE}"
    local text="${AUTO_NOTIFY_BODY:-$DEFAULT_BODY}"

    title="$(_auto_notify_format "$title" "$command" "$elapsed" "$exit_code" "$dir")"
    body="$(_auto_notify_format "$text" "$command" "$elapsed" "$exit_code" "$dir")"

    if [[ "$platform" == "Linux" ]]; then
        local urgency="normal"
        if [[ "$exit_code" != "0" ]]; then
            urgency="critical"
        fi
        if [[ ! -z "$SSH_CONNECTION" ]]; then
            ip_remote=`echo $SSH_CONNECTION | awk '{print $1}'`
            ssh "$ip_remote" notify-send \"$title\" \"$body\" --app-name=zsh --urgency=$urgency --expire-time=$AUTO_NOTIFY_EXPIRE_TIME
        else
            notify-send "$title" "$body" --app-name=zsh "--urgency=$urgency" "--expire-time=$AUTO_NOTIFY_EXPIRE_TIME"
        fi
    elif [[ "$platform" == "Darwin" ]]; then
        osascript \
          -e 'on run argv' \
          -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
          -e 'end run' \
          "$body" "$title"
    else
        printf "Unknown platform for sending notifications: $platform\n"
        printf "Please post an issue on gitub.com/MichaelAquilina/zsh-auto-notify/issues/\n"
    fi
}

function _is_auto_notify_ignored() {
    local command="$1"
    # split the command if its been piped one or more times
    local command_list=("${(@s/|/)command}")
    local target_command="${command_list[-1]}"
    # Remove leading whitespace
    target_command="$(echo "$target_command" | sed -e 's/^ *//')"

    # Remove sudo prefix from command if detected
    if [[ "$target_command" == "sudo "* ]]; then
        target_command="${target_command/sudo /}"
    fi

    # If AUTO_NOTIFY_WHITELIST is defined, then auto-notify will ignore
    # any item not defined in the white list
    # Otherwise - the alternative (default) approach is used where the
    # AUTO_NOTIFY_IGNORE blacklist is used to ignore commands

    if [[ -n "$AUTO_NOTIFY_WHITELIST" ]]; then
        for allowed in $AUTO_NOTIFY_WHITELIST; do
            if [[ "$target_command" == "$allowed"* ]]; then
                print "no"
                return
            fi
        done
        print "yes"
    else
        for ignore in $AUTO_NOTIFY_IGNORE; do
            if [[ "$target_command" == "$ignore"* ]]; then
                print "yes"
                return
            fi
        done
        print "no"
    fi
}

function _auto_notify_send() {
    # Immediately store the exit code before it goes away
    local exit_code="$?"

    if [[ -z "$AUTO_COMMAND" && -z "$AUTO_COMMAND_START" ]]; then
        return
    fi

    if [[ "$(_is_auto_notify_ignored "$AUTO_COMMAND_FULL")" == "no" ]]; then
        local current="$(date +"%s")"
        let "elapsed = current - AUTO_COMMAND_START"

        if [[ $elapsed -gt $AUTO_NOTIFY_THRESHOLD ]]; then
            _auto_notify_message "$AUTO_COMMAND" "$elapsed" "$exit_code" "$AUTO_COMMAND_DIR"
        fi
    fi

    # Empty tracking so that notifications are not
    # triggered for any commands not run (e.g ctrl+C when typing)
    _auto_notify_reset_tracking
}

function _auto_notify_track() {
    # $1 is the string the user typed, but only when history is enabled
    # $2 is a single-line, size-limited version of the command that is always available
    # To still do something useful when history is disabled, although with reduced functionality, fall back to $2 when $1 is empty
    AUTO_COMMAND="${1:-$2}"
    AUTO_COMMAND_FULL="$3"
    AUTO_COMMAND_START="$(date +"%s")"
    AUTO_COMMAND_DIR="$(pwd)"
}

function _auto_notify_reset_tracking() {
    # Command start time in seconds since epoch
    unset AUTO_COMMAND_START
    # Full command that the user has executed after alias expansion
    unset AUTO_COMMAND_FULL
    # Command that the user has executed
    unset AUTO_COMMAND
}

function disable_auto_notify() {
    add-zsh-hook -D preexec _auto_notify_track
    add-zsh-hook -D precmd _auto_notify_send
}

function enable_auto_notify() {
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _auto_notify_track
    add-zsh-hook precmd _auto_notify_send
}

_auto_notify_reset_tracking


platform="$(uname)"
if [[ "$platform" == "Linux" ]] && ! type notify-send > /dev/null; then
    printf "'notify-send' must be installed for zsh-auto-notify to work\n"
    printf "Please install it with your relevant package manager\n"
else
    enable_auto_notify
fi
